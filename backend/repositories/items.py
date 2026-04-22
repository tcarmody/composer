"""
Items repository.

Snapshot records keyed on (source, source_ref). Re-ingesting the same
(source, source_ref) refreshes content/summary/etc in place — id,
promoted_at, and archived_at are preserved so links and archive state
survive a refresh.
"""

import json
import sqlite3
import uuid
from dataclasses import dataclass
from typing import Any

from ..database import Database


@dataclass
class Item:
    id: str
    source: str
    source_ref: str | None
    url: str | None
    title: str
    author: str | None
    published_at: str | None
    promoted_at: str
    content: str | None
    summary: str | None
    key_points: list[str]
    keywords: list[str]
    related_links: list[dict[str, Any]]
    metadata: dict[str, Any]
    archived_at: str | None


def _loads(value: str | None, default: Any) -> Any:
    if not value:
        return default
    try:
        return json.loads(value)
    except (json.JSONDecodeError, TypeError):
        return default


def _row_to_item(row: sqlite3.Row) -> Item:
    return Item(
        id=row["id"],
        source=row["source"],
        source_ref=row["source_ref"],
        url=row["url"],
        title=row["title"],
        author=row["author"],
        published_at=row["published_at"],
        promoted_at=row["promoted_at"],
        content=row["content"],
        summary=row["summary"],
        key_points=_loads(row["key_points"], []),
        keywords=_loads(row["keywords"], []),
        related_links=_loads(row["related_links"], []),
        metadata=_loads(row["metadata"], {}),
        archived_at=row["archived_at"],
    )


def _fts_escape(q: str) -> str:
    """Wrap each bare word in quotes so FTS5 treats user input literally."""
    tokens = [t for t in q.replace('"', "").split() if t]
    return " ".join(f'"{t}"' for t in tokens)


class ItemRepository:
    def __init__(self, db: Database):
        self.db = db

    def create(
        self,
        *,
        source: str,
        source_ref: str | None,
        url: str | None,
        title: str,
        author: str | None,
        published_at: str | None,
        content: str | None,
        summary: str | None,
        key_points: list[str] | None,
        keywords: list[str] | None,
        related_links: list[dict[str, Any]] | None,
        metadata: dict[str, Any] | None,
    ) -> tuple[Item, bool]:
        """
        Upsert keyed on (source, source_ref).

        Returns (item, created). If the row already existed, created=False
        and the existing row has been updated in place (id, promoted_at,
        and archived_at preserved).
        """
        with self.db.conn() as conn:
            if source_ref:
                existing = conn.execute(
                    "SELECT * FROM items WHERE source = ? AND source_ref = ?",
                    (source, source_ref),
                ).fetchone()
                if existing:
                    conn.execute(
                        """
                        UPDATE items SET
                            url = ?, title = ?, author = ?,
                            published_at = ?, content = ?, summary = ?,
                            key_points = ?, keywords = ?,
                            related_links = ?, metadata = ?
                        WHERE id = ?
                        """,
                        (
                            url, title, author,
                            published_at, content, summary,
                            json.dumps(key_points or []),
                            json.dumps(keywords or []),
                            json.dumps(related_links or []),
                            json.dumps(metadata or {}),
                            existing["id"],
                        ),
                    )
                    row = conn.execute(
                        "SELECT * FROM items WHERE id = ?", (existing["id"],)
                    ).fetchone()
                    return _row_to_item(row), False

            item_id = f"cmp-item-{uuid.uuid4().hex[:12]}"
            conn.execute(
                """
                INSERT INTO items (
                    id, source, source_ref, url, title, author,
                    published_at, content, summary,
                    key_points, keywords, related_links, metadata
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    item_id, source, source_ref, url, title, author,
                    published_at, content, summary,
                    json.dumps(key_points or []),
                    json.dumps(keywords or []),
                    json.dumps(related_links or []),
                    json.dumps(metadata or {}),
                ),
            )
            row = conn.execute(
                "SELECT * FROM items WHERE id = ?", (item_id,)
            ).fetchone()
            return _row_to_item(row), True

    def get(self, item_id: str) -> Item | None:
        with self.db.conn() as conn:
            row = conn.execute(
                "SELECT * FROM items WHERE id = ?", (item_id,)
            ).fetchone()
            return _row_to_item(row) if row else None

    def list(
        self,
        *,
        query: str | None = None,
        archived: bool | None = False,
        source: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> tuple[list[Item], int]:
        """
        Returns (items, total_count).

        archived:
          - False (default): only non-archived
          - True: only archived
          - None: all
        """
        where: list[str] = []
        params: list[Any] = []

        base = "FROM items"
        if query:
            base = (
                "FROM items JOIN items_fts ON items.rowid = items_fts.rowid "
                "AND items_fts MATCH ?"
            )
            params.append(_fts_escape(query))

        if archived is False:
            where.append("archived_at IS NULL")
        elif archived is True:
            where.append("archived_at IS NOT NULL")

        if source:
            where.append("source = ?")
            params.append(source)

        where_sql = f"WHERE {' AND '.join(where)}" if where else ""

        with self.db.conn() as conn:
            total = conn.execute(
                f"SELECT COUNT(*) AS n {base} {where_sql}", params
            ).fetchone()["n"]

            rows = conn.execute(
                f"SELECT items.* {base} {where_sql} "
                f"ORDER BY promoted_at DESC LIMIT ? OFFSET ?",
                [*params, limit, offset],
            ).fetchall()

            return [_row_to_item(r) for r in rows], total

    def set_archived(self, item_id: str, archived: bool) -> Item | None:
        with self.db.conn() as conn:
            if archived:
                conn.execute(
                    "UPDATE items SET archived_at = datetime('now') "
                    "WHERE id = ? AND archived_at IS NULL",
                    (item_id,),
                )
            else:
                conn.execute(
                    "UPDATE items SET archived_at = NULL WHERE id = ?",
                    (item_id,),
                )
            row = conn.execute(
                "SELECT * FROM items WHERE id = ?", (item_id,)
            ).fetchone()
            return _row_to_item(row) if row else None

    def delete(self, item_id: str) -> bool:
        with self.db.conn() as conn:
            cur = conn.execute("DELETE FROM items WHERE id = ?", (item_id,))
            return cur.rowcount > 0
