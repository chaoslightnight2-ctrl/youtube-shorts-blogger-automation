from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import sys

from src.blogger_publisher import BloggerPublisher
from src.config import load_config
from src.db import Database
from src.duplicate_guard import DuplicateGuard
from src.groq_client import GroqClient
from src.guide_writer import GuideWriter
from src.html_renderer import HtmlRenderer
from src.logger import setup_logger
from src.safety_filter import SafetyFilter
from src.short_script_writer import ShortScriptWriter
from src.short_video_builder import ShortVideoBuilder
from src.trend_ranker import TrendRanker
from src.trend_sources import collect_trends
from src.utils import ensure_dirs, make_slug, timestamp_for_filename, utc_now_iso, write_json
from src.youtube_uploader import YouTubeUploader, metadata_to_youtube_fields


BASE_DIR = Path(__file__).resolve().parent
DEMO_TRENDS = [
    "Instagram mesaj gitmiyor",
    "Nays odeme onaylanmadi",
    "YouTube Shorts izlenme var para yok",
    "CapCut altyazi cikmiyor",
    "Xiaomi Wi-Fi baglanmiyor",
    "Papara kart odeme basarisiz",
    "Discord mikrofon calismiyor",
    "Valorant VAN hatasi",
    "iPhone sarj olmuyor",
    "Google Play indirme bekleniyor",
]


def build_services():
    cfg = load_config(BASE_DIR)
    ensure_dirs(BASE_DIR, cfg.outputs_dir)
    logger = setup_logger(BASE_DIR)
    db = Database(BASE_DIR / "data" / "automation.db")
    groq = GroqClient(cfg.groq_api_key, cfg.groq_base_url, cfg.groq_model, logger)
    return cfg, logger, db, groq


def seed_demo() -> None:
    (BASE_DIR / "manual_trends.txt").write_text("\n".join(DEMO_TRENDS) + "\n", encoding="utf-8")
    print("manual_trends.txt demo trendlerle dolduruldu.")


def test_groq() -> int:
    _cfg, logger, _db, groq = build_services()
    if not groq.is_configured():
        print("GROQ_API_KEY tanimli degil.")
        return 1
    try:
        answer = groq.chat([{"role": "user", "content": 'Sadece JSON dondur: {"ok": true}'}], temperature=0)
        print(answer)
        return 0
    except Exception as exc:
        logger.exception("Groq auth test basarisiz.")
        print(f"Groq test basarisiz: {exc}")
        return 1


def test_blogger_auth() -> int:
    cfg, _logger, _db, _groq = build_services()
    publisher = BloggerPublisher(cfg.blogger_blog_id, cfg.google_client_secret_file, cfg.google_token_file, BASE_DIR, cfg.google_refresh_token)
    try:
        publisher.authenticate()
        print("Blogger OAuth basarili. token.json hazir.")
        return 0
    except Exception as exc:
        print(f"Blogger auth basarisiz: {exc}")
        return 1


