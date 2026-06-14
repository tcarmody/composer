"""
DataPoints client — asks the DataPoints backend to re-promote an article
so its latest content flows back through the ingest pipeline.

The refresh roundtrip:
  Composer  -- POST /articles/promote-by-ref -->  DataPoints
  DataPoints -- POST /v1/ingest/items        -->  Composer (the one DataPoints
                                                  is wired to via COMPOSER_URL)
  Composer  -- UPSERT by (source, source_ref) -->  items table

Topology note: an item may be owned by either the local DataPoints (:5005)
or the cloud DataPoints, depending on where it was promoted. Items promoted
from the cloud web UI and pulled down to this instance don't exist in the
local DataPoints DB, so refresh tries the primary (local) DataPoints first
and falls back to the cloud one (DATAPOINTS_FALLBACK_URL). A fallback
re-promote lands in the *cloud* Composer; since ingest preserves
promoted_at, the normal item pull (keyed on promoted_at) won't carry the
update down, so we fetch the refreshed snapshot from the cloud Composer
(SYNC_TARGET_URL) and apply it locally.
"""

import logging

import httpx

from ..config import config, state

logger = logging.getLogger(__name__)


class DataPointsError(Exception):
    """Raised when DataPoints can't service a refresh request."""


class _ArticleNotHere(Exception):
    """Internal: a given DataPoints instance doesn't have this article."""


def _promote_request(base: str, source_ref: str) -> tuple[str, dict | None]:
    """(url, params) to re-promote source_ref against DataPoints at `base`.

    A numeric source_ref is a legacy DataPoints id and matches the
    /articles/{id}/promote route directly; a URL ref can't (not an int,
    contains slashes), so it routes through promote-by-ref."""
    base = base.rstrip("/")
    if source_ref.isdigit():
        return f"{base}/articles/{source_ref}/promote", None
    return f"{base}/articles/promote-by-ref", {"ref": source_ref}


async def _promote_against(
    base: str, api_key: str, source_ref: str
) -> None:
    """Re-promote one article against a single DataPoints instance.
    Raises _ArticleNotHere on 404, DataPointsError on transport/other HTTP."""
    url, params = _promote_request(base, source_ref)
    headers = {"X-API-Key": api_key} if api_key else {}
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(url, headers=headers, params=params)
    except httpx.HTTPError as e:
        raise DataPointsError(f"DataPoints unreachable: {e}") from e

    if resp.status_code == 404:
        raise _ArticleNotHere()
    if resp.status_code >= 400:
        raise DataPointsError(
            f"DataPoints promote failed ({resp.status_code}): {resp.text[:200]}"
        )


async def _pull_item_from_cloud(item_id: str) -> bool:
    """Fetch one item snapshot from the cloud Composer and apply it locally.
    Used after a fallback refresh, whose result landed in the cloud and
    won't arrive via the promoted_at-keyed pull. Returns True if applied."""
    if not config.SYNC_TARGET_URL or state.db is None:
        return False
    from .sync import apply_entry  # local import avoids an import cycle

    url = config.SYNC_TARGET_URL.rstrip("/") + f"/v1/sync/items/{item_id}"
    headers = {"X-Ingest-Key": config.SYNC_API_KEY} if config.SYNC_API_KEY else {}
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(url, headers=headers)
        resp.raise_for_status()
    except httpx.HTTPError as e:
        logger.warning("Post-refresh pull of %s failed: %s", item_id, e)
        return False
    snapshot = resp.json().get("item")
    if not snapshot:
        return False
    apply_entry(state.db, "item", item_id, "upsert", snapshot)
    return True


async def refresh_from_datapoints(source_ref: str, item_id: str) -> None:
    """
    Trigger DataPoints to re-promote article `source_ref` into Composer.

    Tries the primary (local) DataPoints, then the configured fallback
    (cloud). For a primary hit the local DB is updated synchronously by the
    re-promote's ingest callback; for a fallback hit we pull the refreshed
    snapshot back from the cloud Composer. Raises DataPointsError if no
    configured instance has the article or all are unreachable.
    """
    targets: list[tuple[str, str, bool]] = [
        (config.DATAPOINTS_URL, config.DATAPOINTS_API_KEY, True),
    ]
    if config.DATAPOINTS_FALLBACK_URL:
        targets.append(
            (config.DATAPOINTS_FALLBACK_URL, config.DATAPOINTS_FALLBACK_API_KEY, False)
        )

    unreachable: list[str] = []
    for base, api_key, is_primary in targets:
        try:
            await _promote_against(base, api_key, source_ref)
        except _ArticleNotHere:
            continue
        except DataPointsError as e:
            # unreachable / server error — remember it but try the next target
            unreachable.append(str(e))
            continue
        # success
        if not is_primary:
            await _pull_item_from_cloud(item_id)
        return

    if unreachable:
        raise DataPointsError("; ".join(dict.fromkeys(unreachable)))
    raise DataPointsError(
        "No connected DataPoints has this article. It was likely promoted "
        "on a different instance; connect to that DataPoints to refresh."
    )
