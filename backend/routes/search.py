"""Search routes. X-API-Key guarded."""

from fastapi import APIRouter, Depends

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
from ..schemas import SearchHit, SearchRequest, SearchResponse
from ..services.search import hybrid_search

router = APIRouter(
    prefix="/v1/search",
    tags=["search"],
    dependencies=[Depends(verify_api_key)],
)


@router.post("", response_model=SearchResponse)
async def search(
    payload: SearchRequest,
    chunks: ChunksRepository = Depends(get_chunks_repo),
    items: ItemRepository = Depends(get_items_repo),
    notes: NotesRepository = Depends(get_notes_repo),
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> SearchResponse:
    hits, vector_used = await hybrid_search(
        query=payload.query,
        source_types=payload.source_types,
        limit=payload.limit,
        chunks_repo=chunks,
        items_repo=items,
        notes_repo=notes,
        drafts_repo=drafts,
    )
    return SearchResponse(
        query=payload.query,
        vector_search_used=vector_used,
        hits=[
            SearchHit(
                chunk_id=h.chunk.id,
                source_type=h.chunk.source_type,
                source_id=h.chunk.source_id,
                source_title=h.source_title,
                source_url=h.source_url,
                chunk_index=h.chunk.chunk_index,
                content=h.chunk.content,
                score=h.score,
                bm25_rank=h.bm25_rank,
                vector_rank=h.vector_rank,
            )
            for h in hits
        ],
    )
