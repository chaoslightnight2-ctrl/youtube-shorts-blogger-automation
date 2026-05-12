from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SafetyResult:
    status: str
    reason: str
    category_hint: str


class SafetyFilter:
    blocked_terms = {
        "hack": "hacking",
        "şifre kırma": "hacking",
        "sifre kirma": "hacking",
        "hesap çalma": "hacking",
        "hesap calma": "hacking",
        "crack": "piracy",
        "apk indir": "piracy",
        "bahis": "gambling",
        "kumar": "gambling",
        "+18": "adult",
        "ilaç dozu": "health",
        "ilac dozu": "health",
        "intihar": "health",
        "dava": "legal",
        "avukat": "legal",
        "seçim": "politics",
        "secim": "politics",
        "parti": "politics",
        "savaş": "disaster",
        "savas": "disaster",
        "ölüm": "death",
        "olum": "death",
        "deprem": "disaster",
        "kişisel veri": "personal_data",
        "kisisel veri": "personal_data",
        "tc kimlik": "personal_data",
        "kredi kartı bilgisi": "personal_data",
        "kredi karti bilgisi": "personal_data",
    }
    sensitive_terms = ["ödeme başarısız", "odeme basarisiz", "kart reddedildi", "banka uygulaması açılmıyor", "para gönderilmiyor", "ödeme onaylanmadı"]

    def classify(self, topic: str) -> SafetyResult:
        low = topic.lower()
        for term, category in self.blocked_terms.items():
            if term in low:
                return SafetyResult("blocked", f"Riskli kategori tespit edildi: {term}", category)
        for term in self.sensitive_terms:
            if term in low:
                return SafetyResult("safe_but_sensitive", "Ödeme/kart konusu güvenli dil gerektirir.", "payment_error")
        if any(word in low for word in ["ödeme", "odeme", "kart", "papara", "nays", "banka"]):
            return SafetyResult("safe_but_sensitive", "Finansal işlem konusu güvenli dil gerektirir.", "payment_error")
        return SafetyResult("safe", "Güvenli teknoloji çözüm konusu.", "general_tech_problem")
