"""
Collections repository.

A collection is a flat ordered list of members. Each member is either
an item reference or a note (drafts added in Phase 4). Position is
1-based within a collection and densely re-numbered on reorder.
"""

import sqlite3
import uuid
from dataclasses import dataclass
from typing import Literal

from ..database import Database

MemberType = Literal["item", "note", "draft"]


@dataclass
class Collection:
    id: str
    name: str
    description: str | None
    created_at: str
    member_count: int


@dataclass
class OutlineNode:
    """A member of a collection with its resolved entity data."""

    member_type: MemberType
    member_id: str
    position: int
    # Item fields (present when member_type == 'item')
    item_title: str | None = None
    item_summary: str | None = None
    item_author: str | None = None
    item_published_at: str | None = None
    item_archived: bool = False
    # Note fields (present when member_type == 'note')
    note_title: str | None = None
    note_body: str | None = None
    note_updated_at: str | None = None


def _row_to_collection(row: sqlite3.Row) -> Collection:
    return Collection(
        id=row["id"],
        name=row["name"],
        description=row["description"],
        created_at=row["created_at"],
        member_count=row["member_count"] if "member_count" in row.keys() else 0,
    )


def _row_to_outline_node(row: sqlite3.Row) -> OutlineNode:
    return OutlineNode(
        member_type=row["member_type"],
        member_id=row["member_id"],
        position=row["position"],
        item_title=row["item_title"],
        item_summary=row["item_summary"],
        item_author=row["item_author"],
        item_published_at=row["item_published_at"],
        item_archived=bool(row["item_archived"]),
        note_title=row["note_title"],
        note_body=row["note_body"],
        note_updated_at=row["note_updated_at"],
    )


