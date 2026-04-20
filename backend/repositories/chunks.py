"""
Chunks repository.

A chunk is a retrievable fragment of an item, note, or draft. Each
chunk optionally carries a dense embedding (stored as a packed
float32 BLOB) and participates in the chunks_fts FTS5 shadow table.

Chunks for a given (source_type, source_id) are rewritten as a batch:
on every save we delete the existing chunks and insert the new ones,
so chunk_index values stay dense.
"""

import sqlite3
import struct
import uuid
from dataclasses import dataclass
from typing import Literal

from ..database import Database

SourceType = Literal["item", "note", "draft"]


@dataclass
class Chunk:
    id: str
    source_type: SourceType
    source_id: str
    chunk_index: int
    content: str
    embedding: list[float] | None
    model: str | None
    updated_at: str


def pack_embedding(vec: list[float]) -> bytes:
    return struct.pack(f"<{len(vec)}f", *vec)


def unpack_embedding(blob: bytes | None) -> list[float] | None:
    if not blob:
        return None
    n = len(blob) // 4
    return list(struct.unpack(f"<{n}f", blob))


def _row_to_chunk(row: sqlite3.Row) -> Chunk:
    return Chunk(
        id=row["id"],
        source_type=row["source_type"],
        source_id=row["source_id"],
        chunk_index=row["chunk_index"],
        content=row["content"],
        embedding=unpack_embedding(row["embedding"]),
        model=row["model"],
        updated_at=row["updated_at"],
    )


class ChunksRepository:
    def __init__(self, db: Database):
        self.db = db

    def replace_for_source(
        self,
        *,
        source_type: SourceType,
        source_id: str,
        chunks: list[tuple[str, list[float] | None, str | None]],
    ) -> int:
        """
        Delete existing chunks for (source_type, source_id) and insert
        the new ones. Each chunk is a (content, embedding, model)
        tuple. Returns the number of chunks written.
        """
        with self.db.conn() as conn:
            conn.execute(
                "DELETE FROM chunks WHERE source_type = ? AND source_id = ?",
                (source_type, source_id),
            )
            for i, (content, embedding, model) in enumerate(chunks):
                chunk_id = f"cmp-chunk-{uuid.uuid4().hex[:12]}"
                conn.execute(
                    """
                    INSERT INTO chunks
                      (id, source_type, source_id, chunk_index, content, embedding, model)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        chunk_id,
                        source_type,
                        source_id,
                        i,
                        content,
                        pack_embedding(embedding) if embedding is not None else None,
                        model,
                    ),
                )
            return len(chunks)

    def delete_for_source(
        self, *, source_type: SourceType, source_id: str
    ) -> int:
        with self.db.conn() as conn:
            cur = conn.execute(
                "DELETE FROM chunks WHERE source_type = ? AND source_id = ?",
                (source_type, source_id),
            )
            return cur.rowcount

    def list_for_source(
        self, *, source_type: SourceType, source_id: str
    ) -> list[Chunk]:
        with self.db.conn() as conn:
            rows = conn.execute(
                """
                SELECT * FROM chunks
                WHERE source_type = ? AND source_id = ?
                ORDER BY chunk_index
                """,
                (source_type, source_id),
            ).fetchall()
            return [_row_to_chunk(r) for r in rows]

    def count(self) -> int:
        with self.db.conn() as conn:
            row = conn.execute("SELECT COUNT(*) AS n FROM chunks").fetchone()
            return row["n"]

    def count_by_source_type(self) -> dict[str, int]:
        with self.db.conn() as conn:
            rows = conn.execute(
                "SELECT source_type, COUNT(*) AS n FROM chunks GROUP BY source_type"
            ).fetchall()
            return {r["source_type"]: r["n"] for r in rows}
