from pathlib import Path

from src.html_renderer import HtmlRenderer


def test_html_renderer_outputs_expected_sections():
    renderer = HtmlRenderer(Path(__file__).resolve().parents[1] / "templates")
    html = renderer.render("# Başlık\n\n## Kısa cevap\n<script>alert(1)</script>", "Başlık")
    assert "<h1>Başlık</h1>" in html
    assert "Kısa Cevap" in html
    assert "<!-- ADSENSE_SLOT_AFTER_INTRO -->" in html
    assert "<!-- ADSENSE_SLOT_MID_CONTENT -->" in html
    assert "<!-- ADSENSE_SLOT_BEFORE_FAQ -->" in html
    assert "<script>" not in html
