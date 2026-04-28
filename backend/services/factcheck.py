"""
Streaming, per-claim fact-check.

Two-stage pipeline:

  1. **Extract** — one fast Haiku call. Pulls verbatim verifiable claims from
     the passage. No tools. Returns IDs + offsets.
  2. **Verify** — one Sonnet+web_search call per claim, in parallel (capped by
     a semaphore). Each call returns a verdict, explanation, suggested
     correction, and source citations.

Emits as a stream of typed events; a thin SSE adapter lives in the route.

  extracted  → fired once with the full claim list (with offsets in the
               passage) so the UI can render placeholders immediately
  verdict    → fired per claim as its verification completes
  done       → fired once at the end with the model used
  error      → fired on extraction failure, or per-claim on verify failure
"""

from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass, field
from typing import AsyncIterator, Literal

import httpx

from ..config import config
from . import secret_store

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
EXTRACT_MODEL = "claude-haiku-4-5"
VERIFY_MODEL = "claude-sonnet-4-6"
EXTRACT_MAX_TOKENS = 1024
VERIFY_MAX_TOKENS = 2048
VERIFY_MAX_SEARCHES = 4
VERIFY_CONCURRENCY = 3
EXTRACT_TIMEOUT = 60.0
VERIFY_TIMEOUT = 180.0
MAX_CLAIMS = 8

Verdict = Literal["supported", "contradicted", "unverified", "needs_context"]
_VALID_VERDICTS: set[str] = {
    "supported",
    "contradicted",
    "unverified",
    "needs_context",
}


EXTRACT_SYSTEM = """You extract verifiable factual claims from a passage so a fact-checker can verify them one by one.

Pick the most consequential claims worth checking: names, dates, numbers, quotes, events, attributions, causal claims. Skip opinions, rhetorical framings, and general background a careful reader would already know.

For each claim, return the EXACT verbatim substring from the passage so it can be located by string match. Do not paraphrase. Do not merge two claims into one quote. Do not split mid-sentence unless the claim itself is mid-sentence.

Cap output at 8 claims. Order by importance.

Respond with JSON only — no fences, no commentary:
{
  "claims": [
    {"claim": "<verbatim substring>", "kind": "stat|date|name|quote|event|attribution|cause"}
  ]
}"""


VERIFY_SYSTEM = """You are a careful fact-checker. You will be given ONE claim from a writer's draft and the passage it came from for context. Use the web_search tool to verify the claim against primary or reputable secondary sources.

Be conservative: prefer "unverified" over a confident verdict you cannot ground in the search results. If you find that the claim is wrong, suggest a corrected version that the writer could paste in.

Respond with JSON only — no fences, no commentary:
{
  "verdict": "supported" | "contradicted" | "unverified" | "needs_context",
  "explanation": "<one or two sentences citing what you found>",
  "suggested_correction": "<rewrite of the claim if contradicted, else null>",
  "sources": [
    {"title": "<source title>", "url": "<source url>", "snippet": "<short supporting quote>"}
  ]
}

Rules:
- "supported": the claim is well-supported by the sources.
- "contradicted": the sources clearly disagree with the claim — provide a correction.
- "unverified": you could not find sources strong enough to judge.
- "needs_context": the claim is technically true but misleading without context — explain.
- Always include at least one source unless verdict is "unverified" with no useful results."""


class FactCheckError(Exception):
    """Raised when fact-check cannot be produced."""


@dataclass
class FactCheckSource:
    title: str
    url: str
    snippet: str | None = None


@dataclass
class FactCheckClaim:
    id: str
    claim: str
    kind: str | None = None
    offset: int | None = None
    length: int | None = None
    verdict: Verdict | None = None
    explanation: str = ""
    suggested_correction: str | None = None
    sources: list[FactCheckSource] = field(default_factory=list)


@dataclass
class ExtractedEvent:
    claims: list[FactCheckClaim]


@dataclass
class VerdictEvent:
    claim_id: str
    verdict: Verdict
    explanation: str
    suggested_correction: str | None
    sources: list[FactCheckSource]


@dataclass
class DoneEvent:
    model_used: str