def run_pipeline(no_blogger: bool = False, publish_now: bool = False) -> int:
    cfg, logger, db, groq = build_services()
    run_id = db.start_run()
    selected_topic_id = None
    try:
        logger.info("Otomasyon basladi. run_id=%s", run_id)
        trends = collect_trends(BASE_DIR, logger, cfg.max_trends_to_collect)
        logger.info("%d trend bulundu.", len(trends))
        safety = SafetyFilter()
        safe_trends: list[dict] = []
        guard = DuplicateGuard(db=db, groq_client=groq, threshold=cfg.duplicate_similarity_threshold, recent_days=cfg.recent_duplicate_days)

        for item in trends:
            result = safety.classify(item["trend"])
            if result.status == "blocked":
                db.add_blocked_topic(guard.normalize(item["trend"]), result.reason)
                continue
            item["safety_status"] = result.status
            item["category_hint"] = result.category_hint
            safe_trends.append(item)
        logger.info("%d trend safety filter'dan gecti.", len(safe_trends))
        if not safe_trends:
            raise RuntimeError("Uretime uygun trend bulunamadi.")

        ranked = TrendRanker(groq).score(safe_trends[: cfg.max_candidates_to_score])
        ranked = sorted(ranked, key=lambda row: float(row.get("final_score", 0)), reverse=True)
        selected = None
        selected_candidate_id = None
        selected_safety = "safe"
        for row in ranked:
            row["source"] = row.get("source") or next((t.get("source") for t in safe_trends if t["trend"] == row.get("trend")), "unknown")
            candidate_id = db.insert_candidate(run_id, row)
            if float(row.get("final_score", 0)) < cfg.min_final_score:
                continue
            problem = row.get("canonical_problem") or row.get("trend")
            dup = guard.is_duplicate(problem)
            logger.info("Duplicate kontrol: %s -> %s (%s)", problem, dup.is_duplicate, dup.reason)
            if not dup.is_duplicate:
                selected = row
                selected_candidate_id = candidate_id
                match = next((t for t in safe_trends if t["trend"] == row.get("trend")), {})
                selected_safety = match.get("safety_status", "safe")
                break
        if not selected:
            raise RuntimeError("Duplicate olmayan ve skor esigini gecen konu bulunamadi.")
        db.mark_candidate_selected(selected_candidate_id)
        logger.info("Secilen konu: %s", selected.get("canonical_problem"))

        problem = selected.get("canonical_problem") or selected["trend"]
        sensitive = selected_safety == "safe_but_sensitive" or selected.get("category") == "payment_error"
        slug = make_slug(problem)
        stamp = timestamp_for_filename()
        outputs = BASE_DIR / cfg.outputs_dir

        guide_md = GuideWriter(groq).write(selected, sensitive=sensitive)
        md_path = outputs / "guides" / f"{stamp}_{slug}.md"
        html_path = outputs / "guides" / f"{stamp}_{slug}.html"
        md_path.write_text(guide_md, encoding="utf-8")
        html_content = HtmlRenderer(BASE_DIR / "templates").render(guide_md, f"{problem} Cozumu")
        html_path.write_text(html_content, encoding="utf-8")
        logger.info("Rehber dosyalari yazildi: %s / %s", md_path, html_path)

        blogger_result = {"status": "skipped", "post_id": None, "url": None, "raw_response": {}}
        if not no_blogger:
            try:
                publisher = BloggerPublisher(cfg.blogger_blog_id, cfg.google_client_secret_file, cfg.google_token_file, BASE_DIR, cfg.google_refresh_token)
                result = publisher.create_post(f"{problem} Cozumu", html_content, cfg.default_labels, is_draft=not publish_now)
                blogger_result = {"status": result.status, "post_id": result.post_id, "url": result.url, "raw_response": result.raw_response}
                logger.info("Blogger post: id=%s url=%s", result.post_id, result.url)
            except Exception as exc:
                logger.exception("Blogger draft olusturulamadi, lokal dosyalar korunuyor.")
                db.log_error(run_id, "blogger", str(exc))
                blogger_result = {"status": "failed", "post_id": None, "url": None, "error": str(exc), "raw_response": {}}

        blogger_path = outputs / "blogger" / f"{stamp}_{slug}_blogger_response.json"
        write_json(blogger_path, blogger_result)
        metadata = ShortScriptWriter(groq).write(problem, guide_md, blogger_result.get("url"))
        script_path = outputs / "scripts" / f"{stamp}_{slug}_script.txt"
        metadata_path = outputs / "metadata" / f"{stamp}_{slug}_metadata.json"
        script_path.write_text(metadata["script"], encoding="utf-8")
        write_json(metadata_path, metadata)
        logger.info("Script ve metadata yazildi: %s / %s", script_path, metadata_path)

        selected_topic_id = db.add_produced_topic({
            "canonical_slug": slug,
            "canonical_problem": problem,
            "normalized_problem": guard.normalize(problem),
            "topic_fingerprint": guard.fingerprint(problem),
            "source_trend": selected.get("trend"),
            "final_score": selected.get("final_score"),
            "guide_md_path": str(md_path),
            "guide_html_path": str(html_path),
            "short_script_path": str(script_path),
            "metadata_path": str(metadata_path),
            "blogger_post_id": blogger_result.get("post_id"),
            "blogger_url": blogger_result.get("url"),
            "publish_status": blogger_result.get("status"),
            "created_at": utc_now_iso(),
        })
        db.finish_run(run_id, "completed", selected_topic_id)
        print("Otomasyon tamamlandi.")
        print(f"Markdown: {md_path}")
        print(f"HTML: {html_path}")
        print(f"Script: {script_path}")
        print(f"Metadata: {metadata_path}")
        print(f"Blogger response: {blogger_path}")
        if blogger_result.get("url"):
            print(f"Blogger URL: {blogger_result['url']}")
        elif blogger_result.get("post_id"):
            print(f"Blogger draft id: {blogger_result['post_id']}")
        return 0
    except Exception as exc:
        logger.exception("Otomasyon hata ile bitti.")
        db.log_error(run_id, "pipeline", str(exc))
        db.finish_run(run_id, "failed", selected_topic_id, str(exc))
        print(f"Otomasyon basarisiz: {exc}")
        return 1


