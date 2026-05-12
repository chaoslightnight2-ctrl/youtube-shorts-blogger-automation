from __future__ import annotations

import asyncio
from dataclasses import dataclass
import re
from pathlib import Path
from typing import Any

import requests


VIDEO_SIZE = (1080, 1920)
MAX_CAPTION_WORDS = 3
MAX_CAPTION_DURATION = 0.75
FONT_SIZE = 58
STROKE_WIDTH = 4
FONT_URL = "https://github.com/google/fonts/raw/main/ofl/montserrat/static/Montserrat-Bold.ttf"

BACKGROUND_HINTS = {
    "instagram": ["vertical smartphone social media", "phone social media app", "person using instagram phone"],
    "dm": ["phone messaging app", "smartphone chat app", "typing message phone"],
    "mesaj": ["phone messaging app", "smartphone chat app", "typing message phone"],
    "youtube": ["youtube creator setup", "vertical video recording phone", "content creator editing video"],
    "shorts": ["vertical video recording phone", "content creator editing video", "smartphone video app"],
    "capcut": ["mobile video editing", "creator editing video", "video editing timeline"],
    "discord": ["gaming headset microphone", "gaming setup keyboard", "computer voice chat"],
    "mikrofon": ["microphone headset gaming", "computer microphone setup", "voice chat headset"],
    "xiaomi": ["android phone settings", "smartphone close up", "wifi router phone"],
    "iphone": ["iphone charging cable", "iphone settings", "smartphone close up"],
    "sarj": ["phone charging cable", "smartphone battery charging", "charging phone close up"],
    "wifi": ["wifi router smartphone", "home wifi router", "phone wifi settings"],
    "google play": ["android app store phone", "smartphone downloading app", "android phone app"],
    "play store": ["android app store phone", "smartphone downloading app", "android phone app"],
    "papara": ["mobile payment phone", "contactless payment phone", "online payment smartphone"],
    "nays": ["mobile payment phone", "contactless payment phone", "online payment smartphone"],
    "odeme": ["mobile payment phone", "contactless payment phone", "online payment smartphone"],
    "kart": ["credit card smartphone", "contactless payment phone", "online payment smartphone"],
    "valorant": ["gaming keyboard setup", "pc gaming setup", "esports gaming monitor"],
    "hata": ["computer error screen", "phone error notification", "troubleshooting laptop"],
    "acilmiyor": ["phone app error", "smartphone troubleshooting", "app loading phone"],
}


@dataclass
class RenderedShort:
    video_path: Path
    audio_path: Path
    background_path: Path


