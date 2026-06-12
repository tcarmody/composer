"""
Sync relay — pushes local writes to a cloud Composer instance, and pulls
cloud-ingested items back down.

Topology: the LOCAL instance is the writer for notes/drafts/collections;
the cloud instance is a serving replica for the web app. Every repository
mutation records an entry in `sync_outbox` (same transaction as the
write). The worker started from server.py drains the outbox, builds
whole-entity snapshots — including chunks with their embeddings, so the
replica never re-embeds — and POSTs them to
`{SYNC_TARGET_URL}/v1/sync/apply`. Apply is an ID-preserving upsert
(last-writer-wins, local wins), so replays are harmless.

ITEMS are the one entity that also flows cloud→local: promoting from the
cloud DataPoints web UI ingests into the cloud instance, so the worker
periodically GETs `{SYNC_TARGET_URL}/v1/sync/items` for items promoted
after its cursor (kept in schema_meta) and applies them locally. Items
are immutable snapshots keyed by (source, source_ref) with UUID ids, so
the two directions can't conflict.

Enabled only when SYNC_TARGET_URL is set; the cloud instance leaves it
unset and never enqueues (Database.track_sync=False).
"""

import asyncio
import base64
import logging
import sqlite3
import time
import uuid
from typing import Any

import httpx

from ..config import config, state
from ..database import Database

logger = logging.getLogger(__name__)

BATCH_LIMIT = 200
PULL_CURSOR_KEY = "sync_items_cursor"

ENTITY_TABLES = {
    "item": "items",
    "note": "notes",
    "draft": "drafts",
    "collection": "collections",
}


# ─── snapshots (local side) ──────────────────────────────────────────


def _chunks_for(conn: sqlite3.Connection, source_type: str, source_id: str) -> list[dict]:
    rows = conn.execute(
        "SELECT chunk_index, content, embedding, model FROM chunks "
        "WHERE source_type = ? AND source_id = ? ORDER BY chunk_index",
        (source_type, source_id),
    ).fetchall()
    return [
        {
            "chunk_index": r["chunk_index"],
            "content": r["content"],
            "embedding_b64": (
                base64.b64encode(r["embedding"]).decode("ascii")
                if r["embedding"] is not None
                else None
            ),
            "model": r["model"],
        }
        for r in rows
    ]


def build_snapshot(db: Database, entity_type: str, entity_id: str) -> dict | None:
    """Full current state of an entity, or None if it no longer exists."""
    table = ENTITY_TABLES[entity_type]
    with db.conn() as conn:
        row = conn.execute(
            f"SELECT * FROM {table} WHERE id = ?", (entity_id,)
        ).fetchone()
        if row is None:
            return None
        data: dict[str, Any] = dict(row)

        if entity_type in ("item", "note", "draft"):
            data["chunks"] = _chunks_for(conn, entity_type, entity_id)

        if entity_type == "note":
            data["item_attachments"] = [
                dict(r)
                for r in conn.execute(
                    "SELECT item_id, anchor FROM item_notes WHERE note_id = ?",
                    (entity_id,),
                ).fetchall()
            ]
        elif entity_type == "draft":
            data["sources"] = [
                dict(r)
                for r in conn.execute(
                    "SELECT item_id, excerpt, added_at FROM draft_sources "
                    "WHERE draft_id = ? ORDER BY added_at",
                    (entity_id,),
                ).fetchall()
            ]
        elif entity_type == "collection":
            data["members"] = [
                dict(r)
                for r in conn.execute(
                    "SELECT member_type, member_id, position FROM collection_members "
                    "WHERE collection_id = ? ORDER BY position",
                    (entity_id,),
                ).fetchall()
            ]
        return data


# ─── outbox ──────────────────────────────────────────────────────────


def pending_count(db: Database) -> int:
    with db.conn() as conn:
        return conn.execute("SELECT COUNT(*) AS n FROM sync_outbox").fetchone()["n"]


