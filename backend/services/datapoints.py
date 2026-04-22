"""
DataPoints client — asks the DataPoints backend to re-promote an article
so its latest content flows back through the ingest pipeline.

The refresh roundtrip:
  Composer  -- POST /articles/{source_ref}/promote -->  DataPoints
  DataPoints -- POST /v1/ingest/items             -->  Composer
  Composer  -- UPSERT by (source, source_ref)     -->  items table
"""

import httpx

from ..config import config


class DataPointsError(Exception):
    """Raised when DataPoints can't service a refresh request."""


async def refresh_from_datapoints(source_ref: str) -> None:
    """
    Trigger DataPoints to re-promote article `source_ref` into Composer.

    Returns when DataPoints has acknowledged; by that point DataPoints has
    already called back into our /v1/ingest/items endpoint, so the caller
    can re-read the item from the DB and see refreshed fields.
    """
    url = f"{config.DATAPOINTS_URL.rstrip('/')}/articles/{source_ref}/promote"
    headers: dict[str, str] = {}
    if config.DATAPOINTS_API_KEY:
        headers["X-API-Key"] = config.DATAPOINTS_API_KEY

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(url, headers=headers)
    except httpx.HTTPError as e:
        raise DataPointsError(f"DataPoints unreachable: {e}") from e

    if resp.status_code == 404:
        raise DataPointsError(
            f"DataPoints has no article with id {source_ref}"
        )
    if resp.status_code >= 400:
        raise DataPointsError(
            f"DataPoints promote failed ({resp.status_code}): {resp.text[:200]}"
        )
