from __future__ import annotations

import json

from .groq_client import GroqClient
from .utils import parse_ai_json


class ShortScriptWriter:
    def __init__(self, groq_client: GroqClient | None = None):
        self.groq_client = groq_client

    def write(self, problem: str, guide_markdown: str, blogger_url: str | None) -> dict:
        url = blogger_url or "Blogger draft oluşturulunca buraya rehber linki eklenecek."
        if self.groq_client and self.groq_client.is_configured():
            prompt = f"""
Konu: {problem}
Blogger URL: {url}
Rehberden 35-45 saniyelik Türkçe YouTube Shorts scripti ve metadata JSON üret.
Kurallar: İlk 2 saniyede güçlü hook; çözümün en az %70'i videoda verilsin; 3 pratik adım olsun; abartı ve "kesin çözüm" yok.
Son cümle aynen: “Detaylı adım adım çözüm rehberini açıklamadaki linke bıraktım.”
JSON şeması:
{{"title":"...","description":"...","hashtags":["#teknoloji","#çözüm","#shorts"],"pinned_comment":"...","script":"...","cta":"..."}}
Rehber:
{guide_markdown[:5000]}
"""
            data = parse_ai_json(self.groq_client.chat([{"role": "user", "content": prompt}], temperature=0.35))
            return self._normalize(data, url)
        return self._fallback(problem, url)

    def _fallback(self, problem: str, url: str) -> dict:
        script = (
            f"{problem} yaşıyorsan önce panik yapma. İlk adım: interneti değiştir, uygulamayı tamamen kapatıp yeniden aç. "
            "İkinci adım: uygulama güncellemesini ve gerekli izinleri kontrol et. Üçüncü adım: Android'de önbelleği temizle, "
            "iPhone'da uygulamayı güncelle ve cihazı yeniden başlat. Ödeme veya hesap sorunu varsa yalnızca resmi uygulamadan "
            "limitleri ve güvenlik uyarılarını kontrol et; kimseyle şifre, SMS kodu veya kart bilgisi paylaşma. "
            "Detaylı adım adım çözüm rehberini açıklamadaki linke bıraktım."
        )
        description = (
            "Detaylı adım adım çözüm rehberi:\n"
            f"{url}\n\n"
            "Not: Bu rehber bilgilendirme amaçlıdır. Ödeme/kart/hesap sorunlarında kimseyle şifre, SMS kodu veya kart bilgisi paylaşmayın.\n\n"
            "Her gün 1 dakikada teknoloji, uygulama ve ödeme sorunları için abone ol."
        )
        return {
            "title": f"{problem} nasıl çözülür?",
            "description": description,
            "hashtags": ["#teknoloji", "#çözüm", "#shorts"],
            "pinned_comment": f"Detaylı rehber: {url}",
            "script": script,
            "cta": "Detaylı adım adım çözüm rehberini açıklamadaki linke bıraktım.",
        }

    def _normalize(self, data: dict, url: str) -> dict:
        data.setdefault("hashtags", ["#teknoloji", "#çözüm", "#shorts"])
        data.setdefault("cta", "Detaylı adım adım çözüm rehberini açıklamadaki linke bıraktım.")
        data["description"] = (
            "Detaylı adım adım çözüm rehberi:\n"
            f"{url}\n\n"
            "Not: Bu rehber bilgilendirme amaçlıdır. Ödeme/kart/hesap sorunlarında kimseyle şifre, SMS kodu veya kart bilgisi paylaşmayın.\n\n"
            "Her gün 1 dakikada teknoloji, uygulama ve ödeme sorunları için abone ol."
        )
        return data

    @staticmethod
    def as_text(metadata: dict) -> str:
        return json.dumps(metadata, ensure_ascii=False, indent=2)
