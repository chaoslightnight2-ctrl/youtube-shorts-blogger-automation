from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
import json
from pathlib import Path
from typing import Any

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload


YOUTUBE_UPLOAD_SCOPE = "https://www.googleapis.com/auth/youtube.upload"


@dataclass
class YouTubeUploadResult:
    video_id: str
    youtube_url: str
    privacy_status: str
    publish_at_utc: str | None
    raw_response: dict[str, Any]


class YouTubeUploader:
    def __init__(self, client_secret_file: str, refresh_token: str, base_dir: Path | str | None = None, category_id: str = "28"):
        self.refresh_token = refresh_token
        self.category_id = category_id
        base = Path(base_dir) if base_dir else Path.cwd()
        self.client_secret_file = self._resolve_path(client_secret_file, base)
        self.service = None

    @staticmethod
    def _resolve_path(path_value: str, base_dir: Path) -> Path:
        path = Path(path_value)
        return path if path.is_absolute() else base_dir / path

    def authenticate(self):
        credentials = self._credentials_from_refresh_token()
        credentials.refresh(Request())
        self.service = build("youtube", "v3", credentials=credentials)
        return self.service

    def _credentials_from_refresh_token(self) -> Credentials:
        client_info = self._load_client_info()
        return Credentials(
            token=None,
            refresh_token=self.refresh_token,
            token_uri=client_info.get("token_uri", "https://oauth2.googleapis.com/token"),
            client_id=client_info["client_id"],
            client_secret=client_info["client_secret"],
            scopes=[YOUTUBE_UPLOAD_SCOPE],
        )

    def _load_client_info(self) -> dict[str, str]:
        data = json.loads(self.client_secret_file.read_text(encoding="utf-8"))
        client_info = data.get("installed") or data.get("web") or data
        missing = [key for key in ["client_id", "client_secret"] if not client_info.get(key)]
        if missing:
            raise RuntimeError(f"Google client JSON eksik alan iceriyor: {', '.join(missing)}")
        return client_info

    def upload(
        self,
        video_path: Path | str,
        title: str,
        description: str,
        tags: list[str] | None = None,
        privacy_status: str = "private",
        publish_at: datetime | None = None,
    ) -> YouTubeUploadResult:
        video = Path(video_path)
        if not video.exists():
            raise FileNotFoundError(f"Video dosyasi bulunamadi: {video}")

        body = self.build_request_body(title, description, tags or [], privacy_status, publish_at)
        media = MediaFileUpload(str(video), mimetype="video/mp4", resumable=True, chunksize=5 * 1024 * 1024)
        request = (self.service or self.authenticate()).videos().insert(part="snippet,status", body=body, media_body=media)

        response = None
        while response is None:
            _status, response = request.next_chunk()

        video_id = response["id"]
        return YouTubeUploadResult(
            video_id=video_id,
            youtube_url=f"https://youtu.be/{video_id}",
            privacy_status=body["status"]["privacyStatus"],
            publish_at_utc=body["status"].get("publishAt"),
            raw_response=response,
        )

    def build_request_body(self, title: str, description: str, tags: list[str], privacy_status: str, publish_at: datetime | None) -> dict[str, Any]:
        safe_title = title.strip()
        if "#shorts" not in safe_title.lower():
            safe_title = f"{safe_title} #shorts"

        status: dict[str, Any] = {"privacyStatus": privacy_status, "selfDeclaredMadeForKids": False}
        if publish_at:
            status["privacyStatus"] = "private"
            status["publishAt"] = publish_at.astimezone(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")

        normalized_tags = list(dict.fromkeys([tag.lstrip("#").strip() for tag in tags if tag.strip()]))
        if "shorts" not in [tag.lower() for tag in normalized_tags]:
            normalized_tags.insert(0, "shorts")

        return {
            "snippet": {
                "title": safe_title[:100],
                "description": description[:5000],
                "tags": normalized_tags[:30],
                "categoryId": self.category_id,
            },
            "status": status,
        }


def metadata_to_youtube_fields(metadata: dict[str, Any]) -> tuple[str, str, list[str]]:
    title = str(metadata.get("title") or "YouTube Shorts")
    description = str(metadata.get("description") or "")
    hashtags = metadata.get("hashtags") or []
    tags = [str(item) for item in hashtags if str(item).strip()]
    return title, description, tags
