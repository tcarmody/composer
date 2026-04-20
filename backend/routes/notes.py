"""Notes routes. X-API-Key guarded."""

import asyncio

from fastapi import APIRouter, Depends, HTTPException, Query

from ..auth import verify_api_key
from ..config import get_notes_repo
from ..repositories import NotesRepository
from ..schemas import (
    NoteCreateRequest,
    NoteListResponse,
    NotePatchRequest,
    NoteResponse,
)
from ..services.indexer import deindex, index_note

router = APIRouter(
    prefix="/notes",
    tags=["notes"],
    dependencies=[Depends(verify_api_key)],
)


@router.get("", response_model=NoteListResponse)
async def list_notes(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    notes: NotesRepository = Depends(get_notes_repo),
) -> NoteListResponse:
    rows, total = notes.list(limit=limit, offset=offset)
    return NoteListResponse(
        notes=[NoteResponse.from_note(n) for n in rows],
        total=total,
    )


@router.post("", response_model=NoteResponse, status_code=201)
async def create_note(
    payload: NoteCreateRequest,
    notes: NotesRepository = Depends(get_notes_repo),
) -> NoteResponse:
    note = notes.create(title=payload.title, body=payload.body)
    asyncio.create_task(index_note(note))
    return NoteResponse.from_note(note)


@router.get("/{note_id}", response_model=NoteResponse)
async def get_note(
    note_id: str,
    notes: NotesRepository = Depends(get_notes_repo),
) -> NoteResponse:
    note = notes.get(note_id)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return NoteResponse.from_note(note)


@router.patch("/{note_id}", response_model=NoteResponse)
async def patch_note(
    note_id: str,
    payload: NotePatchRequest,
    notes: NotesRepository = Depends(get_notes_repo),
) -> NoteResponse:
    updated = notes.update(note_id, title=payload.title, body=payload.body)
    if not updated:
        raise HTTPException(status_code=404, detail="Note not found")
    asyncio.create_task(index_note(updated))
    return NoteResponse.from_note(updated)


@router.delete("/{note_id}", status_code=204)
async def delete_note(
    note_id: str,
    notes: NotesRepository = Depends(get_notes_repo),
) -> None:
    if not notes.delete(note_id):
        raise HTTPException(status_code=404, detail="Note not found")
    deindex("note", note_id)
