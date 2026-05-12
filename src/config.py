from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import os

from dotenv import load_dotenv
import yaml


@dataclass
class AppConfig:
    country: str = "TR"
    language: str = "tr"
    lookback_hours: int = 24
    max_trends_to_collect: int = 50
    max_candidates_to_score: int = 15
    min_final_score: int = 65
    duplicate_similarity_threshold: int = 86
    recent_duplicate_days: int = 60
    outputs_dir: str = "outputs"
    blogger_publish_mode: str = "draft"
    default_labels: list[str] = field(default_factory=lambda: ["Tech Çözüm", "1 Dakikada Çözüm", "Uygulama Hatası"])
    allowed_categories: list[str] = field(default_factory=list)
    blocked_categories: list[str] = field(default_factory=list)
    groq_api_key: str | None = None
    groq_model: str = "llama-3.1-8b-instant"
    groq_base_url: str = "https://api.groq.com/openai/v1"
    blogger_blog_id: str | None = None
    google_client_secret_file: str = "client_secret.json"
    google_token_file: str = "token.json"
    google_refresh_token: str | None = None


def load_config(base_dir: Path | str = ".") -> AppConfig:
    base = Path(base_dir)
    load_dotenv(base / ".env")
    raw: dict = {}
    config_path = base / "config.yaml"
    if config_path.exists():
        raw = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    cfg = AppConfig(**{k: v for k, v in raw.items() if hasattr(AppConfig, k)})
    cfg.groq_api_key = os.getenv("GROQ_API_KEY")
    cfg.groq_model = os.getenv("GROQ_MODEL", cfg.groq_model)
    cfg.groq_base_url = os.getenv("GROQ_BASE_URL", cfg.groq_base_url)
    cfg.blogger_blog_id = os.getenv("BLOGGER_BLOG_ID")
    cfg.google_client_secret_file = os.getenv("GOOGLE_CLIENT_SECRET_FILE", cfg.google_client_secret_file)
    cfg.google_token_file = os.getenv("GOOGLE_TOKEN_FILE", cfg.google_token_file)
    cfg.google_refresh_token = os.getenv("GOOGLE_REFRESH_TOKEN")
    cfg.blogger_publish_mode = os.getenv("BLOGGER_PUBLISH_MODE", cfg.blogger_publish_mode)
    return cfg
