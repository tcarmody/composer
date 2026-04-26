"""Drafts routes. X-API-Key guarded."""

import asyncio

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import verify_api_key
from ..config import get_drafts_repo
from ..repositories import DraftsRepository
from ..schemas import (
    DraftAppendRequest,
    DraftAssistRequest,
    DraftAssistResponse,
    DraftCreateRequest,
    DraftListResponse,
    DraftPatchRequest,
    DraftResponse,
    DraftSourceListResponse,
    DraftSourceResponse,
)
from ..services.assist import AssistError, run_assist
from ..services.indexer import deindex, index_draft

router = APIRouter(
    prefix="/drafts",
    tags=["drafts"],
    dependencies=[Depends(verify_api_key)],
)


@router.get("", response_model=DraftListResponse)
async def list_drafts(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> DraftListResponse:
    rows, total = drafts.list(limit=limit, offset=offset)
    return DraftListResponse(
        drafts=[DraftResponse.from_draft(d) for d in rows],
        total=total,
    )


@router.post("", response_model=DraftResponse, status_code=201)
async def create_draft(
    payload: DraftCreateRequest,
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> DraftResponse:
    draft = drafts.create(
        title=payload.title, body=payload.body, status=payload.status
    )
    asyncio.create_task(index_draft(draft))
    return DraftResponse.from_draft(draft)


@router.get("/{draft_id}", response_model=DraftResponse)
async def get_draft(
    draft_id: str,
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> DraftResponse:
    draft = drafts.get(draft_id)
    if not draft:
        raise HTTPException(status_code=404, detail="Draft not found")
    return DraftResponse.from_draft(draft)


@router.patch("/{draft_id}", response_model=DraftResponse)
async def patch_draft(
    draft_id: str,
    payload: DraftPatchRequest,
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> DraftResponse:
    updated = drafts.update(
        draft_id,
        title=payload.title,
        body=payload.body,
        status=payload.status,
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Draft not found")
    asyncio.create_task(index_draft(updated))
    return DraftResponse.from_draft(updated)


@router.delete("/{draft_id}", status_code=204)
async def delete_draft(
    draft_id: str,
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> None:
    if not drafts.delete(draft_id):
        raise HTTPException(status_code=404, detail="Draft not found")
    deindex("draft", draft_id)


@router.post("/{draft_id}/append", response_model=DraftResponse)
async def append_draft(
    draft_id: str,
    payload: DraftAppendRequest,
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> DraftResponse:
    updated = drafts.append_body(
        draft_id,
        text=payload.text,
        item_id=payload.item_id,
        excerpt=payload.excerpt,
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Draft not found")
    asyncio.create_task(index_draft(updated))
    return DraftResponse.from_draft(updated)


@router.get("/{draft_id}/sources", response_model=DraftSourceListResponse)
async def list_draft_sources(
    draft_id: str,
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> DraftSourceListResponse:
    if drafts.get(draft_id) is None:
        raise HTTPException(status_code=404, detail="Draft not found")
    rows = drafts.list_sources(draft_id)
    return DraftSourceListResponse(
        sources=[DraftSourceResponse.from_source(s) for s in rows]
    )


@router.delete("/{draft_id}/sources/{source_id}", status_code=204)
async def delete_draft_source(
    draft_id: str,
    source_id: int,
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> None:
    if not drafts.remove_source(draft_id, source_id):
        raise HTTPException(status_code=404, detail="Source not found")


@router.post("/{draft_id}/assist", response_model=DraftAssistResponse)
async def assist_draft(
    draft_id: str,
    payload: DraftAssistRequest,
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> DraftAssistResponse:
    draft = drafts.get(draft_id)
    if not draft:
        raise HTTPException(status_code=404, detail="Draft not found")
    try:
        suggestion = await run_assist(
            action=payload.action,
            draft_body=draft.body,
            selection=payload.selection,
            instructions=payload.instructions,
        )
    except AssistError as e:
        raise HTTPException(status_code=502, detail=str(e)) from e
    return DraftAssistResponse(suggestion=suggestion)