class CollectionsRepository:
    def __init__(self, db: Database):
        self.db = db

    # ─── collections ────────────────────────────────────

    def create(self, *, name: str, description: str | None = None) -> Collection:
        collection_id = f"cmp-coll-{uuid.uuid4().hex[:12]}"
        with self.db.conn() as conn:
            conn.execute(
                "INSERT INTO collections (id, name, description) VALUES (?, ?, ?)",
                (collection_id, name, description),
            )
        return self.get(collection_id)  # type: ignore[return-value]

    def get(self, collection_id: str) -> Collection | None:
        with self.db.conn() as conn:
            row = conn.execute(
                """
                SELECT c.*,
                       (SELECT COUNT(*) FROM collection_members
                        WHERE collection_id = c.id) AS member_count
                FROM collections c
                WHERE c.id = ?
                """,
                (collection_id,),
            ).fetchone()
            return _row_to_collection(row) if row else None

    def list(self) -> list[Collection]:
        with self.db.conn() as conn:
            rows = conn.execute(
                """
                SELECT c.*,
                       (SELECT COUNT(*) FROM collection_members
                        WHERE collection_id = c.id) AS member_count
                FROM collections c
                ORDER BY c.created_at DESC
                """
            ).fetchall()
            return [_row_to_collection(r) for r in rows]

    def update(
        self,
        collection_id: str,
        *,
        name: str | None = None,
        description: str | None = None,
    ) -> Collection | None:
        sets: list[str] = []
        params: list[object] = []
        if name is not None:
            sets.append("name = ?")
            params.append(name)
        if description is not None:
            sets.append("description = ?")
            params.append(description)
        if not sets:
            return self.get(collection_id)
        params.append(collection_id)
        with self.db.conn() as conn:
            conn.execute(
                f"UPDATE collections SET {', '.join(sets)} WHERE id = ?", params
            )
        return self.get(collection_id)

    def delete(self, collection_id: str) -> bool:
        with self.db.conn() as conn:
            cur = conn.execute(
                "DELETE FROM collections WHERE id = ?", (collection_id,)
            )
            return cur.rowcount > 0

    # ─── members ────────────────────────────────────────

    def add_member(
        self,
        *,
        collection_id: str,
        member_type: MemberType,
        member_id: str,
    ) -> int:
        """
        Append a member at the end. Returns its new position.
        Idempotent: re-adding the same member is a no-op, returning the
        existing position.
        """
        with self.db.conn() as conn:
            existing = conn.execute(
                "SELECT position FROM collection_members "
                "WHERE collection_id = ? AND member_type = ? AND member_id = ?",
                (collection_id, member_type, member_id),
            ).fetchone()
            if existing:
                return existing["position"]

            row = conn.execute(
                "SELECT COALESCE(MAX(position), 0) AS mx FROM collection_members "
                "WHERE collection_id = ?",
                (collection_id,),
            ).fetchone()
            position = row["mx"] + 1
            conn.execute(
                "INSERT INTO collection_members "
                "(collection_id, member_type, member_id, position) "
                "VALUES (?, ?, ?, ?)",
                (collection_id, member_type, member_id, position),
            )
            return position

    def remove_member(
        self, *, collection_id: str, member_type: MemberType, member_id: str
    ) -> bool:
        with self.db.conn() as conn:
            cur = conn.execute(
                "DELETE FROM collection_members "
                "WHERE collection_id = ? AND member_type = ? AND member_id = ?",
                (collection_id, member_type, member_id),
            )
            if cur.rowcount == 0:
                return False
            self._compact_positions(conn, collection_id)
            return True

    def reorder(
        self,
        *,
        collection_id: str,
        ordered_members: list[tuple[MemberType, str]],
    ) -> None:
        """
        Re-set positions for members of a collection. Any members not
        included keep their relative order and are appended after.
        """
        with self.db.conn() as conn:
            existing_rows = conn.execute(
                "SELECT member_type, member_id, position FROM collection_members "
                "WHERE collection_id = ? ORDER BY position",
                (collection_id,),
            ).fetchall()
            existing = [(r["member_type"], r["member_id"]) for r in existing_rows]
            included = set(ordered_members)
            leftovers = [m for m in existing if m not in included]
            final_order = list(ordered_members) + leftovers

            # Two-phase update to avoid temporary unique collisions via offset.
            offset = 10_000
            for i, (mtype, mid) in enumerate(final_order, start=1):
                conn.execute(
                    "UPDATE collection_members SET position = ? "
                    "WHERE collection_id = ? AND member_type = ? AND member_id = ?",
                    (offset + i, collection_id, mtype, mid),
                )
            for i, (mtype, mid) in enumerate(final_order, start=1):
                conn.execute(
                    "UPDATE collection_members SET position = ? "
                    "WHERE collection_id = ? AND member_type = ? AND member_id = ?",
                    (i, collection_id, mtype, mid),
                )

    def list_members(self, collection_id: str) -> list[OutlineNode]:
        with self.db.conn() as conn:
            rows = conn.execute(
                """
                SELECT
                    cm.member_type,
                    cm.member_id,
                    cm.position,
                    items.title         AS item_title,
                    items.summary       AS item_summary,
                    items.author        AS item_author,
                    items.published_at  AS item_published_at,
                    CASE WHEN items.archived_at IS NOT NULL THEN 1 ELSE 0 END
                        AS item_archived,
                    notes.title         AS note_title,
                    notes.body          AS note_body,
                    notes.updated_at    AS note_updated_at
                FROM collection_members cm
                LEFT JOIN items ON items.id = cm.member_id AND cm.member_type = 'item'
                LEFT JOIN notes ON notes.id = cm.member_id AND cm.member_type = 'note'
                WHERE cm.collection_id = ?
                ORDER BY cm.position ASC
                """,
                (collection_id,),
            ).fetchall()
            return [_row_to_outline_node(r) for r in rows]

    def _compact_positions(
        self, conn: sqlite3.Connection, collection_id: str
    ) -> None:
        rows = conn.execute(
            "SELECT member_type, member_id FROM collection_members "
            "WHERE collection_id = ? ORDER BY position",
            (collection_id,),
        ).fetchall()
        for i, r in enumerate(rows, start=1):
            conn.execute(
                "UPDATE collection_members SET position = ? "
                "WHERE collection_id = ? AND member_type = ? AND member_id = ?",
                (i, collection_id, r["member_type"], r["member_id"]),
            )
