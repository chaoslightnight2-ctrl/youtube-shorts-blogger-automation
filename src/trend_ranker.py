from __future__ import annotations

from .groq_client import GroqClient
from .utils import parse_ai_json


PROMPT = """Aşağıdaki trendleri “1 Dakikada Tech Çözüm” YouTube Shorts + Blogger rehber sistemi için analiz et.

Amaç:
Gerçekten çözüm aranan, kısa videoda anlatılabilecek, detaylı Blogger rehberine tıklama ihtimali olan, güvenli ve evergreen potansiyeli yüksek konuları seçmek.

Her trend için JSON döndür:
[
  {
    "trend": "...",
    "canonical_problem": "...",
    "category": "app_error/payment_error/phone_problem/social_media_problem/gaming_error/youtube_creator_problem/general_tech_problem/other",
    "problem_intent_score": 0-100,
    "shorts_potential": 0-100,
    "link_click_potential": 0-100,
    "evergreen_score": 0-100,
    "policy_risk": 0-100,
    "final_score": 0-100,
    "reason": "kısa gerekçe"
  }
]

Puanlama:
final_score = problem_intent_score * 0.35 + shorts_potential * 0.20 + link_click_potential * 0.20 + evergreen_score * 0.15 - policy_risk * 0.30

Kurallar:
- Riskli konuları düşük puanla.
- Sağlık/hukuk/siyaset/felaket/hack/crack/bahis gibi konuları ele.
- Aynı kullanıcı ihtiyacını temsil eden trendleri canonical_problem altında birleştir.
- Türkçe yanıt ver.
- Sadece JSON döndür.
"""


class TrendRanker:
    def __init__(self, groq_client: GroqClient | None = None):
        self.groq_client = groq_client

    def score(self, trends: list[dict]) -> list[dict]:
        if self.groq_client and self.groq_client.is_configured():
            trend_text = "\n".join(f"- {t['trend']}" for t in trends)
            text = self.groq_client.chat([{"role": "system", "content": PROMPT}, {"role": "user", "content": trend_text}], temperature=0.2)
            data = parse_ai_json(text)
            if isinstance(data, dict):
                data = data.get("items") or data.get("trends") or []
            return self._merge_sources(data, trends)
        return self.heuristic_score(trends)

    def heuristic_score(self, trends: list[dict]) -> list[dict]:
        scored = []
        for item in trends:
            title = item["trend"]
            low = title.lower()
            category = "general_tech_problem"
            if any(w in low for w in ["ödeme", "kart", "papara", "nays"]):
                category = "payment_error"
            elif any(w in low for w in ["instagram", "discord", "capcut"]):
                category = "app_error"
            elif any(w in low for w in ["iphone", "xiaomi", "wi-fi"]):
                category = "phone_problem"
            elif "shorts" in low:
                category = "youtube_creator_problem"
            base = 80 if any(w in low for w in ["olmuyor", "çalışmıyor", "gitmiyor", "hatası", "başarısız", "bekleniyor", "çıkmıyor", "onaylanmadı"]) else 62
            scored.append({
                **item,
                "canonical_problem": title,
                "category": category,
                "problem_intent_score": base,
                "shorts_potential": 78,
                "link_click_potential": 74,
                "evergreen_score": 72,
                "policy_risk": 15 if category == "payment_error" else 5,
                "final_score": base * 0.35 + 78 * 0.20 + 74 * 0.20 + 72 * 0.15 - (15 if category == "payment_error" else 5) * 0.30,
                "reason": "Heuristik MVP puanlaması; Groq yapılandırılınca AI puanlama kullanılır.",
            })
        return scored

    @staticmethod
    def _merge_sources(data: list[dict], originals: list[dict]) -> list[dict]:
        by_title = {o["trend"].lower(): o for o in originals}
        merged = []
        for row in data:
            source = by_title.get(str(row.get("trend", "")).lower(), {})
            merged.append({**source, **row})
        return merged
