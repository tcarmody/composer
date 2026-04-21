"""Chat routes — SSE streaming. X-API-Key guarded."""

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from ..auth import verify_api_key
from ..config import (
    get_chunks_repo,
    get_drafts_repo,
    get_items_repo,
    get_notes_repo,
)
from ..repositories import (
    ChunksRepository,
    DraftsRepository,
    ItemRepository,
    NotesRepository,
)
from ..schemas import ChatRequest
from ..services.chat import stream_chat

router = APIRouter(
    prefix="/v1/chat",
    tags=["chat"],
    dependencies=[Depends(verify_api_key)],
)


@router.post("")
async def chat(
    payload: ChatRequest,
    chunks: ChunksRepository = Depends(get_chunks_repo),
    items: ItemRepository = Depends(get_items_repo),
    notes: NotesRepository = Depends(get_notes_repo),
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> StreamingResponse:
    generator = stream_chat(
        query=payload.query,
        source_types=payload.source_types,
        limit=payload.limit,
        chunks_repo=chunks,
        items_repo=items,
        notes_repo=notes,
        drafts_repo=drafts,
        history=payload.history,
    )
    return StreamingResponse(
        generator,
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
