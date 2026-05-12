from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
import sqlite3
from typing import Any

from .utils import utc_now_iso


class Database:
    def __init__(self, db_path: Path | str):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.init_schema()

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def init_schema(self) -> None:
        with self.connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS runs (
                    id INTEGER PRIMARY KEY,
                    started_at TEXT,
                    finished_at TEXT,
                    status TEXT,
                    selected_topic_id INTEGER,
                    error_message TEXT
                );
                CREATE TABLE IF NOT EXISTS trend_candidates (
                    id INTEGER PRIMARY KEY,
                    run_id INTEGER,
                    raw_title TEXT,
                    normalized_title TEXT,
                    source TEXT,
                    source_url TEXT,
                    collected_at TEXT,
                    category TEXT,
                    problem_intent_score REAL,
                    shorts_potential REAL,
                    link_click_potential REAL,
                    evergreen_score REAL,
                    policy_risk REAL,
                    final_score REAL,
                    ai_reason TEXT,
                    selected INTEGER DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS produced_topics (
                    id INTEGER PRIMARY KEY,
                    canonical_slug TEXT UNIQUE,
                    canonical_problem TEXT,
                    normalized_problem TEXT,
                    topic_fingerprint TEXT,
                    source_trend TEXT,
                    final_score REAL,
                    guide_md_path TEXT,
                    guide_html_path TEXT,
                    short_script_path TEXT,
                    metadata_path TEXT,
                    blogger_post_id TEXT,
                    blogger_url TEXT,
                    publish_status TEXT,
                    created_at TEXT
                );
                CREATE TABLE IF NOT EXISTS blocked_topics (
                    id INTEGER PRIMARY KEY,
                    normalized_problem TEXT,
                    reason TEXT,
                    created_at TEXT
                );
                CREATE TABLE IF NOT EXISTS errors (
                    id INTEGER PRIMARY KEY,
                    run_id INTEGER,
                    step TEXT,
                    error_message TEXT,
                    created_at TEXT
                );
                """
            )

    def start_run(self) -> int:
        with self.connect() as conn:
            cur = conn.execute("INSERT INTO runs(started_at, status) VALUES (?, ?)", (utc_now_iso(), "running"))
            return int(cur.lastrowid)

    def finish_run(self, run_id: int, status: str, selected_topic_id: int | None = None, error_message: str | None = None) -> None:
        with self.connect() as conn:
            conn.execute(
                "UPDATE runs SET finished_at=?, status=?, selected_topic_id=?, error_message=? WHERE id=?",
                (utc_now_iso(), status, selected_topic_id, error_message, run_id),
            )

    def log_error(self, run_id: int | None, step: str, error_message: str) -> None:
        with self.connect() as conn:
            conn.execute(
                "INSERT INTO errors(run_id, step, error_message, created_at) VALUES (?, ?, ?, ?)",
                (run_id, step, error_message, utc_now_iso()),
            )

    def insert_candidate(self, run_id: int, item: dict[str, Any]) -> int:
        with self.connect() as conn:
            cur = conn.execute(
                """
                INSERT INTO trend_candidates(run_id, raw_title, normalized_title, source, source_url, collected_at, category,
                problem_intent_score, shorts_potential, link_click_potential, evergreen_score, policy_risk, final_score, ai_reason)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    run_id,
                    item.get("trend") or item.get("raw_title"),
                    item.get("normalized_title") or item.get("canonical_problem") or item.get("trend"),
                    item.get("source"),
                    item.get("source_url"),
                    item.get("collected_at") or utc_now_iso(),
                    item.get("category"),
                    item.get("problem_intent_score"),
                    item.get("shorts_potential"),
                    item.get("link_click_potential"),
                    item.get("evergreen_score"),
                    item.get("policy_risk"),
                    item.get("final_score"),
                    item.get("reason"),
                ),
            )
            return int(cur.lastrowid)

    def mark_candidate_selected(self, candidate_id: int) -> None:
        with self.connect() as conn:
            conn.execute("UPDATE trend_candidates SET selected=1 WHERE id=?", (candidate_id,))

    def add_blocked_topic(self, normalized_problem: str, reason: str) -> None:
        with self.connect() as conn:
            conn.execute(
                "INSERT INTO blocked_topics(normalized_problem, reason, created_at) VALUES (?, ?, ?)",
                (normalized_problem, reason, utc_now_iso()),
            )

    def produced_recent(self, days: int) -> list[sqlite3.Row]:
        cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).replace(microsecond=0).isoformat()
        with self.connect() as conn:
            return list(conn.execute("SELECT * FROM produced_topics WHERE created_at >= ?", (cutoff,)))

    def slug_exists(self, slug: str) -> bool:
        with self.connect() as conn:
            row = conn.execute("SELECT 1 FROM produced_topics WHERE canonical_slug=?", (slug,)).fetchone()
            return row is not None

    def add_produced_topic(self, payload: dict[str, Any]) -> int:
        columns = ", ".join(payload.keys())
        placeholders = ", ".join(["?"] * len(payload))
        with self.connect() as conn:
            cur = conn.execute(f"INSERT INTO produced_topics({columns}) VALUES ({placeholders})", tuple(payload.values()))
            return int(cur.lastrowid)

    def list_produced(self, limit: int = 50) -> list[sqlite3.Row]:
        with self.connect() as conn:
            return list(conn.execute("SELECT * FROM produced_topics ORDER BY created_at DESC LIMIT ?", (limit,)))
