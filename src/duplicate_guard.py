from __future__ import annotations

from dataclasses import dataclass
import re
import unicodedata

from rapidfuzz import fuzz

from .utils import make_slug, parse_ai_json


@dataclass(frozen=True)
class DuplicateResult:
    is_duplicate: bool
    reason: str
    matched_problem: str | None = None
    similarity: float = 0.0


class DuplicateGuard:
    stop_phrases = [
        "çözümü", "cozumu", "nasıl çözülür", "nasil cozulur", "hatası", "hatasi",
        "sorunu", "neden", "olmuyor", "açılmıyor", "acilmiyor", "çalışmıyor",
        "calismiyor", "ne yapmalı", "ne yapmali", "gönderilmiyor", "gonderilmiyor",
    ]
    synonym_groups = [
        ("dm", "mesaj"),
        ("gitmiyor", "gonderilmiyor", "gönderilmiyor"),
    ]
    phrase_synonyms = {
        "kart reddedildi": "payment_failed",
        "odeme onaylanmadi": "payment_failed",
        "odeme basarisiz": "payment_failed",
        "odeme basarisiz oldu": "payment_failed",
    }

    def __init__(self, db=None, groq_client=None, threshold: int = 86, recent_days: int = 60):
        self.db = db
        self.groq_client = groq_client
        self.threshold = threshold
        self.recent_days = recent_days

    @staticmethod
    def ascii_fold(text: str) -> str:
        mapping = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")
        return unicodedata.normalize("NFKD", text.translate(mapping)).encode("ascii", "ignore").decode("ascii")

    def normalize(self, text: str) -> str:
        value = self.ascii_fold(text.lower())
        value = re.sub(r"[^a-z0-9\s]", " ", value)
        for phrase in self.stop_phrases:
            value = value.replace(self.ascii_fold(phrase.lower()), " ")
        value = re.sub(r"\s+", " ", value).strip()
        return value

    def fingerprint(self, text: str) -> str:
        normalized = self.normalize(text)
        for phrase, canonical in self.phrase_synonyms.items():
            normalized = normalized.replace(phrase, canonical)
        tokens = normalized.split()
        for group in self.synonym_groups:
            canonical = self.normalize(group[0])
            group_tokens = {self.normalize(g) for g in group}
            tokens = [canonical if token in group_tokens else token for token in tokens]
        return " ".join(sorted(set(tokens)))

    def compare_texts(self, new_problem: str, existing_problem: str) -> DuplicateResult:
        new_fp = self.fingerprint(new_problem)
        old_fp = self.fingerprint(existing_problem)
        similarity = max(fuzz.token_set_ratio(new_fp, old_fp), fuzz.token_sort_ratio(new_fp, old_fp))
        if similarity >= self.threshold:
            return DuplicateResult(True, "Fuzzy/fingerprint benzerligi esik ustunde.", existing_problem, similarity)
        if new_fp == old_fp and new_fp:
            return DuplicateResult(True, "Ayni fingerprint.", existing_problem, 100.0)
        if 75 <= similarity < self.threshold:
            return DuplicateResult(False, "Borderline benzerlik; AI kontrolu gerekebilir.", existing_problem, similarity)
        return DuplicateResult(False, "Duplicate gorunmuyor.", existing_problem, similarity)

    def is_duplicate(self, canonical_problem: str) -> DuplicateResult:
        slug = make_slug(canonical_problem)
        if self.db and self.db.slug_exists(slug):
            return DuplicateResult(True, "Canonical slug daha once uretildi.", canonical_problem, 100.0)
        rows = self.db.produced_recent(self.recent_days) if self.db else []
        borderline: DuplicateResult | None = None
        for row in rows:
            result = self.compare_texts(canonical_problem, row["canonical_problem"])
            if result.is_duplicate:
                return result
            if 75 <= result.similarity < self.threshold and borderline is None:
                borderline = result
        if borderline and self.groq_client and self.groq_client.is_configured():
            prompt = (
                "Bu iki problem aynı kullanıcı ihtiyacını mı çözüyor? Sadece JSON döndür: "
                '{"is_duplicate": true/false, "reason": "..."}\n'
                f"Problem A: {canonical_problem}\nProblem B: {borderline.matched_problem}"
            )
            try:
                answer = self.groq_client.chat([{"role": "user", "content": prompt}], temperature=0)
                data = parse_ai_json(answer)
                if bool(data.get("is_duplicate")):
                    return DuplicateResult(True, data.get("reason", "AI duplicate dedi."), borderline.matched_problem, borderline.similarity)
            except Exception:
                pass
        return borderline or DuplicateResult(False, "Duplicate bulunmadi.", None, 0.0)
