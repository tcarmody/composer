"""Admin routes. X-API-Key guarded."""

import os
import sqlite3
import tempfile

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from ..auth import verify_api_key
from ..config import config, get_db
from ..database import Database
from ..services.indexer import reindex_all
from ..services.sync import enqueue_full_resync, pending_count

router = APIRouter(
    prefix="/v1/admin",
    tags=["admin"],
    dependencies=[Depends(verify_api_key)],
)


@router.post("/reindex")
async def reindex() -> dict[str, int]:
    return await reindex_all()


@router.get("/sync/status")
async def sync_status(db: Database = Depends(get_db)) -> dict:
    return {
        "target": config.SYNC_TARGET_URL or None,
        "enabled": bool(config.SYNC_TARGET_URL),
        "pending": pending_count(db) if db.track_sync else 0,
    }


@router.post("/sync/full")
async def sync_full(db: Database = Depends(get_db)) -> dict:
    """Queue every entity for push — drift repair or initial cloud seed."""
    if not db.track_sync:
        return {"queued": {}, "error": "sync not enabled (SYNC_TARGET_URL unset)"}
    return {"queued": enqueue_full_resync(db)}


@router.get("/export/db")
async def export_db(db: Database = Depends(get_db)) -> FileResponse:
    """Stream a consistent snapshot of the SQLite database (for seeding a
    local instance from the cloud copy)."""
    fd, tmp_path = tempfile.mkstemp(suffix=".db", prefix="composer-export-")
    os.close(fd)
    src = sqlite3.connect(db.db_path)
    try:
        dst = sqlite3.connect(tmp_path)
        try:
            src.backup(dst)
        finally:
            dst.close()
    finally:
        src.close()
    return FileResponse(
        tmp_path,
        filename="composer.db",
        media_type="application/octet-stream",
        background=BackgroundTask(os.unlink, tmp_path),
    )
