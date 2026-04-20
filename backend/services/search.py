"""
Hybrid retrieval — combines FTS5 BM25 and dense vector similarity with
Reciprocal Rank Fusion.

Each leg (BM25, cosine) produces its own ranked list over chunk_ids.
We fuse by RRF: score(chunk) = sum over legs of 1/(k + rank). Higher is
better. If the query can't be embedded (Voyage not configured / down),
we degrade gracefully to BM25-only.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from typing import Literal

from ..repositories.chunks import Chunk, ChunksRepository
from ..repositories.drafts import DraftsRepository
from ..repositories.items import ItemRepository
from ..repositories.notes import NotesRepository
from .embeddings import EmbeddingError, embed_query

logger = logging.getLogger(__name__)

SourceType = Literal["item", "note", "draft"]

RRF_K = 60
PER_LEG_MULTIPLIER = 4  # fetch 4x limit per leg before fusing


@dataclass
class HydratedHit:
    chunk: Chunk
    source_title: str | None
    source_url: str | None
    score: float
    bm25_rank: int | None
    vector_rank: int | None


def _sanitize_fts(query: str) -> str:
    """Wrap each token in double quotes so FTS5 operator chars can't
    hijack the query. Returns an empty string if nothing usable remains."""
    cleaned = query.replace('"', " ").replace("\x00", " ")
    tokens = [t for t in cleaned.split() if t]
    if not tokens:
        return ""
    return " ".join(f'"{t}"' for t in tokens)


def _cosine(a: list[float], b: list[float]) -> float:
    if len(a) != len(b):
        return 0.0
    dot = 0.0
    na = 0.0
    nb = 0.0
    for x, y in zip(a, b):
        dot += x * y
        na += x * x
        nb += y * y
    if na == 0.0 or nb == 0.0:
        return 0.0
    return dot / (math.sqrt(na) * math.sqrt(nb))


def _rrf_merge(
    rank_lists: list[list[str]], *, k: int, limit: int
) -> list[str]:
    scores: dict[str, float] = {}
    for ranked in rank_lists:
        for i, chunk_id in enumerate(ranked):
            scores[chunk_id] = scores.get(chunk_id, 0.0) + 1.0 / (k + i + 1)
    return [cid for cid, _ in sorted(scores.items(), key=lambda kv: kv[1], reverse=True)[:limit]]


async def hybrid_search(
    *,
    query: str,
    source_types: list[SourceType] | None,
    limit: int,
    chunks_repo: ChunksRepository,
    items_repo: ItemRepository,
    notes_repo: NotesRepository,
    drafts_repo: DraftsRepository,
) -> tuple[list[HydratedHit], bool]:
    fts_query = _sanitize_fts(query)
    per_leg = limit * PER_LEG_MULTIPLIER

    bm25_hits: list[tuple[str, float]] = []
    if fts_query:
        bm25_hits = chunks_repo.fts_search(
            query=fts_query, source_types=source_types, limit=per_leg
        )
    bm25_rank = {cid: i for i, (cid, _) in enumerate(bm25_hits)}

    vector_used = False
    vec_rank: dict[str, int] = {}
    try:
        _, qvec = await embed_query(query)
        vector_used = True
    except EmbeddingError as e:
        logger.info("Vector leg skipped: %s", e)
        qvec = None

    if qvec is not None:
        candidates = chunks_repo.iter_with_embeddings(source_types)
        scored = [
            (cid, _cosine(qvec, vec))
            for (cid, _st, _sid, _ci, _content, vec) in candidates
        ]
        scored.sort(key=lambda t: t[1], reverse=True)
        vec_rank = {cid: i for i, (cid, _) in enumerate(scored[:per_leg])}

    rank_lists: list[list[str]] = []
    if bm25_rank:
        rank_lists.append([cid for cid, _ in bm25_hits])
    if vec_rank:
        rank_lists.append([cid for cid, _ in sorted(vec_rank.items(), key=lambda kv: kv[1])])

    if not rank_lists:
        return [], vector_used

    fused_ids = _rrf_merge(rank_lists, k=RRF_K, limit=limit)
    if not fused_ids:
        return [], vector_used

    chunks_by_id = chunks_repo.get_many(fused_ids)
    hits: list[HydratedHit] = []
    needed_items = {c.source_id for c in chunks_by_id.values() if c.source_type == "item"}
    needed_notes = {c.source_id for c in chunks_by_id.values() if c.source_type == "note"}
    needed_drafts = {c.source_id for c in chunks_by_id.values() if c.source_type == "draft"}
    items_map = {iid: items_repo.get(iid) for iid in needed_items}
    notes_map = {nid: notes_repo.get(nid) for nid in needed_notes}
    drafts_map = {did: drafts_repo.get(did) for did in needed_drafts}

    scores: dict[str, float] = {}
    for ranked in rank_lists:
        for i, cid in enumerate(ranked):
            scores[cid] = scores.get(cid, 0.0) + 1.0 / (RRF_K + i + 1)

    for cid in fused_ids:
        chunk = chunks_by_id.get(cid)
        if chunk is None:
            continue
        title: str | None = None
        url: str | None = None
        if chunk.source_type == "item":
            it = items_map.get(chunk.source_id)
            if it is not None:
                title = it.title
                url = it.url
        elif chunk.source_type == "note":
            n = notes_map.get(chunk.source_id)
            if n is not None:
                title = n.title
        elif chunk.source_type == "draft":
            d = drafts_map.get(chunk.source_id)
            if d is not None:
                title = d.title
        hits.append(
            HydratedHit(
                chunk=chunk,
                source_title=title,
                source_url=url,
                score=scores.get(cid, 0.0),
                bm25_rank=bm25_rank.get(cid),
                vector_rank=vec_rank.get(cid),
            )
        )
    return hits, vector_used