class ShortVideoBuilder:
    def __init__(self, pexels_api_key: str, output_dir: Path | str, font_dir: Path | str, voice: str = "tr-TR-AhmetNeural", voice_rate: str = "+8%", voice_pitch: str = "-3Hz"):
        self.pexels_api_key = pexels_api_key
        self.output_dir = Path(output_dir)
        self.font_dir = Path(font_dir)
        self.font_path = self.font_dir / "Montserrat-Bold.ttf"
        self.voice = voice
        self.voice_rate = voice_rate
        self.voice_pitch = voice_pitch

    def render_from_metadata(self, metadata: dict[str, Any], slug: str = "short") -> RenderedShort:
        script = str(metadata.get("script") or "").strip()
        if not script:
            raise RuntimeError("Metadata icinde script bulunamadi.")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        audio_path = self.output_dir / f"{slug}_voiceover.mp3"
        background_path = self.output_dir / f"{slug}_background.mp4"
        video_path = self.output_dir / f"{slug}.mp4"
        word_ts = asyncio.run(self.create_voiceover(script, audio_path))
        self.download_background_video(metadata, background_path)
        self.assemble_video(background_path, audio_path, video_path, word_ts)
        return RenderedShort(video_path=video_path, audio_path=audio_path, background_path=background_path)

    async def create_voiceover(self, script: str, audio_path: Path) -> list[tuple[float, float, str]]:
        import edge_tts
        communicate = edge_tts.Communicate(script, self.voice, rate=self.voice_rate, pitch=self.voice_pitch)
        word_timestamps: list[tuple[float, float, str]] = []
        with open(audio_path, "wb") as file:
            async for chunk in communicate.stream():
                if chunk["type"] == "audio":
                    file.write(chunk["data"])
                elif chunk["type"] == "WordBoundary":
                    word_timestamps.append((chunk["offset"] / 10_000_000, chunk["duration"] / 10_000_000, chunk["text"]))
        if not audio_path.exists() or audio_path.stat().st_size == 0:
            raise RuntimeError("Ses dosyasi olusmadi.")
        if word_timestamps:
            return word_timestamps
        from moviepy.editor import AudioFileClip
        audio_clip = AudioFileClip(str(audio_path))
        total_duration = max(float(audio_clip.duration), 1.0)
        audio_clip.close()
        words = [word for word in script.split() if word.strip()]
        total_chars = sum(max(len(word), 1) for word in words) or 1
        current = 0.05
        usable_duration = max(total_duration - 0.1, 0.5)
        for word in words:
            duration = max(usable_duration * (max(len(word), 1) / total_chars), 0.16)
            word_timestamps.append((current, duration, word))
            current += duration
        return word_timestamps

    def build_background_queries(self, metadata: dict[str, Any]) -> list[str]:
        text = normalize_text(" ".join(str(metadata.get(key) or "") for key in ["title", "description", "script"]))
        queries: list[str] = []
        for key, mapped in BACKGROUND_HINTS.items():
            if key in text:
                queries.extend(mapped)
        keywords = extract_keywords(text)
        if len(keywords) >= 2:
            queries.append(f"{keywords[0]} {keywords[1]} smartphone problem")
            queries.append(f"{keywords[0]} {keywords[1]} troubleshooting")
        if keywords:
            queries.append(f"{keywords[0]} mobile app problem")
        queries.extend(["smartphone troubleshooting", "phone app vertical", "person using smartphone close up", "technology help desk"])
        return list(dict.fromkeys(queries))

    def search_pexels_video(self, query: str) -> str | None:
        headers = {"Authorization": self.pexels_api_key}
        try:
            response = requests.get("https://api.pexels.com/videos/search", headers=headers, params={"query": query, "per_page": 10, "orientation": "portrait", "size": "large"}, timeout=20)
            response.raise_for_status()
            candidates: list[tuple[int, str]] = []
            for video in response.json().get("videos", []):
                for vf in video.get("video_files", []):
                    width = int(vf.get("width") or 0)
                    height = int(vf.get("height") or 0)
                    link = vf.get("link")
                    if not link or width <= 0 or height <= 0:
                        continue
                    score = width * height + (10_000_000 if height >= width else 0)
                    candidates.append((score, link))
            if candidates:
                candidates.sort(reverse=True)
                return candidates[0][1]
        except Exception:
            return None
        return None

    def download_background_video(self, metadata: dict[str, Any], output_path: Path) -> None:
        url = None
        for query in self.build_background_queries(metadata):
            url = self.search_pexels_video(query)
            if url:
                break
        if not url:
            raise RuntimeError("Uygun Pexels arka plan videosu bulunamadi.")
        with requests.get(url, stream=True, timeout=90) as response:
            response.raise_for_status()
            with open(output_path, "wb") as file:
                for chunk in response.iter_content(8192):
                    if chunk:
                        file.write(chunk)
        if output_path.stat().st_size < 200_000:
            raise RuntimeError("Arka plan videosu cok kucuk veya bozuk.")

    def ensure_font(self) -> str:
        if self.font_path.exists():
            return str(self.font_path.resolve())
        self.font_dir.mkdir(parents=True, exist_ok=True)
        try:
            with requests.get(FONT_URL, timeout=20) as response:
                response.raise_for_status()
                self.font_path.write_bytes(response.content)
            return str(self.font_path.resolve())
        except Exception:
            return "Arial-Bold"

    def assemble_video(self, background_path: Path, audio_path: Path, video_path: Path, word_ts: list[tuple[float, float, str]]) -> None:
        from moviepy.editor import AudioFileClip, CompositeVideoClip, TextClip, VideoFileClip
        from moviepy.video.fx.all import crop
        bg_clip = VideoFileClip(str(background_path))
        audio_clip = AudioFileClip(str(audio_path))
        target_duration = audio_clip.duration
        width, height = bg_clip.size
        if width / height < VIDEO_SIZE[0] / VIDEO_SIZE[1]:
            bg_clip = bg_clip.resize(width=VIDEO_SIZE[0])
            bg_clip = crop(bg_clip, y1=(bg_clip.h - VIDEO_SIZE[1]) // 2, y2=(bg_clip.h + VIDEO_SIZE[1]) // 2)
        else:
            bg_clip = bg_clip.resize(height=VIDEO_SIZE[1])
            bg_clip = crop(bg_clip, x1=(bg_clip.w - VIDEO_SIZE[0]) // 2, x2=(bg_clip.w + VIDEO_SIZE[0]) // 2)
        bg_clip = bg_clip.resize(VIDEO_SIZE)
        bg_clip = bg_clip.loop(duration=target_duration) if bg_clip.duration < target_duration else bg_clip.subclip(0, target_duration)
        bg_clip = bg_clip.set_audio(audio_clip)
        font = self.ensure_font()
        captions = []
        for start, duration, text in chunk_timestamps(word_ts):
            text = clean_caption_text(text)
            if not text:
                continue
            caption = TextClip(text, fontsize=FONT_SIZE, color="white", font=font, stroke_color="black", stroke_width=STROKE_WIDTH, method="caption" if len(text) > 12 else "label", size=(VIDEO_SIZE[0] - 180, None)).set_start(start).set_duration(duration).set_position(("center", "center"))
            captions.append(caption)
        final = CompositeVideoClip([bg_clip] + captions, size=VIDEO_SIZE)
        final.write_videofile(str(video_path), codec="libx264", audio_codec="aac", fps=30, preset="medium", threads=4, verbose=False, logger=None)
        final.close()
        audio_clip.close()
        bg_clip.close()


def normalize_text(text: str) -> str:
    text = text.lower()
    text = re.sub(r"[^\w\s]", " ", text, flags=re.UNICODE)
    return re.sub(r"\s+", " ", text).strip()


def extract_keywords(text: str, count: int = 5) -> list[str]:
    words = [word for word in normalize_text(text).split() if len(word) >= 4]
    stop = {"icin", "olan", "gore", "detayli", "cozum", "rehber", "shorts", "video", "adim"}
    words = [word for word in words if word not in stop]
    return sorted(set(words), key=len, reverse=True)[:count]


def clean_caption_word(word: str) -> str:
    return re.sub(r"[^\w'\-]+", "", str(word), flags=re.UNICODE).strip()


def clean_caption_text(text: str) -> str:
    return re.sub(r"[^\w'\- ]+", "", text, flags=re.UNICODE).strip()


def chunk_timestamps(word_ts: list[tuple[float, float, str]]) -> list[tuple[float, float, str]]:
    if not word_ts:
        return []
    chunks: list[tuple[float, float, str]] = []
    current_words: list[str] = []
    chunk_start = word_ts[0][0]
    chunk_end = word_ts[0][0]
    for start, duration, word in word_ts:
        word = clean_caption_word(word)
        if not word:
            continue
        word_end = max(start + duration, start + 0.14)
        projected_duration = word_end - chunk_start
        if current_words and (len(current_words) >= MAX_CAPTION_WORDS or projected_duration > MAX_CAPTION_DURATION):
            chunks.append((chunk_start, max(chunk_end - chunk_start, 0.16), " ".join(current_words)))
            current_words = [word]
            chunk_start = start
            chunk_end = word_end
        else:
            current_words.append(word)
            chunk_end = word_end
    if current_words:
        chunks.append((chunk_start, max(chunk_end - chunk_start, 0.16), " ".join(current_words)))
    fixed: list[tuple[float, float, str]] = []
    for index, (start, duration, text) in enumerate(chunks):
        end = start + duration
        if index + 1 < len(chunks):
            end = min(end, chunks[index + 1][0] - 0.015)
        fixed.append((start, max(end - start, 0.12), text))
    return fixed
