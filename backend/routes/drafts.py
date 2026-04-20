"""Drafts routes. X-API-Key guarded."""

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import verify_api_key
from ..config import get_drafts_repo
from ..repositories import DraftsRepository
from ..schemas import (
    DraftCreateRequest,
    DraftListResponse,
    DraftPatchRequest,
    DraftResponse,
)

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
    return DraftResponse.from_draft(updated)


@router.delete("/{draft_id}", status_code=204)
async def delete_draft(
    draft_id: str,
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> None:
    if not drafts.delete(draft_id):
        raise HTTPException(status_code=404, detail="Draft not found")