def read_pending(db: Database) -> tuple[list[tuple[str, str, str]], int]:
    """
    Read up to BATCH_LIMIT outbox rows, coalesced per entity (the snapshot
    reflects current state, so one entry per entity suffices; the last op
    seen wins). Returns ([(entity_type, entity_id, op)], max_seq).
    """
    with db.conn() as conn:
        rows = conn.execute(
            "SELECT seq, entity_type, entity_id, op FROM sync_outbox "
            "ORDER BY seq LIMIT ?",
            (BATCH_LIMIT,),
        ).fetchall()
    if not rows:
        return [], 0
    order: list[tuple[str, str]] = []
    final_op: dict[tuple[str, str], str] = {}
    for r in rows:
        key = (r["entity_type"], r["entity_id"])
        if key not in final_op:
            order.append(key)
        final_op[key] = r["op"]
    entries = [(t, i, final_op[(t, i)]) for (t, i) in order]
    return entries, rows[-1]["seq"]


def ack_through(db: Database, max_seq: int) -> None:
    with db.conn() as conn:
        conn.execute("DELETE FROM sync_outbox WHERE seq <= ?", (max_seq,))


def enqueue_full_resync(db: Database) -> dict[str, int]:
    """Queue every entity for push — drift repair / initial cloud seeding."""
    counts: dict[str, int] = {}
    with db.conn() as conn:
        for entity_type, table in ENTITY_TABLES.items():
            cur = conn.execute(
                f"INSERT INTO sync_outbox (entity_type, entity_id, op) "
                f"SELECT ?, id, 'upsert' FROM {table}",
                (entity_type,),
            )
            counts[entity_type] = cur.rowcount
    return counts


# ─── apply (cloud side) ──────────────────────────────────────────────


def _replace_chunks(
    conn: sqlite3.Connection, source_type: str, source_id: str, chunks: list[dict]
) -> None:
    conn.execute(
        "DELETE FROM chunks WHERE source_type = ? AND source_id = ?",
        (source_type, source_id),
    )
    for c in chunks:
        embedding = (
            base64.b64decode(c["embedding_b64"])
            if c.get("embedding_b64")
            else None
        )
        conn.execute(
            "INSERT INTO chunks "
            "(id, source_type, source_id, chunk_index, content, embedding, model) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                f"cmp-chunk-{uuid.uuid4().hex[:12]}",
                source_type,
                source_id,
                c["chunk_index"],
                c["content"],
                embedding,
                c.get("model"),
            ),
        )


def _upsert_row(
    conn: sqlite3.Connection, table: str, entity_id: str, data: dict, columns: list[str]
) -> None:
    """INSERT … ON CONFLICT(id) DO UPDATE — never OR REPLACE, which would
    delete+reinsert and cascade-wipe rows referencing the id."""
    values = [data.get(col) for col in columns]
    placeholders = ", ".join("?" for _ in columns)
    updates = ", ".join(f"{c} = excluded.{c}" for c in columns if c != "id")
    conn.execute(
        f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({placeholders}) "
        f"ON CONFLICT(id) DO UPDATE SET {updates}",
        values,
    )


ENTITY_COLUMNS = {
    "item": [
        "id", "source", "source_ref", "url", "title", "author",
        "published_at", "promoted_at", "content", "summary",
        "key_points", "keywords", "related_links", "metadata", "archived_at",
    ],
    "note": ["id", "title", "body", "created_at", "updated_at"],
    "draft": ["id", "title", "body", "status", "created_at", "updated_at"],
    "collection": ["id", "name", "description", "created_at"],
}


