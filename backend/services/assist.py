"""
AI assist for drafts — grounded text transformations via Anthropic.

One call, no streaming, no tools. Keep the surface small: the client
picks an action, optionally narrows to a selection, and we rewrite.
"""

from typing import Literal

from . import llm

AssistAction = Literal["rewrite", "expand", "summarize", "tighten", "audio"]

MAX_TOKENS = 2048
TIMEOUT = 60.0

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
    "audio": (
        "Rewrite the passage as a script for a human to read aloud in a recording. "
        "Preserve the intelligence, accuracy, and substance, but loosen the "
        "register: favor contractions, shorter sentences, and natural spoken "
        "cadence over written formality. The voice is an expert speaking "
        "familiarly with an attentive student — warm, pedagogical, lightly "
        "conversational, never folksy or glib. Match the source word count "
        "closely — within about ten percent. Sentence count may go up if the "
        "sentences are correspondingly shorter; what matters is that the total "
        "word count holds. Do not pad with explanatory sentences, transitional "
        "phrases, or bridging examples — this is the main failure mode. Reduce "
        "parenthetical asides and em-dash interjections by folding them into the "
        "surrounding prose or splitting them into short sentences, without adding "
        "bridge words to stitch the result. Do not introduce phrases like \"This "
        "is why,\" \"Put another way,\" or \"Consider\" where the source doesn't "
        "already turn the corner that way; where a transition is needed, keep it "
        "short (\"so,\" \"but,\" \"and\"). Round figures and percentages to at "
        "most two significant digits and hedge them with \"about,\" \"roughly,\" "
        "\"a little over,\" or \"nearly\" (e.g., 47.3% → about 47 percent; $1,284 "
        "→ roughly thirteen hundred dollars; 2.718 → around two-point-seven). "
        "Spell out symbols and units the way a reader would say them (% → "
        "percent, $ → dollars, & → and). Expand uncommon acronyms on first "
        "mention. Italicize the words and short phrases the reader should lean "
        "on for emphasis — sparingly, two or three per paragraph at most, on the "
        "load-bearing term, not the whole clause. Avoid colloquial signposts like "
        "\"here's the thing\" or \"and here's why.\" Strip bracketed citations, "
        "footnote markers, and anything else that reads as visual furniture. Do "
        "not add new facts, examples, or opinions; do not change conclusions. "
        "Return prose only — no headers, no bullet lists, no stage directions."
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
    provider = llm.get_provider()
    if provider is None:
        raise AssistError(llm.KEY_MISSING_MESSAGE)

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

    try:
        result = await provider.complete_async(
            user_prompt="\n\n".join(user_parts),
            system_prompt=system,
            model=llm.chat_model(),
            max_tokens=MAX_TOKENS,
            timeout=TIMEOUT,
        )
    except llm.LLM_ERRORS as e:
        raise AssistError(llm.describe_error(e)) from e

    suggestion = result.text.strip()
    if not suggestion:
        raise AssistError("Anthropic returned an empty response.")
    return suggestion
