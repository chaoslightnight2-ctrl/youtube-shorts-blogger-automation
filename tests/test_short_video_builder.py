from src.short_video_builder import ShortVideoBuilder, chunk_timestamps


def test_chunk_timestamps_groups_short_caption_lines():
    chunks = chunk_timestamps(
        [
            (0.0, 0.2, "Instagram"),
            (0.2, 0.2, "mesaj"),
            (0.4, 0.2, "gitmiyor"),
            (0.6, 0.2, "cozumu"),
        ]
    )

    assert chunks[0][2] == "Instagram mesaj gitmiyor"
    assert chunks[1][2] == "cozumu"


def test_background_queries_use_metadata_keywords():
    builder = ShortVideoBuilder("pexels-key", "outputs/videos", "fonts")

    queries = builder.build_background_queries({"title": "Instagram mesaj gitmiyor", "script": "Telefon uygulama sorunu"})

    assert "vertical smartphone social media" in queries
    assert "smartphone troubleshooting" in queries
