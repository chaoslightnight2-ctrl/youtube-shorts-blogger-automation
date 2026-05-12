import pytest

from src.utils import JsonParseError, parse_ai_json


def test_parse_json_from_markdown_block():
    assert parse_ai_json('```json\n{"ok": true}\n```') == {"ok": True}


def test_broken_json_has_meaningful_error():
    with pytest.raises(JsonParseError, match="parse edilemedi"):
        parse_ai_json("{broken")
