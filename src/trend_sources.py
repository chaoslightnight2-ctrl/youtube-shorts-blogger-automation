from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import logging
from urllib.parse import quote_plus

from bs4 import BeautifulSoup
import requests

from .utils import utc_now_iso


@dataclass
class TrendItem:
    title: str
    source: str
    source_url: str = ""
    collected_at: str = ""

    def to_dict(self) -> dict:
        return {"raw_title": self.title, "trend": self.title, "source": self.source, "source_url": self.source_url, "collected_at": self.collected_at or utc_now_iso()}


class ManualSeedProvider:
    name = "manual_seed"

    def __init__(self, path: Path):
        self.path = path

    def collect(self) -> list[TrendItem]:
        if not self.path.exists():
            return []
        return [TrendItem(line.strip(), self.name, str(self.path)) for line in self.path.read_text(encoding="utf-8").splitlines() if line.strip()]


class GoogleTrendsLightProvider:
    name = "google_trends_light"

    def collect(self) -> list[TrendItem]:
        url = "https://trends.google.com/trends/trendingsearches/daily?geo=TR"
        resp = requests.get(url, timeout=8, headers={"User-Agent": "Mozilla/5.0"})
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")
        texts = [t.get_text(" ", strip=True) for t in soup.select(".title, .feed-item-header, a")][:20]
        return [TrendItem(text, self.name, url) for text in texts if len(text) > 3]


class SearchSuggestionProvider:
    name = "search_suggestion"
    seeds = ["instagram", "papara", "nays", "youtube shorts", "capcut", "xiaomi", "discord", "google play"]

    def collect(self) -> list[TrendItem]:
        items: list[TrendItem] = []
        for seed in self.seeds:
            url = f"https://suggestqueries.google.com/complete/search?client=firefox&hl=tr&q={quote_plus(seed + ' sorun')}"
            try:
                resp = requests.get(url, timeout=5, headers={"User-Agent": "Mozilla/5.0"})
                resp.raise_for_status()
                data = resp.json()
                items.extend(TrendItem(str(s), self.name, url) for s in data[1][:5])
            except Exception:
                continue
        return items


def collect_trends(base_dir: Path, logger: logging.Logger, max_items: int) -> list[dict]:
    providers = [ManualSeedProvider(base_dir / "manual_trends.txt"), GoogleTrendsLightProvider(), SearchSuggestionProvider()]
    seen: set[str] = set()
    results: list[dict] = []
    for provider in providers:
        logger.info("Trend source basladi: %s", provider.name)
        try:
            items = provider.collect()
            logger.info("Trend source bitti: %s (%d)", provider.name, len(items))
        except Exception as exc:
            logger.warning("Trend source hata verdi: %s - %s", provider.name, exc)
            continue
        for item in items:
            key = item.title.lower().strip()
            if key and key not in seen:
                seen.add(key)
                results.append(item.to_dict())
            if len(results) >= max_items:
                return results
    return results
