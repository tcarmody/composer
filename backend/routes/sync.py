"""
Sync apply endpoint — the cloud replica side of the local→cloud relay.

A local Composer instance (the single writer) pushes whole-entity
snapshots here; we upsert them preserving IDs. Guarded by the same
X-Ingest-Key as /v1/ingest since both are service-to-service surfaces.
"""

import logging

from fastapi import APIRouter, Depends, Query

from ..auth import verify_ingest_key
from ..config import get_db
from ..database import Database
from ..schemas import SyncApplyRequest, SyncApplyResponse
from ..services.sync import apply_entry, list_items_since

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/v1/sync",
    tags=["sync"],
    dependencies=[Depends(verify_ingest_key)],
)


@router.post("/apply", response_model=SyncApplyResponse)
async def sync_apply(
    payload: SyncApplyRequest,
    db: Database = Depends(get_db),
) -> SyncApplyResponse:
    counts = {"upserted": 0, "deleted": 0, "skipped": 0}
    for entry in payload.entries:
        result = apply_entry(
            db, entry.entity_type, entry.entity_id, entry.op, entry.data
        )
        counts[result] += 1
    logger.info(
        "sync apply: %d upserted, %d deleted, %d skipped",
        counts["upserted"], counts["deleted"], counts["skipped"],
    )
    return SyncApplyResponse(**counts)


@router.get("/items")
async def sync_items(
    since: str = Query("", description="promoted_at cursor; items after this"),
    limit: int = Query(200, ge=1, le=500),
    db: Database = Depends(get_db),
) -> dict:
    """Item snapshots promoted after `since` — lets a local instance pull
    down items that were ingested cloud-side (web DataPoints promotions)."""
    return {"items": list_items_since(db, since, limit)}
