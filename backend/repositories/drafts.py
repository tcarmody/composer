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


@dataclass
class DraftSource:
    id: int
    draft_id: str
    item_id: str
    excerpt: str | None
    added_at: str
    item_title: str | None
    item_author: str | None
    item_url: str | None


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

    def append_body(
        self,
        draft_id: str,
        *,
        text: str,
        item_id: str | None = None,
        excerpt: str | None = None,
    ) -> Draft | None:
        """Append text to a draft's body, separated by a blank line, and
        optionally record the source item that contributed the excerpt."""
        with self.db.conn() as conn:
            row = conn.execute(
                "SELECT body FROM drafts WHERE id = ?", (draft_id,)
            ).fetchone()
            if row is None:
                return None
            existing = row["body"] or ""
            joiner = "" if existing == "" else ("\n\n" if not existing.endswith("\n\n") else "")
            new_body = existing + joiner + text
            conn.execute(
                "UPDATE drafts SET body = ?, updated_at = datetime('now') WHERE id = ?",
                (new_body, draft_id),
            )
            if item_id is not None:
                conn.execute(
                    "INSERT INTO draft_sources (draft_id, item_id, excerpt) VALUES (?, ?, ?)",
                    (draft_id, item_id, excerpt),
                )
            updated = conn.execute(
                "SELECT * FROM drafts WHERE id = ?", (draft_id,)
            ).fetchone()
            return _row_to_draft(updated) if updated else None

    def list_sources(self, draft_id: str) -> list[DraftSource]:
        with self.db.conn() as conn:
            rows = conn.execute(
                """
                SELECT ds.id, ds.draft_id, ds.item_id, ds.excerpt, ds.added_at,
                       i.title AS item_title, i.author AS item_author, i.url AS item_url
                  FROM draft_sources ds
                  LEFT JOIN items i ON i.id = ds.item_id
                 WHERE ds.draft_id = ?
                 ORDER BY ds.added_at ASC
                """,
                (draft_id,),
            ).fetchall()
            return [
                DraftSource(
                    id=r["id"],
                    draft_id=r["draft_id"],
                    item_id=r["item_id"],
                    excerpt=r["excerpt"],
                    added_at=r["added_at"],
                    item_title=r["item_title"],
                    item_author=r["item_author"],
                    item_url=r["item_url"],
                )
                for r in rows
            ]

    def remove_source(self, draft_id: str, source_id: int) -> bool:
        with self.db.conn() as conn:
            cur = conn.execute(
                "DELETE FROM draft_sources WHERE draft_id = ? AND id = ?",
                (draft_id, source_id),
            )
            return cur.rowcount > 0