@dataclass
class ErrorEvent:
    message: str
    claim_id: str | None = None


FactCheckEvent = ExtractedEvent | VerdictEvent | DoneEvent | ErrorEvent


async def factcheck_events(
    *,
    draft_body: str,
    selection: str | None,
) -> AsyncIterator[FactCheckEvent]:
    """Async generator of fact-check events. Suitable for SSE adaptation."""
    api_key = secret_store.get("anthropic")
    if not api_key:
        yield ErrorEvent(
            message=(
                "Anthropic API key is not configured. "
                "Set it in Settings → LLM Keys."
            )
        )
        return

    body = (draft_body or "").strip()
    sel = (selection or "").strip()
    passage = sel or body
    if not passage:
        yield ErrorEvent(message="Nothing to fact-check — passage is empty.")
        return

    # Stage 1: extraction
    try:
        raw_claims = await _extract_claims(passage, body, api_key)
    except FactCheckError as e:
        yield ErrorEvent(message=str(e))
        return

    claims: list[FactCheckClaim] = []
    for i, c in enumerate(raw_claims[:MAX_CLAIMS]):
        text = (c.get("claim") or "").strip()
        if not text:
            continue
        offset, length = _locate(text, passage)
        claims.append(
            FactCheckClaim(
                id=f"c{i}",
                claim=text,
                kind=(c.get("kind") or None),
                offset=offset,
                length=length,
            )
        )

    yield ExtractedEvent(claims=claims)
    if not claims:
        yield DoneEvent(model_used=VERIFY_MODEL)
        return

    # Stage 2: parallel verification, results emitted as they finish
    queue: asyncio.Queue[FactCheckEvent] = asyncio.Queue()
    sem = asyncio.Semaphore(VERIFY_CONCURRENCY)

    async def worker(claim: FactCheckClaim) -> None:
        async with sem:
            try:
                event = await _verify_claim(claim, passage, body, api_key)
            except FactCheckError as e:
                event = ErrorEvent(message=str(e), claim_id=claim.id)
            await queue.put(event)

    tasks = [asyncio.create_task(worker(c)) for c in claims]
    pending = len(tasks)
    try:
        while pending > 0:
            event = await queue.get()
            yield event
            pending -= 1
    finally:
        for t in tasks:
            if not t.done():
                t.cancel()

    yield DoneEvent(model_used=VERIFY_MODEL)


# ─── stage 1: claim extraction ──────────────────────────


async def _extract_claims(
    passage: str,
    full_body: str,
    api_key: str,
) -> list[dict]:
    user_parts: list[str] = []
    if passage != full_body and full_body:
        user_parts.append("Full draft (for context only):\n\n" + full_body)
        user_parts.append("Passage to extract claims from:\n\n" + passage)
    else:
        user_parts.append("Passage:\n\n" + passage)

    payload = {
        "model": config.LLM_MODEL or EXTRACT_MODEL,
        "max_tokens": EXTRACT_MAX_TOKENS,
        "system": EXTRACT_SYSTEM,
        "messages": [{"role": "user", "content": "\n\n".join(user_parts)}],
    }
    text = await _post_messages(payload, api_key, EXTRACT_TIMEOUT)
    parsed = _parse_json(text)
    claims = parsed.get("claims") if isinstance(parsed, dict) else None
    if not isinstance(claims, list):
        raise FactCheckError("Extraction response missing 'claims' array.")
    return claims


# ─── stage 2: per-claim verification ────────────────────


