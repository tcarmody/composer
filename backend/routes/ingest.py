"""
Public ingest API — consumed by DataPoints to promote articles into Composer.

Guarded by COMPOSER_INGEST_KEY (optional in dev).
"""

import asyncio

from fastapi import APIRouter, Depends

from ..auth import verify_ingest_key
from ..config import get_items_repo
from ..repositories import ItemRepository
from ..schemas import (
    IngestBatchResponse,
    IngestItemRequest,
    IngestItemResponse,
)
from ..services.indexer import index_item

router = APIRouter(
    prefix="/v1/ingest",
    tags=["ingest"],
    dependencies=[Depends(verify_ingest_key)],
)


def _item_url(item_id: str) -> str:
    return f"composer://item/{item_id}"


@router.post("/items", response_model=IngestItemResponse)
async def ingest_item(
    payload: IngestItemRequest,
    items: ItemRepository = Depends(get_items_repo),
) -> IngestItemResponse:
    item, created = items.create(
        source=payload.source,
        source_ref=payload.source_ref,
        url=payload.url,
        title=payload.title,
        author=payload.author,
        published_at=payload.published_at,
        content=payload.content,
        summary=payload.summary,
        key_points=payload.key_points,
        keywords=payload.keywords,
        related_links=[rl.model_dump() for rl in payload.related_links],
        metadata=payload.metadata,
    )
    if created:
        asyncio.create_task(index_item(item))
    return IngestItemResponse(
        id=item.id,
        url=_item_url(item.id),
        already_existed=not created,
    )


@router.post("/items/batch", response_model=IngestBatchResponse)
async def ingest_items_batch(
    payloads: list[IngestItemRequest],
    items: ItemRepository = Depends(get_items_repo),
) -> IngestBatchResponse:
    results: list[IngestItemResponse] = []
    created = 0
    skipped = 0
    for payload in payloads:
        item, was_created = items.create(
            source=payload.source,
            source_ref=payload.source_ref,
            url=payload.url,
            title=payload.title,
            author=payload.author,
            published_at=payload.published_at,
            content=payload.content,
            summary=payload.summary,
            key_points=payload.key_points,
            keywords=payload.keywords,
            related_links=[rl.model_dump() for rl in payload.related_links],
            metadata=payload.metadata,
        )
        results.append(
            IngestItemResponse(
                id=item.id,
                url=_item_url(item.id),
                already_existed=not was_created,
            )
        )
        if was_created:
            created += 1
            asyncio.create_task(index_item(item))
        else:
            skipped += 1
    return IngestBatchResponse(items=results, created=created, skipped=skipped)
