"""
Article summarizer — single-pass Anthropic call returning a structured summary.

Trimmed port of the DataPoints summarizer: same prompts and output shape, but
no multi-provider, no critic/review pass, no cache. One JSON-shaped Anthropic
request via httpx, mirroring `services/assist.py`.
"""

from __future__ import annotations

import json
from dataclasses import dataclass

import httpx

from . import secret_store

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
HAIKU_MODEL = "claude-haiku-4-5"
SONNET_MODEL = "claude-sonnet-4-6"
MAX_TOKENS = 1024
MAX_CONTENT_LENGTH = 15000

_TECHNICAL_TERMS = (
    "algorithm", "neural", "quantum", "blockchain", "protocol",
    "cryptographic", "machine learning", "artificial intelligence",
    "api", "infrastructure", "architecture", "microservices",
    "distributed", "consensus", "encryption", "compiler",
    "semiconductor", "genomic", "molecular", "theorem",
)

SYSTEM_PROMPT = """You are a sharp technology columnist writing for software engineers and AI practitioners. Your voice is conversational and confident—closer to The Atlantic or Ars Technica than a press release or research abstract. You write to be read, not just to inform.

You are genuinely curious about every topic you cover. Even routine stories have something worth noticing—an unusual technical choice, a telling constraint, a quiet shift in how things work. Let that curiosity come through in which details you choose to highlight, not in your adjectives. Never amplify a company's own framing or hype—find what's actually interesting underneath it.

Core principles:
- Write like a person, not a pipeline. Vary sentence length—mix short punchy sentences with longer ones that unspool an idea. Avoid stacking multiple compound clauses into a single sentence.
- Present information directly and factually—no meta-language like "This article explains..." or "The author discusses..."
- Use active voice, concrete verbs, and plain language. Say "costs" not "is priced at," "broke" not "experienced a failure in."
- Include technical details when they matter; omit jargon that doesn't add meaning
- Let the summary breathe. Not every fact belongs in the prose—that's what key points are for. Prioritize narrative flow over completeness.
- Always connect stories to their practical implications for builders and practitioners
- Be skeptical of marketing language and press release hype—focus on substance
- Surface the detail that makes a reader pause and think—but through selection, not editorializing. Pick the interesting fact; don't tell the reader it's interesting."""

INSTRUCTION_PROMPT = """Summarize the article below. Respond with valid JSON only—no other text.

CONTENT TYPE DETECTION:
First, classify the article as one of: news, analysis, tutorial, review, research, newsletter
- news: Announcements, product launches, funding, acquisitions, breaking developments
- analysis: Opinion pieces, commentary, predictions, industry analysis
- tutorial: How-to guides, technical walkthroughs, implementation guides
- review: Product reviews, comparisons, evaluations
- research: Academic papers, technical reports, benchmark studies
- newsletter: Multi-story digests, roundups, curated links

HEADLINE GUIDELINES (8-12 words):
- Lead with the most searchable noun (company name, product, technology)
- Use a strong, active verb
- Include one concrete detail (number, name, or outcome)
- Do NOT repeat the article's original headline verbatim
- Avoid vague words: "new," "big," "major," "revolutionary," "game-changing"
- Avoid clickbait: "You won't believe," "Here's why," "Everything you need to know"

SUMMARY GUIDELINES:
Write 4-6 sentences as flowing prose—readable, not dense. Imagine someone skimming this over coffee.

For SINGLE-STORY articles (news, analysis, tutorial, review, research):
- ONE paragraph only. No paragraph breaks. This is critical — even long, complex stories get a single cohesive paragraph.
- Open with what happened. One clear sentence.
- Then develop the story naturally: pick the 2-3 most interesting details (not all of them) and weave them into sentences that each earn their place. Vary rhythm—follow a long explanatory sentence with a short declarative one.
- Close by connecting to the bigger picture, but make it feel like a natural thought, not a thesis statement. Never start with "This matters because..." or "This is significant for..."

For MULTI-STORY articles (newsletters, roundups, digests):
- First, identify each distinct news story or topic in the article. Each story gets its own paragraph.
- Separate paragraphs with \\n\\n. This is the ONLY content type that uses paragraph breaks.
- Each paragraph: 2-4 sentences covering one story. Lead with what happened, add the key detail, done.
- Order paragraphs by importance, not by the order they appeared in the original.
- Skip filler items, listicles of minor links, or "quick hits" sections — focus on the 3-5 most substantial stories.
- Close the most significant story with a bigger-picture thought.

ADDITIONAL GUIDELINES:
- If the article contains a notable quote from a primary source that captures the story's essence, include it
- If information conflicts or is disputed, present both sides neutrally
- If content appears truncated or paywalled, summarize only what's available and note the limitation
- Spell out numerals one through nine; use digits for 10 and above, currency, and large round numbers ("$15.99" not "fifteen ninety-nine dollars"; "8 billion" not "8B"; "percent" not "%")
- Use active voice and simple verbs ("released" not "has released")
- Omit background readers likely know ("OpenAI is an AI company")

KEY POINTS GUIDELINES:
- 3-5 bullet points with distinct, scannable takeaways
- Include specific facts, numbers, dates, or names
- For multi-story articles, prioritize across all stories by importance

Respond with this exact JSON structure:
{
  "headline": "Your headline here",
  "summary": "Your summary paragraphs here. Use \\n\\n for paragraph breaks in multi-story summaries.",
  "key_points": ["First point", "Second point", "Third point"],
  "content_type": "news|analysis|tutorial|review|research|newsletter"
}"""


