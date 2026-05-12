from __future__ import annotations

from datetime import datetime, timezone
import json
import re
from pathlib import Path
from typing import Any

from slugify import slugify


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def timestamp_for_filename() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M")


def make_slug(text: str) -> str:
    return slugify(text, lowercase=True, max_length=80) or "konu"


def ensure_dirs(base_dir: Path, outputs_dir: str = "outputs") -> None:
    for item in ["data", "logs", f"{outputs_dir}/guides", f"{outputs_dir}/scripts", f"{outputs_dir}/metadata", f"{outputs_dir}/blogger"]:
        (base_dir / item).mkdir(parents=True, exist_ok=True)


class JsonParseError(ValueError):
    pass


def parse_ai_json(text: str) -> Any:
    cleaned = text.strip()
    block = re.search(r"```(?:json)?\s*(.*?)```", cleaned, re.DOTALL | re.IGNORECASE)
    if block:
        cleaned = block.group(1).strip()
    if not cleaned.startswith(("[", "{")):
        match = re.search(r"(\[.*\]|\{.*\})", cleaned, re.DOTALL)
        if match:
            cleaned = match.group(1)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise JsonParseError(f"AI JSON yanıtı parse edilemedi: {exc.msg}") from exc


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