def apply_entry(db: Database, entity_type: str, entity_id: str, op: str, data: dict | None) -> str:
    """Apply one sync entry. Returns 'upserted' | 'deleted' | 'skipped'."""
    table = ENTITY_TABLES[entity_type]
    with db.conn() as conn:
        if op == "delete":
            conn.execute(f"DELETE FROM {table} WHERE id = ?", (entity_id,))
            if entity_type in ("item", "note", "draft"):
                conn.execute(
                    "DELETE FROM chunks WHERE source_type = ? AND source_id = ?",
                    (entity_type, entity_id),
                )
            if entity_type != "collection":
                # collection_members has no FK; clear dangling references
                conn.execute(
                    "DELETE FROM collection_members "
                    "WHERE member_type = ? AND member_id = ?",
                    (entity_type, entity_id),
                )
            return "deleted"

        if data is None:
            return "skipped"

        _upsert_row(conn, table, entity_id, data, ENTITY_COLUMNS[entity_type])

        if entity_type in ("item", "note", "draft"):
            _replace_chunks(conn, entity_type, entity_id, data.get("chunks") or [])

        if entity_type == "note":
            conn.execute("DELETE FROM item_notes WHERE note_id = ?", (entity_id,))
            for att in data.get("item_attachments") or []:
                try:
                    conn.execute(
                        "INSERT OR REPLACE INTO item_notes (item_id, note_id, anchor) "
                        "VALUES (?, ?, ?)",
                        (att["item_id"], entity_id, att.get("anchor")),
                    )
                except sqlite3.IntegrityError:
                    # referenced item hasn't synced yet; the attachment will
                    # arrive with a later snapshot or a full resync
                    logger.warning(
                        "sync apply: skipping attachment to missing item %s",
                        att["item_id"],
                    )
        elif entity_type == "draft":
            conn.execute("DELETE FROM draft_sources WHERE draft_id = ?", (entity_id,))
            for src in data.get("sources") or []:
                try:
                    conn.execute(
                        "INSERT INTO draft_sources (draft_id, item_id, excerpt, added_at) "
                        "VALUES (?, ?, ?, ?)",
                        (entity_id, src["item_id"], src.get("excerpt"), src.get("added_at")),
                    )
                except sqlite3.IntegrityError:
                    logger.warning(
                        "sync apply: skipping draft source for missing item %s",
                        src["item_id"],
                    )
        elif entity_type == "collection":
            conn.execute(
                "DELETE FROM collection_members WHERE collection_id = ?", (entity_id,)
            )
            for m in data.get("members") or []:
                conn.execute(
                    "INSERT INTO collection_members "
                    "(collection_id, member_type, member_id, position) "
                    "VALUES (?, ?, ?, ?)",
                    (entity_id, m["member_type"], m["member_id"], m["position"]),
                )
        return "upserted"


# ─── item pull-down (cloud→local) ────────────────────────────────────


def list_items_since(db: Database, since: str, limit: int = BATCH_LIMIT) -> list[dict]:
    """Item snapshots promoted after `since`, oldest first (cloud side)."""
    with db.conn() as conn:
        rows = conn.execute(
            "SELECT id FROM items WHERE promoted_at > ? "
            "ORDER BY promoted_at ASC LIMIT ?",
            (since, limit),
        ).fetchall()
    snapshots = []
    for r in rows:
        snap = build_snapshot(db, "item", r["id"])
        if snap is not None:
            snapshots.append(snap)
    return snapshots


def _get_pull_cursor(db: Database) -> str | None:
    with db.conn() as conn:
        row = conn.execute(
            "SELECT value FROM schema_meta WHERE key = ?", (PULL_CURSOR_KEY,)
        ).fetchone()
        return row["value"] if row else None


def _set_pull_cursor(db: Database, cursor: str) -> None:
    with db.conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO schema_meta (key, value) VALUES (?, ?)",
            (PULL_CURSOR_KEY, cursor),
        )


def init_pull_cursor(db: Database) -> str:
    """First run after seeding from the cloud DB: start the cursor at the
    newest local item so the whole corpus isn't re-pulled."""
    cursor = _get_pull_cursor(db)
    if cursor is not None:
        return cursor
    with db.conn() as conn:
        row = conn.execute("SELECT MAX(promoted_at) AS mx FROM items").fetchone()
    cursor = row["mx"] or ""
    _set_pull_cursor(db, cursor)
    return cursor


