"""
Embedding client — Voyage AI.

Single async function that batches inputs and returns (model, vectors).
Voyage caps request size; we split into sub-batches to stay under
128 inputs per call. Inputs that are too long will error server-side
(we truncate to TRUNCATE_CHARS as a local safety net).
"""

import httpx

from ..config import config

VOYAGE_URL = "https://api.voyageai.com/v1/embeddings"
DEFAULT_MODEL = "voyage-3"
BATCH_SIZE = 64
TRUNCATE_CHARS = 32_000


class EmbeddingError(Exception):
    pass


def _resolve_model() -> str:
    env_model = getattr(config, "EMBEDDING_MODEL", None)
    return env_model or DEFAULT_MODEL


async def embed_documents(texts: list[str]) -> tuple[str, list[list[float]]]:
    return await _embed(texts, input_type="document")


async def embed_query(text: str) -> tuple[str, list[float]]:
    model, vecs = await _embed([text], input_type="query")
    return model, vecs[0]


async def _embed(
    texts: list[str], *, input_type: str
) -> tuple[str, list[list[float]]]:
    if not config.VOYAGE_API_KEY:
        raise EmbeddingError("VOYAGE_API_KEY is not configured on the server.")
    if not texts:
        return _resolve_model(), []

    truncated = [t[:TRUNCATE_CHARS] for t in texts]
    model = _resolve_model()
    headers = {
        "Authorization": f"Bearer {config.VOYAGE_API_KEY}",
        "content-type": "application/json",
    }

    results: list[list[float]] = []
    async with httpx.AsyncClient(timeout=60.0) as client:
        for start in range(0, len(truncated), BATCH_SIZE):
            batch = truncated[start : start + BATCH_SIZE]
            payload = {
                "model": model,
                "input": batch,
                "input_type": input_type,
            }
            try:
                resp = await client.post(VOYAGE_URL, headers=headers, json=payload)
            except httpx.HTTPError as e:
                raise EmbeddingError(f"Network error: {e}") from e
            if resp.status_code != 200:
                raise EmbeddingError(
                    f"Voyage error {resp.status_code}: {resp.text[:400]}"
                )
            data = resp.json()
            for item in data.get("data", []):
                vec = item.get("embedding")
                if not vec:
                    raise EmbeddingError("Voyage returned empty embedding.")
                results.append(list(vec))

    return model, results
