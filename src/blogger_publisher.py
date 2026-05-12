from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build


SCOPES = ["https://www.googleapis.com/auth/blogger"]


@dataclass
class BloggerPostResult:
    post_id: str | None
    url: str | None
    status: str
    raw_response: dict[str, Any]


class BloggerPublisher:
    def __init__(self, blog_id: str | None, client_secret_file: str, token_file: str, base_dir: Path | str | None = None):
        self.blog_id = blog_id
        base = Path(base_dir) if base_dir else Path.cwd()
        self.client_secret_file = self._resolve_path(client_secret_file, base)
        self.token_file = self._resolve_path(token_file, base)
        self.service = None

    @staticmethod
    def _resolve_path(path_value: str, base_dir: Path) -> Path:
        path = Path(path_value)
        return path if path.is_absolute() else base_dir / path

    def authenticate(self):
        creds = None
        if self.token_file.exists():
            creds = Credentials.from_authorized_user_file(str(self.token_file), SCOPES)
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        if not creds or not creds.valid:
            if not self.client_secret_file.exists():
                raise FileNotFoundError(f"Google client secret bulunamadi: {self.client_secret_file}")
            flow = InstalledAppFlow.from_client_secrets_file(str(self.client_secret_file), SCOPES)
            creds = flow.run_local_server(port=0)
            self.token_file.write_text(creds.to_json(), encoding="utf-8")
        self.service = build("blogger", "v3", credentials=creds)
        return self.service

    def create_post(self, title: str, html_content: str, labels: list[str], is_draft: bool = True) -> BloggerPostResult:
        if not self.blog_id:
            raise RuntimeError("BLOGGER_BLOG_ID tanimli degil.")
        service = self.service or self.authenticate()
        body = {"title": title, "content": html_content, "labels": labels}
        resp = service.posts().insert(blogId=self.blog_id, body=body, isDraft=is_draft).execute()
        return BloggerPostResult(resp.get("id"), resp.get("url"), "draft" if is_draft else "published", resp)

    def update_post(self, post_id: str, title: str | None = None, html_content: str | None = None, labels: list[str] | None = None) -> BloggerPostResult:
        if not self.blog_id:
            raise RuntimeError("BLOGGER_BLOG_ID tanimli degil.")
        service = self.service or self.authenticate()
        current = service.posts().get(blogId=self.blog_id, postId=post_id).execute()
        body = {
            "title": title or current.get("title"),
            "content": html_content or current.get("content"),
            "labels": labels or current.get("labels", []),
        }
        resp = service.posts().update(blogId=self.blog_id, postId=post_id, body=body).execute()
        return BloggerPostResult(resp.get("id"), resp.get("url"), resp.get("status", "updated"), resp)

    def list_recent_posts(self, max_results: int = 20):
        if not self.blog_id:
            raise RuntimeError("BLOGGER_BLOG_ID tanimli degil.")
        service = self.service or self.authenticate()
        return service.posts().list(blogId=self.blog_id, maxResults=max_results).execute()