async def _verify_claim(
    claim: FactCheckClaim,
    passage: str,
    full_body: str,
    api_key: str,
) -> VerdictEvent:
    user_parts = [f"Claim to verify:\n\n{claim.claim}"]
    if passage and passage != claim.claim:
        user_parts.append(f"Surrounding passage (context only):\n\n{passage}")
    if full_body and full_body != passage:
        user_parts.append(f"Full draft (additional context):\n\n{full_body}")

    payload = {
        "model": VERIFY_MODEL,
        "max_tokens": VERIFY_MAX_TOKENS,
        "system": VERIFY_SYSTEM,
        "tools": [
            {
                "type": "web_search_20250305",
                "name": "web_search",
                "max_uses": VERIFY_MAX_SEARCHES,
            }
        ],
        "messages": [{"role": "user", "content": "\n\n".join(user_parts)}],
    }
    text = await _post_messages(payload, api_key, VERIFY_TIMEOUT)
    raw = _parse_json(text)
    if not isinstance(raw, dict):
        raise FactCheckError("Verification response was not a JSON object.")

    verdict_raw = (raw.get("verdict") or "unverified").strip()
    verdict: Verdict = (
        verdict_raw if verdict_raw in _VALID_VERDICTS else "unverified"  # type: ignore[assignment]
    )
    explanation = (raw.get("explanation") or "").strip()

    correction = raw.get("suggested_correction")
    correction = (
        correction.strip()
        if isinstance(correction, str) and correction.strip()
        else None
    )

    sources: list[FactCheckSource] = []
    sources_raw = raw.get("sources") or []
    if isinstance(sources_raw, list):
        for s in sources_raw:
            if not isinstance(s, dict):
                continue
            url = (s.get("url") or "").strip()
            if not url:
                continue
            sources.append(
                FactCheckSource(
                    title=(s.get("title") or url).strip(),
                    url=url,
                    snippet=(s.get("snippet") or "").strip() or None,
                )
            )

    return VerdictEvent(
        claim_id=claim.id,
        verdict=verdict,
        explanation=explanation,
        suggested_correction=correction,
        sources=sources,
    )


# ─── shared helpers ─────────────────────────────────────


async def _post_messages(payload: dict, api_key: str, timeout: float) -> str:
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            resp = await client.post(ANTHROPIC_URL, headers=headers, json=payload)
        except httpx.HTTPError as e:
            raise FactCheckError(f"Network error: {e}") from e
    if resp.status_code != 200:
        raise FactCheckError(
            f"Anthropic API error {resp.status_code}: {resp.text[:400]}"
        )
    data = resp.json()
    blocks = data.get("content") or []
    text = "\n".join(b.get("text", "") for b in blocks if b.get("type") == "text").strip()
    if not text:
        raise FactCheckError("Anthropic returned no text.")
    return text


def _parse_json(text: str) -> dict | list:
    raw = text.strip()
    if raw.startswith("```"):
        lines = raw.split("\n")
        raw = "\n".join(
            lines[1:-1] if lines and lines[-1].strip() == "```" else lines[1:]
        )
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise FactCheckError(f"Could not parse response as JSON: {e}") from e


def _locate(claim: str, passage: str) -> tuple[int | None, int | None]:
    if not claim:
        return None, None
    idx = passage.find(claim)
    if idx >= 0:
        return idx, len(claim)
    return None, None


# ─── SSE adapter ────────────────────────────────────────


def _sse(event: str, data: dict) -> bytes:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n".encode("utf-8")


async def stream_factcheck_sse(
    *,
    draft_body: str,
    selection: str | None,
) -> AsyncIterator[bytes]:
    """SSE byte stream — adapts factcheck_events for StreamingResponse."""
    async for event in factcheck_events(
        draft_body=draft_body, selection=selection
    ):
        if isinstance(event, ExtractedEvent):
            yield _sse(
                "extracted",
                {
                    "claims": [
                        {
                            "id": c.id,
                            "claim": c.claim,
                            "kind": c.kind,
                            "offset": c.offset,
                            "length": c.length,
                        }
                        for c in event.claims
                    ]
                },
            )
        elif isinstance(event, VerdictEvent):
            yield _sse(
                "verdict",
                {
                    "claim_id": event.claim_id,
                    "verdict": event.verdict,
                    "explanation": event.explanation,
                    "suggested_correction": event.suggested_correction,
                    "sources": [
                        {"title": s.title, "url": s.url, "snippet": s.snippet}
                        for s in event.sources
                    ],
                },
            )
        elif isinstance(event, DoneEvent):
            yield _sse("done", {"model_used": event.model_used})
        elif isinstance(event, ErrorEvent):
            payload: dict = {"message": event.message}
            if event.claim_id:
                payload["claim_id"] = event.claim_id
            yield _sse("error", payload)
