"""
Drafts repository.

Drafts are long-form work-in-progress documents. They can stand alone
or be members of a collection. Storage mirrors notes (markdown body +
optional title) with an additional status field for wip/final.
"""

import sqlite3
import uuid
from dataclasses import dataclass
from typing import Literal

from ..database import Database

DraftStatus = Literal["wip", "final"]


@dataclass
class Draft:
    id: str
    title: str | None
    body: str
    status: DraftStatus
    created_at: str
    updated_at: str


def _row_to_draft(row: sqlite3.Row) -> Draft:
    return Draft(
        id=row["id"],
        title=row["title"],
        body=row["body"],
        status=row["status"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


class DraftsRepository:
    def __init__(self, db: Database):
        self.db = db

    def create(
        self,
        *,
        title: str | None = None,
        body: str = "",
        status: DraftStatus = "wip",
    ) -> Draft:
        draft_id = f"cmp-draft-{uuid.uuid4().hex[:12]}"
        with self.db.conn() as conn:
            conn.execute(
                "INSERT INTO drafts (id, title, body, status) VALUES (?, ?, ?, ?)",
                (draft_id, title, body, status),
            )
            row = conn.execute(
                "SELECT * FROM drafts WHERE id = ?", (draft_id,)
            ).fetchone()
            return _row_to_draft(row)

    def get(self, draft_id: str) -> Draft | None:
        with self.db.conn() as conn:
            row = conn.execute(
                "SELECT * FROM drafts WHERE id = ?", (draft_id,)
            ).fetchone()
            return _row_to_draft(row) if row else None

    def list(self, *, limit: int = 100, offset: int = 0) -> tuple[list[Draft], int]:
        with self.db.conn() as conn:
            total = conn.execute(
                "SELECT COUNT(*) AS n FROM drafts"
            ).fetchone()["n"]
            rows = conn.execute(
                "SELECT * FROM drafts ORDER BY updated_at DESC LIMIT ? OFFSET ?",
                (limit, offset),
            ).fetchall()
            return [_row_to_draft(r) for r in rows], total

    def update(
        self,
        draft_id: str,
        *,
        title: str | None = None,
        body: str | None = None,
        status: DraftStatus | None = None,
    ) -> Draft | None:
        sets: list[str] = []
        params: list[object] = []
        if title is not None:
            sets.append("title = ?")
            params.append(title)
        if body is not None:
            sets.append("body = ?")
            params.append(body)
        if status is not None:
            sets.append("status = ?")
            params.append(status)
        if not sets:
            return self.get(draft_id)

        sets.append("updated_at = datetime('now')")
        params.append(draft_id)

        with self.db.conn() as conn:
            conn.execute(
                f"UPDATE drafts SET {', '.join(sets)} WHERE id = ?", params
            )
            row = conn.execute(
                "SELECT * FROM drafts WHERE id = ?", (draft_id,)
            ).fetchone()
            return _row_to_draft(row) if row else None

    def delete(self, draft_id: str) -> bool:
        with self.db.conn() as conn:
            cur = conn.execute("DELETE FROM drafts WHERE id = ?", (draft_id,))
            return cur.rowcount > 0
