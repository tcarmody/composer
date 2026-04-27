"""
Internal items API — consumed by the Composer frontend.

Guarded by AUTH_API_KEY (optional in dev).
"""

import asyncio

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import verify_api_key
from ..config import get_items_repo
from ..repositories import ItemRepository
from ..schemas import (
    ItemListResponse,
    ItemPatchRequest,
    ItemResponse,
    ItemSummaryResponse,
)
from ..services.datapoints import DataPointsError, refresh_from_datapoints
from ..services.fetcher import FetchError, fetch_article, html_to_text
from ..services.indexer import deindex, index_item
from ..services.summarizer import SummarizeError, summarize_article

router = APIRouter(
    prefix="/items",
    tags=["items"],
    dependencies=[Depends(verify_api_key)],
)


@router.get("", response_model=ItemListResponse)
async def list_items(
    q: str | None = Query(None, description="FTS5 query across title, author, summary, content, keywords"),
    archived: bool | None = Query(False, description="false=active only (default), true=archived only, null=all"),
    source: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    items: ItemRepository = Depends(get_items_repo),
) -> ItemListResponse:
    rows, total = items.list(
        query=q, archived=archived, source=source, limit=limit, offset=offset
    )
    return ItemListResponse(
        items=[ItemSummaryResponse.from_item(i) for i in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/{item_id}", response_model=ItemResponse)
async def get_item(
    item_id: str,
    items: ItemRepository = Depends(get_items_repo),
) -> ItemResponse:
    item = items.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return ItemResponse.from_item(item)


@router.patch("/{item_id}", response_model=ItemResponse)
async def patch_item(
    item_id: str,
    patch: ItemPatchRequest,
    items: ItemRepository = Depends(get_items_repo),
) -> ItemResponse:
    if patch.archived is not None:
        updated = items.set_archived(item_id, patch.archived)
        if not updated:
            raise HTTPException(status_code=404, detail="Item not found")
        asyncio.create_task(index_item(updated))
        return ItemResponse.from_item(updated)

    item = items.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return ItemResponse.from_item(item)


@router.delete("/{item_id}", status_code=204)
async def delete_item(
    item_id: str,
    items: ItemRepository = Depends(get_items_repo),
) -> None:
    ok = items.delete(item_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Item not found")
    deindex("item", item_id)


@router.post("/{item_id}/refresh", response_model=ItemResponse)
async def refresh_item(
    item_id: str,
    items: ItemRepository = Depends(get_items_repo),
) -> ItemResponse:
    """
    Ask the upstream source to re-promote this item.

    Only supported for items sourced from DataPoints. DataPoints will call
    back into /v1/ingest/items, which upserts the row in place; we then
    re-read the item and return the refreshed record.
    """
    item = items.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    if item.source != "datapoints":
        raise HTTPException(
            status_code=400,
            detail=f"Refresh not supported for source '{item.source}'",
        )
    if not item.source_ref:
        raise HTTPException(
            status_code=400,
            detail="Item has no source_ref; cannot refresh",
        )

    try:
        await refresh_from_datapoints(item.source_ref)
    except DataPointsError as e:
        raise HTTPException(status_code=502, detail=str(e))

    refreshed = items.get(item_id)
    if not refreshed:
        raise HTTPException(
            status_code=500,
            detail="Item disappeared during refresh",
        )
    return ItemResponse.from_item(refreshed)


@router.post("/{item_id}/fetch-content", response_model=ItemResponse)
async def fetch_item_content(
    item_id: str,
    items: ItemRepository = Depends(get_items_repo),
) -> ItemResponse:
    """
    Fetch the article at this item's URL and replace `content` with the
    extracted readable HTML. Updates word_count / reading_time / extractor_used
    in metadata. Re-runs even when `content` already exists.
    """
    item = items.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    if not item.url:
        raise HTTPException(
            status_code=400,
            detail="Item has no URL; nothing to fetch",
        )

    try:
        article = await fetch_article(item.url)
    except FetchError as e:
        raise HTTPException(status_code=502, detail=str(e))

    metadata_patch = {
        "word_count": article.word_count,
        "reading_time_minutes": article.reading_time_minutes,
        "extractor_used": article.extractor_used,
        "is_paywalled": article.is_paywalled,
        "site_name": article.site_name,
        "content_hash": article.content_hash,
    }
    updated = items.update_content(
        item_id, content=article.content_html, metadata_patch=metadata_patch
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Item not found")
    asyncio.create_task(index_item(updated))
    return ItemResponse.from_item(updated)


@router.post("/{item_id}/summarize", response_model=ItemResponse)
async def summarize_item(
    item_id: str,
    items: ItemRepository = Depends(get_items_repo),
) -> ItemResponse:
    """
    Generate a fresh summary + key points for this item from its `content`.
    Re-runs even when a summary already exists.
    """
    item = items.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    if not item.content or len(item.content.strip()) < 200:
        raise HTTPException(
            status_code=400,
            detail=(
                "Item has insufficient content to summarize. "
                "Try 'Fetch full text' first."
            ),
        )

    plain = html_to_text(item.content)
    try:
        result = await summarize_article(
            content=plain,
            title=item.title,
            url=item.url or "",
        )
    except SummarizeError as e:
        raise HTTPException(status_code=502, detail=str(e))

    updated = items.update_summary(
        item_id, summary=result.summary, key_points=result.key_points
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Item not found")
    asyncio.create_task(index_item(updated))
    return ItemResponse.from_item(updated)
