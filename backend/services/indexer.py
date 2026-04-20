"""
Indexer — chunks + embeds content from items / notes / drafts and
writes the result into the chunks table.

Called from save paths as a fire-and-forget asyncio.Task so the user
doesn't wait on the embedding API. If Voyage isn't configured or
errors, we still store chunks (without embeddings) so FTS retrieval
keeps working.
"""

import logging
from typing import Literal

from ..config import state
from ..repositories.chunks import ChunksRepository, SourceType
from ..repositories.drafts import Draft
from ..repositories.items import Item
from ..repositories.notes import Note
from .chunker import chunk_text
from .embeddings import EmbeddingError, embed_documents

logger = logging.getLogger(__name__)


def _compose_item_text(item: Item) -> str:
    parts: list[str] = []
    if item.summary:
        parts.append(item.summary.strip())
    if item.key_points:
        parts.append("\n\n".join(f"- {p}" for p in item.key_points))
    if item.content:
        parts.append(item.content.strip())
    return "\n\n".join(p for p in parts if p)


async def _index_source(
    *,
    source_type: SourceType,
    source_id: str,
    title: str | None,
    text: str,
    chunks_repo: ChunksRepository,
) -> int:
    chunks = chunk_text(text, title=title)
    if not chunks:
        chunks_repo.delete_for_source(source_type=source_type, source_id=source_id)
        return 0

    contents = [c.content for c in chunks]
    model: str | None = None
    vectors: list[list[float] | None] = [None] * len(contents)
    try:
        model, vecs = await embed_documents(contents)
        vectors = [list(v) for v in vecs]
    except EmbeddingError as e:
        logger.warning("Embedding skipped for %s %s: %s", source_type, source_id, e)

    chunks_repo.replace_for_source(
        source_type=source_type,
        source_id=source_id,
        chunks=[
            (contents[i], vectors[i], model) for i in range(len(contents))
        ],
    )
    return len(contents)


async def index_item(item: Item) -> int:
    chunks_repo = state.chunks
    if chunks_repo is None:
        return 0
    if item.archived_at is not None:
        chunks_repo.delete_for_source(source_type="item", source_id=item.id)
        return 0
    text = _compose_item_text(item)
    return await _index_source(
        source_type="item",
        source_id=item.id,
        title=item.title,
        text=text,
        chunks_repo=chunks_repo,
    )


async def index_note(note: Note) -> int:
    chunks_repo = state.chunks
    if chunks_repo is None:
        return 0
    return await _index_source(
        source_type="note",
        source_id=note.id,
        title=note.title,
        text=note.body,
        chunks_repo=chunks_repo,
    )


async def index_draft(draft: Draft) -> int:
    chunks_repo = state.chunks
    if chunks_repo is None:
        return 0
    return await _index_source(
        source_type="draft",
        source_id=draft.id,
        title=draft.title,
        text=draft.body,
        chunks_repo=chunks_repo,
    )


def deindex(source_type: SourceType, source_id: str) -> None:
    chunks_repo = state.chunks
    if chunks_repo is None:
        return
    chunks_repo.delete_for_source(source_type=source_type, source_id=source_id)


async def reindex_all() -> dict[str, int]:
    """Re-chunk and re-embed every item/note/draft. Returns counts."""
    if (
        state.items is None
        or state.notes is None
        or state.drafts is None
        or state.chunks is None
    ):
        return {"item": 0, "note": 0, "draft": 0}

    totals = {"item": 0, "note": 0, "draft": 0}
    items, _ = state.items.list(limit=10_000, offset=0, archived=False)
    for it in items:
        totals["item"] += await index_item(it)
    notes, _ = state.notes.list(limit=10_000, offset=0)
    for n in notes:
        totals["note"] += await index_note(n)
    drafts, _ = state.drafts.list(limit=10_000, offset=0)
    for d in drafts:
        totals["draft"] += await index_draft(d)
    return totals
