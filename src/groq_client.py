from __future__ import annotations

import logging
import time
from typing import Any

from openai import OpenAI

from .utils import JsonParseError, parse_ai_json


class GroqClient:
    def __init__(self, api_key: str | None, base_url: str, model: str, logger: logging.Logger | None = None):
        self.api_key = api_key
        self.model = model
        self.logger = logger or logging.getLogger(__name__)
        self.client = OpenAI(api_key=api_key or "missing", base_url=base_url)

    def is_configured(self) -> bool:
        return bool(self.api_key)

    def chat(self, messages: list[dict[str, str]], temperature: float = 0.3, response_format: dict[str, str] | None = None) -> str:
        if not self.api_key:
            raise RuntimeError("GROQ_API_KEY tanimli degil.")
        last_error: Exception | None = None
        for attempt in range(4):
            try:
                kwargs: dict[str, Any] = {
                    "model": self.model,
                    "messages": messages,
                    "temperature": temperature,
                }
                if response_format:
                    kwargs["response_format"] = response_format
                resp = self.client.chat.completions.create(**kwargs)
                return resp.choices[0].message.content or ""
            except Exception as exc:
                last_error = exc
                status = getattr(exc, "status_code", None)
                headers = getattr(exc, "headers", {}) or {}
                if status == 429 and attempt < 3:
                    retry_after = headers.get("Retry-After") if hasattr(headers, "get") else None
                    delay = float(retry_after) if retry_after else min(2 ** attempt, 8)
                    self.logger.warning("Groq rate limit, %.1f sn bekleniyor.", delay)
                    time.sleep(delay)
                    continue
                if attempt < 3:
                    time.sleep(min(2 ** attempt, 8))
                    continue
                break
        raise RuntimeError(f"Groq istegi basarisiz: {last_error}") from last_error

    def json_chat(self, messages: list[dict[str, str]], temperature: float = 0.2) -> Any:
        text = self.chat(messages, temperature=temperature, response_format={"type": "json_object"})
        try:
            return parse_ai_json(text)
        except JsonParseError:
            self.logger.warning("JSON object mode parse edilemedi, duz parse deneniyor.")
            return parse_ai_json(text)
