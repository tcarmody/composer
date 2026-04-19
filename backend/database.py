"""
Database - SQLite operations for Composer.

Uses raw SQLite (no ORM). Schema is created on Database init; future
migrations are tracked in the `schema_meta` table.
"""

import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


SCHEMA_VERSION = 2


class Database:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    @contextmanager
    def _conn(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    @contextmanager
    def conn(self) -> Iterator[sqlite3.Connection]:
        """Public connection accessor for repositories."""
        with self._conn() as conn:
            yield conn

    def _init_schema(self):
        with self._conn() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS schema_meta (
                    key   TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS items (
                    id             TEXT PRIMARY KEY,
                    source         TEXT NOT NULL,
                    source_ref     TEXT,
                    url            TEXT,
                    title          TEXT NOT NULL,
                    author         TEXT,
                    published_at   TEXT,
                    promoted_at    TEXT NOT NULL DEFAULT (datetime('now')),
                    content        TEXT,
                    summary        TEXT,
                    key_points     TEXT,
                    keywords       TEXT,
                    related_links  TEXT,
                    metadata       TEXT,
                    archived_at    TEXT
                );

                CREATE UNIQUE INDEX IF NOT EXISTS idx_items_source_ref
                    ON items(source, source_ref)
                    WHERE source_ref IS NOT NULL;

                CREATE INDEX IF NOT EXISTS idx_items_promoted_at
                    ON items(promoted_at DESC);

                CREATE INDEX IF NOT EXISTS idx_items_archived
                    ON items(archived_at)
                    WHERE archived_at IS NULL;

                CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
                    title, author, summary, content, keywords,
                    content='items', content_rowid='rowid'
                );

                CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
                    INSERT INTO items_fts(rowid, title, author, summary, content, keywords)
                    VALUES (new.rowid, new.title, new.author, new.summary, new.content, new.keywords);
                END;

                CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, title, author, summary, content, keywords)
                    VALUES ('delete', old.rowid, old.title, old.author, old.summary, old.content, old.keywords);
                END;

                CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, title, author, summary, content, keywords)
                    VALUES ('delete', old.rowid, old.title, old.author, old.summary, old.content, old.keywords);
                    INSERT INTO items_fts(rowid, title, author, summary, content, keywords)
                    VALUES (new.rowid, new.title, new.author, new.summary, new.content, new.keywords);
                END;
            """)
            conn.execute(
                "INSERT OR REPLACE INTO schema_meta(key, value) VALUES (?, ?)",
                ("version", str(SCHEMA_VERSION)),
            )

    def version(self) -> int:
        with self._conn() as conn:
            row = conn.execute(
                "SELECT value FROM schema_meta WHERE key = 'version'"
            ).fetchone()
            return int(row["value"]) if row else 0
