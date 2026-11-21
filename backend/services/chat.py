"""
Streaming chat with citations.

Retrieves chunks via hybrid_search, builds a numbered-sources prompt,
then streams Anthropic's Messages API and re-emits the stream as
Server-Sent Events for our frontend:

  event: citations   — emitted first, lists the numbered sources
  event: delta       — one per text delta from Claude
  event: done        — stop_reason at the end
  event: error       — any failure, including a refusal

If ANTHROPIC_API_KEY is missing, we emit `error` and stop. If the
retrieval has no hits, we still send the question to Claude with an
explicit "no sources" signal so the model declines cleanly.
"""

from __future__ import annotations

import json
import logging
from typing import AsyncIterator, Literal

from dpcommon.llm import StreamEnd

from ..repositories.chunks import ChunksRepository
from ..repositories.drafts import DraftsRepository
from ..repositories.items import ItemRepository
from ..repositories.notes import NotesRepository
from ..schemas import ChatMessage
from . import llm
from .search import hybrid_search

logger = logging.getLogger(__name__)

SourceType = Literal["item", "note", "draft"]

MAX_TOKENS = 2048
STREAM_TIMEOUT = 120.0

SYSTEM_PROMPT = (
    "You are a research assistant helping a writer query their personal "
    "archive of articles, notes, and drafts. Answer using only the numbered "
    "sources provided below. Cite every factual claim inline with bracketed "
    "source numbers such as [1] or [2, 3]. If the sources do not support an "
    "answer, say so plainly — do not invent facts, do not cite sources that "
    "are not listed. Keep answers direct and grounded."
)


def _sse(event: str, data: dict) -> bytes:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n".encode("utf-8")


def _format_sources(hits: list) -> str:
    lines: list[str] = []
    for i, h in enumerate(hits, start=1):
        header = f"[{i}] ({h.chunk.source_type}"
        if h.source_title:
            header += f': "{h.source_title}"'
        header += ")"
        lines.append(f"{header}\n{h.chunk.content.strip()}")
    return "\n\n".join(lines)


async def stream_chat(
    *,
    query: str,
    source_types: list[SourceType] | None,
    limit: int,
    chunks_repo: ChunksRepository,
    items_repo: ItemRepository,
    notes_repo: NotesRepository,
    drafts_repo: DraftsRepository,
    history: list[ChatMessage] | None = None,
) -> AsyncIterator[bytes]:
    provider = llm.get_provider()
    if provider is None:
        yield _sse("error", {"message": llm.KEY_MISSING_MESSAGE})
        return

    hits, vector_used = await hybrid_search(
        query=query,
        source_types=source_types,
        limit=limit,
        chunks_repo=chunks_repo,
        items_repo=items_repo,
        notes_repo=notes_repo,
        drafts_repo=drafts_repo,
    )

    citations = [
        {
            "index": i + 1,
            "chunk_id": h.chunk.id,
            "source_type": h.chunk.source_type,
            "source_id": h.chunk.source_id,
            "source_title": h.source_title,
            "source_url": h.source_url,
            "chunk_index": h.chunk.chunk_index,
            "snippet": h.chunk.content,
        }
        for i, h in enumerate(hits)
    ]
    yield _sse(
        "citations",
        {"citations": citations, "vector_search_used": vector_used},
    )

    if hits:
        user_content = (
            f"Sources:\n\n{_format_sources(hits)}\n\nQuestion: {query}"
        )
    else:
        user_content = (
            f"Question: {query}\n\n"
            "(No sources were retrieved from the archive for this question.)"
        )

    messages: list[dict] = []
    if history:
        for m in history:
            messages.append({"role": m.role, "content": m.content})
    messages.append({"role": "user", "content": user_content})

    try:
        async for item in provider.stream_chat_async(
            messages,
            system_prompt=SYSTEM_PROMPT,
            model=llm.chat_model(),
            max_tokens=MAX_TOKENS,
            timeout=STREAM_TIMEOUT,
        ):
            if isinstance(item, StreamEnd):
                if item.stop_reason == "refusal":
                    yield _sse(
                        "error",
                        {"message": f"Claude declined this request (category: {item.refusal_category})."},
                    )
                    return
                yield _sse("done", {"stop_reason": item.stop_reason})
            else:
                yield _sse("delta", {"text": item})
    except llm.LLM_ERRORS as e:
        yield _sse("error", {"message": llm.describe_error(e)})