def list_produced() -> None:
    _cfg, _logger, db, _groq = build_services()
    rows = db.list_produced()
    if not rows:
        print("Henuz uretilmis konu yok.")
        return
    for row in rows:
        print(f"{row['id']} | {row['created_at']} | {row['canonical_problem']} | {row['publish_status']} | {row['blogger_url'] or row['blogger_post_id'] or '-'}")


def check_duplicate(topic: str) -> None:
    cfg, _logger, db, groq = build_services()
    guard = DuplicateGuard(db=db, groq_client=groq, threshold=cfg.duplicate_similarity_threshold, recent_days=cfg.recent_duplicate_days)
    result = guard.is_duplicate(topic)
    print(f"duplicate={result.is_duplicate} similarity={result.similarity:.1f} matched={result.matched_problem} reason={result.reason}")


def render_short(metadata_path: str, slug: str | None = None) -> int:
    cfg, _logger, _db, _groq = build_services()
    if not cfg.pexels_api_key:
        print("PEXELS_API_KEY tanimli degil.")
        return 1
    metadata_file = Path(metadata_path)
    metadata = json.loads(metadata_file.read_text(encoding="utf-8"))
    output_slug = slug or make_slug(str(metadata.get("title") or metadata_file.stem))
    builder = ShortVideoBuilder(
        cfg.pexels_api_key,
        BASE_DIR / cfg.outputs_dir / "videos",
        BASE_DIR / "fonts",
        voice=cfg.voice,
        voice_rate=cfg.voice_rate,
        voice_pitch=cfg.voice_pitch,
    )
    rendered = builder.render_from_metadata(metadata, output_slug)
    print(f"Video: {rendered.video_path}")
    print(f"Audio: {rendered.audio_path}")
    print(f"Background: {rendered.background_path}")
    return 0


def upload_short(video_path: str, metadata_path: str, privacy_status: str = "private", publish_at: str | None = None) -> int:
    cfg, _logger, _db, _groq = build_services()
    if not cfg.youtube_refresh_token:
        print("YOUTUBE_REFRESH_TOKEN veya GOOGLE_REFRESH_TOKEN tanimli degil.")
        return 1
    metadata = json.loads(Path(metadata_path).read_text(encoding="utf-8"))
    title, description, tags = metadata_to_youtube_fields(metadata)
    scheduled_at = datetime.fromisoformat(publish_at) if publish_at else None
    uploader = YouTubeUploader(
        cfg.google_client_secret_file,
        cfg.youtube_refresh_token,
        BASE_DIR,
        category_id=cfg.youtube_category_id,
    )
    result = uploader.upload(
        Path(video_path),
        title=title,
        description=description,
        tags=tags,
        privacy_status=privacy_status,
        publish_at=scheduled_at,
    )
    print(f"YouTube upload tamamlandi: {result.youtube_url}")
    if result.publish_at_utc:
        print(f"PublishAt UTC: {result.publish_at_utc}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="YouTube Shorts + Blogger otomasyon sistemi")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("seed-demo")
    run_p = sub.add_parser("run")
    run_p.add_argument("--no-blogger", action="store_true")
    run_p.add_argument("--publish-now", action="store_true", help="Blogger postunu draft yerine yayinla. Varsayilan drafttir.")
    sub.add_parser("list-produced")
    dup = sub.add_parser("check-duplicate")
    dup.add_argument("topic")
    sub.add_parser("test-blogger-auth")
    sub.add_parser("test-groq")
    render_p = sub.add_parser("render-short")
    render_p.add_argument("--metadata", required=True)
    render_p.add_argument("--slug")
    upload_p = sub.add_parser("upload-short")
    upload_p.add_argument("video_path")
    upload_p.add_argument("--metadata", required=True)
    upload_p.add_argument("--privacy", choices=["private", "unlisted", "public"], default="private")
    upload_p.add_argument("--publish-at", help="ISO tarih/saat. Verilirse video private olarak zamanlanir.")
    args = parser.parse_args(argv)
    if args.command == "seed-demo":
        seed_demo()
        return 0
    if args.command == "run":
        return run_pipeline(no_blogger=args.no_blogger, publish_now=args.publish_now)
    if args.command == "list-produced":
        list_produced()
        return 0
    if args.command == "check-duplicate":
        check_duplicate(args.topic)
        return 0
    if args.command == "test-blogger-auth":
        return test_blogger_auth()
    if args.command == "test-groq":
        return test_groq()
    if args.command == "render-short":
        return render_short(args.metadata, args.slug)
    if args.command == "upload-short":
        return upload_short(args.video_path, args.metadata, args.privacy, args.publish_at)
    return 1


if __name__ == "__main__":
    sys.exit(main())
