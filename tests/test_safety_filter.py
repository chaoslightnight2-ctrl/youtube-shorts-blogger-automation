from src.safety_filter import SafetyFilter


def test_safe_topic():
    assert SafetyFilter().classify("instagram açılmıyor").status == "safe"


def test_payment_sensitive():
    assert SafetyFilter().classify("papara ödeme başarısız").status == "safe_but_sensitive"


def test_blocked_topics():
    sf = SafetyFilter()
    assert sf.classify("apk crack indir").status == "blocked"
    assert sf.classify("hesap şifre kırma").status == "blocked"
    assert sf.classify("bahis sitesi ödeme sorunu").status == "blocked"
    assert sf.classify("ilaç dozu nasıl ayarlanır").status == "blocked"