class SummarizeError(Exception):
    """Raised when the summarizer cannot produce a summary."""


@dataclass
class ArticleSummary:
    headline: str
    summary: str
    key_points: list[str]
    content_type: str | None
    model_used: str


async def summarize_article(
    *,
    content: str,
    title: str = "",
    url: str = "",
) -> ArticleSummary:
    """Run a single Anthropic call to summarize `content`."""
    api_key = secret_store.get("anthropic")
    if not api_key:
        raise SummarizeError(
            "Anthropic API key is not configured. Set it in Settings → LLM Keys."
        )
    cleaned = (content or "").strip()
    if len(cleaned) < 200:
        raise SummarizeError(
            "Content is too short to summarize. Try fetching full text first."
        )

    model = _select_model(cleaned)
    article_block = _build_article_block(cleaned, title, url)

    payload = {
        "model": model,
        "max_tokens": MAX_TOKENS,
        "system": [
            {
                "type": "text",
                "text": SYSTEM_PROMPT,
                "cache_control": {"type": "ephemeral"},
            },
            {
                "type": "text",
                "text": INSTRUCTION_PROMPT,
                "cache_control": {"type": "ephemeral"},
            },
        ],
        "messages": [{"role": "user", "content": article_block}],
    }
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }

    async with httpx.AsyncClient(timeout=60.0) as client:
        try:
            resp = await client.post(ANTHROPIC_URL, headers=headers, json=payload)
        except httpx.HTTPError as e:
            raise SummarizeError(f"Network error: {e}") from e

    if resp.status_code != 200:
        raise SummarizeError(
            f"Anthropic API error {resp.status_code}: {resp.text[:400]}"
        )

    data = resp.json()
    blocks = data.get("content") or []
    text = "\n".join(b.get("text", "") for b in blocks if b.get("type") == "text")
    if not text.strip():
        raise SummarizeError("Anthropic returned an empty response.")

    parsed = _parse_json_response(text)
    return ArticleSummary(
        headline=parsed["headline"],
        summary=parsed["summary"],
        key_points=parsed["key_points"],
        content_type=parsed.get("content_type"),
        model_used=model,
    )


def _select_model(content: str) -> str:
    word_count = len(content.split())
    if word_count > 2000:
        return SONNET_MODEL
    lower = content.lower()
    technical_count = sum(1 for term in _TECHNICAL_TERMS if term in lower)
    if technical_count > 2:
        return SONNET_MODEL
    return HAIKU_MODEL


def _build_article_block(content: str, title: str, url: str) -> str:
    truncated = content[:MAX_CONTENT_LENGTH]
    if len(content) > MAX_CONTENT_LENGTH:
        truncated += "\n\n[Content truncated...]"
    parts: list[str] = []
    if title:
        parts.append(f"Original title: {title}")
    if url:
        parts.append(f"URL: {url}")
    parts.append("Article:")
    parts.append(truncated)
    return "\n".join(parts)


def _parse_json_response(text: str) -> dict:
    raw = text.strip()
    if raw.startswith("```"):
        lines = raw.split("\n")
        raw = "\n".join(
            lines[1:-1] if lines and lines[-1].strip() == "```" else lines[1:]
        )
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise SummarizeError(
            f"Could not parse summarizer response as JSON: {e}"
        ) from e

    headline = (data.get("headline") or "").strip()
    summary = (data.get("summary") or "").strip()
    key_points_raw = data.get("key_points") or []
    if not isinstance(key_points_raw, list):
        key_points_raw = []
    key_points = [str(p).strip() for p in key_points_raw if str(p).strip()][:5]
    if not headline or not summary:
        raise SummarizeError("Summarizer response missing headline or summary.")
    return {
        "headline": headline[:200],
        "summary": summary,
        "key_points": key_points,
        "content_type": data.get("content_type"),
    }
