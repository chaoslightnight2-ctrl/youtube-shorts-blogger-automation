from datetime import UTC, datetime

from src.youtube_uploader import YouTubeUploader, metadata_to_youtube_fields


def test_youtube_body_for_shorts_and_scheduled_private():
    uploader = YouTubeUploader("client_secret.json", "refresh-token", category_id="28")

    body = uploader.build_request_body(
        title="Instagram mesaj gitmiyor",
        description="Detayli rehber",
        tags=["#teknoloji", "#shorts", "#cozum"],
        privacy_status="unlisted",
        publish_at=datetime(2026, 5, 12, 9, 0, tzinfo=UTC),
    )

    assert body["snippet"]["title"] == "Instagram mesaj gitmiyor #shorts"
    assert body["snippet"]["categoryId"] == "28"
    assert body["snippet"]["tags"] == ["teknoloji", "shorts", "cozum"]
    assert body["status"]["privacyStatus"] == "private"
    assert body["status"]["publishAt"] == "2026-05-12T09:00:00Z"
    assert body["status"]["selfDeclaredMadeForKids"] is False


def test_metadata_to_youtube_fields():
    title, description, tags = metadata_to_youtube_fields(
        {"title": "Baslik", "description": "Aciklama", "hashtags": ["#a", "#b"]}
    )

    assert title == "Baslik"
    assert description == "Aciklama"
    assert tags == ["#a", "#b"]
