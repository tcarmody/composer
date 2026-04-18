"""
Authentication for Composer.

Two separate keys:
- AUTH_API_KEY   guards the internal API consumed by the Composer frontend
- COMPOSER_INGEST_KEY   guards the public /v1/ingest/* endpoints DataPoints calls

If a key is unset, the corresponding surface is open (dev mode). In production,
set both.
"""

import secrets

from fastapi import HTTPException, Security, status
from fastapi.security import APIKeyHeader

from .config import config

API_KEY_HEADER = APIKeyHeader(name="X-API-Key", auto_error=False)
INGEST_KEY_HEADER = APIKeyHeader(name="X-Ingest-Key", auto_error=False)


def verify_api_key(api_key: str | None = Security(API_KEY_HEADER)) -> str:
    configured = config.AUTH_API_KEY
    if not configured:
        return ""
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing API key. Provide X-API-Key header.",
            headers={"WWW-Authenticate": "ApiKey"},
        )
    if not secrets.compare_digest(api_key, configured):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key",
            headers={"WWW-Authenticate": "ApiKey"},
        )
    return api_key


def verify_ingest_key(ingest_key: str | None = Security(INGEST_KEY_HEADER)) -> str:
    configured = config.INGEST_API_KEY
    if not configured:
        return ""
    if not ingest_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing ingest key. Provide X-Ingest-Key header.",
            headers={"WWW-Authenticate": "ApiKey"},
        )
    if not secrets.compare_digest(ingest_key, configured):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid ingest key",
            headers={"WWW-Authenticate": "ApiKey"},
        )
    return ingest_key


def generate_api_key() -> str:
    return secrets.token_urlsafe(32)
