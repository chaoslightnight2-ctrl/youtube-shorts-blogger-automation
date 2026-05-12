from src.duplicate_guard import DuplicateGuard


def test_instagram_dm_duplicate():
    guard = DuplicateGuard(threshold=86)
    assert guard.compare_texts("Instagram DM gitmiyor", "Instagram mesaj gönderilmiyor").is_duplicate


def test_nays_payment_duplicate():
    guard = DuplicateGuard(threshold=86)
    assert guard.compare_texts("Nays ödeme onaylanmadı", "Nays kart reddedildi").is_duplicate


def test_instagram_notification_not_duplicate():
    guard = DuplicateGuard(threshold=86)
    assert not guard.compare_texts("Instagram bildirim gelmiyor", "Instagram DM gitmiyor").is_duplicate


def test_youtube_shorts_borderline_not_forced_duplicate():
    guard = DuplicateGuard(threshold=86)
    result = guard.compare_texts("YouTube Shorts para kazanma şartları", "Shorts izlenme var para yok")
    assert not result.is_duplicate