async def pull_once(db: Database) -> int:
    """Pull one batch of cloud-ingested items down. Returns items applied.
    Raises on transport/HTTP failure so the worker can back off."""
    cursor = init_pull_cursor(db)
    headers = {}
    if config.SYNC_API_KEY:
        headers["X-Ingest-Key"] = config.SYNC_API_KEY
    url = config.SYNC_TARGET_URL.rstrip("/") + "/v1/sync/items"
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.get(
            url, params={"since": cursor, "limit": BATCH_LIMIT}, headers=headers
        )
    resp.raise_for_status()
    items = resp.json().get("items", [])
    if not items:
        return 0

    applied = 0
    max_promoted = cursor
    for snap in items:
        max_promoted = max(max_promoted, snap.get("promoted_at") or "")
        # Guard against divergence: same (source, source_ref) already
        # present locally under a different id (e.g. promoted to both
        # instances independently before sync existed). Local wins.
        if snap.get("source_ref"):
            with db.conn() as conn:
                existing = conn.execute(
                    "SELECT id FROM items WHERE source = ? AND source_ref = ?",
                    (snap["source"], snap["source_ref"]),
                ).fetchone()
            if existing and existing["id"] != snap["id"]:
                logger.warning(
                    "pull: skipping cloud item %s — (%s, %s) exists locally as %s",
                    snap["id"], snap["source"], snap["source_ref"], existing["id"],
                )
                continue
        apply_entry(db, "item", snap["id"], "upsert", snap)
        applied += 1
    _set_pull_cursor(db, max_promoted)
    if applied:
        logger.info("Pulled %d item(s) from cloud", applied)
    return applied


# ─── worker (local side) ─────────────────────────────────────────────


async def push_once(db: Database) -> int:
    """Push one outbox batch. Returns entries sent (0 = outbox empty).
    Raises on transport/HTTP failure so the worker can back off."""
    entries, max_seq = read_pending(db)
    if not entries:
        return 0

    payload = []
    for entity_type, entity_id, op in entries:
        data = None
        if op == "upsert":
            data = build_snapshot(db, entity_type, entity_id)
            if data is None:
                # Entity vanished after the upsert was queued (e.g. deleted,
                # with the post-delete deindex enqueueing another upsert that
                # coalesced over the tombstone). IDs are UUIDs and never
                # reused, so a delete is always the right translation.
                op = "delete"
        payload.append(
            {"entity_type": entity_type, "entity_id": entity_id, "op": op, "data": data}
        )

    if payload:
        headers = {}
        if config.SYNC_API_KEY:
            headers["X-Ingest-Key"] = config.SYNC_API_KEY
        url = config.SYNC_TARGET_URL.rstrip("/") + "/v1/sync/apply"
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(url, json={"entries": payload}, headers=headers)
        resp.raise_for_status()

    ack_through(db, max_seq)
    return len(entries)


async def sync_worker() -> None:
    interval = max(config.SYNC_INTERVAL, 1.0)
    pull_interval = max(config.SYNC_PULL_INTERVAL, 1.0)
    backoff = interval
    last_pull = 0.0
    logger.info("Sync worker started → %s (every %.0fs)", config.SYNC_TARGET_URL, interval)
    while True:
        db = state.db
        if db is None:
            await asyncio.sleep(interval)
            continue
        try:
            sent = await push_once(db)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning("Sync push failed (%s); retrying in %.0fs", e, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 300.0)
            continue
        backoff = interval
        if sent:
            logger.info("Synced %d entr%s to cloud", sent, "y" if sent == 1 else "ies")

        if time.monotonic() - last_pull >= pull_interval:
            try:
                pulled = await pull_once(db)
                last_pull = time.monotonic()
                # keep pulling promptly while the cloud has a backlog
                if pulled >= BATCH_LIMIT:
                    last_pull = 0.0
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.warning("Item pull failed (%s); will retry", e)
                last_pull = time.monotonic()

        # drain immediately while busy, otherwise idle at the poll interval
        await asyncio.sleep(0 if sent >= BATCH_LIMIT else interval)
