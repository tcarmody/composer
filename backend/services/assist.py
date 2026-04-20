"""
AI assist for drafts — grounded text transformations via Anthropic.

One call, no streaming, no tools. Keep the surface small: the client
picks an action, optionally narrows to a selection, and we rewrite.
"""

from typing import Literal

import httpx

from ..config import config

AssistAction = Literal["rewrite", "expand", "summarize", "tighten"]

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
DEFAULT_MODEL = "claude-sonnet-4-6"
MAX_TOKENS = 2048

_ACTION_PROMPTS: dict[str, str] = {
    "rewrite": (
        "Rewrite the passage for clarity, rhythm, and directness. Keep the "
        "author's voice and factual content unchanged."
    ),
    "expand": (
        "Expand the passage with additional detail, context, and concrete "
        "examples drawn from the surrounding draft. Do not invent facts."
    ),
    "summarize": (
        "Summarize the passage in one tight paragraph. Preserve the key "
        "claims; drop filler."
    ),
    "tighten": (
        "Tighten the passage: cut hedging, redundancy, and throat-clearing. "
        "Preserve meaning and the author's voice."
    ),
}


class AssistError(Exception):
    """Raised when assist cannot be produced."""


async def run_assist(
    *,
    action: AssistAction,
    draft_body: str,
    selection: str | None,
    instructions: str | None,
) -> str:
    if not config.ANTHROPIC_API_KEY:
        raise AssistError(
            "ANTHROPIC_API_KEY is not configured on the server."
        )

    task = _ACTION_PROMPTS[action]
    target = (selection or draft_body).strip()
    if not target:
        raise AssistError("Nothing to assist on — selection is empty.")

    system = (
        "You are an editing assistant for a writer's long-form draft. "
        "Return only the revised passage as plain markdown — no preamble, "
        "no quotation marks, no commentary."
    )

    user_parts: list[str] = [f"Task: {task}"]
    if instructions and instructions.strip():
        user_parts.append(f"Additional instructions: {instructions.strip()}")
    if selection and selection.strip() and selection.strip() != draft_body.strip():
        user_parts.append(
            "Full draft (for context; only revise the selection):\n\n"
            f"{draft_body.strip()}"
        )
        user_parts.append(f"Selection to revise:\n\n{selection.strip()}")
    else:
        user_parts.append(f"Passage:\n\n{target}")

    payload = {
        "model": config.LLM_MODEL or DEFAULT_MODEL,
        "max_tokens": MAX_TOKENS,
        "system": system,
        "messages": [{"role": "user", "content": "\n\n".join(user_parts)}],
    }

    headers = {
        "x-api-key": config.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }

    async with httpx.AsyncClient(timeout=60.0) as client:
        try:
            resp = await client.post(ANTHROPIC_URL, headers=headers, json=payload)
        except httpx.HTTPError as e:
            raise AssistError(f"Network error: {e}") from e

    if resp.status_code != 200:
        raise AssistError(
            f"Anthropic API error {resp.status_code}: {resp.text[:400]}"
        )

    data = resp.json()
    blocks = data.get("content") or []
    texts = [b.get("text", "") for b in blocks if b.get("type") == "text"]
    suggestion = "\n".join(t for t in texts if t).strip()
    if not suggestion:
        raise AssistError("Anthropic returned an empty response.")
    return suggestion
