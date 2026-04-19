"""
Notes repository.

Notes are first-class objects. They can stand alone, be attached to an
item (item_notes), or be added to a collection (collection_members).
"""

import sqlite3
import uuid
from dataclasses import dataclass

from ..database import Database


@dataclass
class Note:
    id: str
    title: str | None
    body: str
    created_at: str
    updated_at: str


def _row_to_note(row: sqlite3.Row) -> Note:
    return Note(
        id=row["id"],
        title=row["title"],
        body=row["body"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


class NotesRepository:
    def __init__(self, db: Database):
        self.db = db

    def create(self, *, title: str | None, body: str) -> Note:
        note_id = f"cmp-note-{uuid.uuid4().hex[:12]}"
        with self.db.conn() as conn:
            conn.execute(
                "INSERT INTO notes (id, title, body) VALUES (?, ?, ?)",
                (note_id, title, body),
            )
            row = conn.execute(
                "SELECT * FROM notes WHERE id = ?", (note_id,)
            ).fetchone()
            return _row_to_note(row)

    def get(self, note_id: str) -> Note | None:
        with self.db.conn() as conn:
            row = conn.execute(
                "SELECT * FROM notes WHERE id = ?", (note_id,)
            ).fetchone()
            return _row_to_note(row) if row else None

    def list(self, *, limit: int = 100, offset: int = 0) -> tuple[list[Note], int]:
        with self.db.conn() as conn:
            total = conn.execute("SELECT COUNT(*) AS n FROM notes").fetchone()["n"]
            rows = conn.execute(
                "SELECT * FROM notes ORDER BY updated_at DESC LIMIT ? OFFSET ?",
                (limit, offset),
            ).fetchall()
            return [_row_to_note(r) for r in rows], total

    def update(
        self,
        note_id: str,
        *,
        title: str | None = None,
        body: str | None = None,
    ) -> Note | None:
        sets: list[str] = []
        params: list[object] = []
        if title is not None:
            sets.append("title = ?")
            params.append(title)
        if body is not None:
            sets.append("body = ?")
            params.append(body)
        if not sets:
            return self.get(note_id)

        sets.append("updated_at = datetime('now')")
        params.append(note_id)

        with self.db.conn() as conn:
            conn.execute(
                f"UPDATE notes SET {', '.join(sets)} WHERE id = ?", params
            )
            row = conn.execute(
                "SELECT * FROM notes WHERE id = ?", (note_id,)
            ).fetchone()
            return _row_to_note(row) if row else None

    def delete(self, note_id: str) -> bool:
        with self.db.conn() as conn:
            cur = conn.execute("DELETE FROM notes WHERE id = ?", (note_id,))
            return cur.rowcount > 0

    # ─── item attachments ───────────────────────────────

    def attach_to_item(
        self, *, item_id: str, note_id: str, anchor: str | None = None
    ) -> None:
        with self.db.conn() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO item_notes(item_id, note_id, anchor) "
                "VALUES (?, ?, ?)",
                (item_id, note_id, anchor),
            )

    def detach_from_item(self, *, item_id: str, note_id: str) -> bool:
        with self.db.conn() as conn:
            cur = conn.execute(
                "DELETE FROM item_notes WHERE item_id = ? AND note_id = ?",
                (item_id, note_id),
            )
            return cur.rowcount > 0

    def list_for_item(self, item_id: str) -> list[Note]:
        with self.db.conn() as conn:
            rows = conn.execute(
                "SELECT notes.* FROM notes "
                "JOIN item_notes ON item_notes.note_id = notes.id "
                "WHERE item_notes.item_id = ? "
                "ORDER BY notes.updated_at DESC",
                (item_id,),
            ).fetchall()
            return [_row_to_note(r) for r in rows]
