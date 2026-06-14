"""
Configuration and application state management.
"""

import os
from pathlib import Path
from typing import TYPE_CHECKING

from dotenv import load_dotenv
from fastapi import HTTPException

if TYPE_CHECKING:
    from .database import Database
    from .repositories import (
        ChunksRepository,
        CollectionsRepository,
        DraftsRepository,
        ItemRepository,
        NotesRepository,
    )


_backend_dir = Path(__file__).parent
_project_root = _backend_dir.parent
load_dotenv(_project_root / ".env")


def _parse_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.lower() in ("true", "1", "yes", "on")


class Config:
    """Application configuration from environment."""

    AUTH_API_KEY: str = os.getenv("AUTH_API_KEY", "")
    INGEST_API_KEY: str = os.getenv("COMPOSER_INGEST_KEY", "")

    ANTHROPIC_API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    VOYAGE_API_KEY: str = os.getenv("VOYAGE_API_KEY", "")

    LLM_PROVIDER: str = os.getenv("LLM_PROVIDER", "")
    LLM_MODEL: str = os.getenv("LLM_MODEL", "")
    EMBEDDING_MODEL: str = os.getenv("EMBEDDING_MODEL", "")

    DB_PATH: Path = Path(os.getenv("DB_PATH", "./data/composer.db"))
    PORT: int = int(os.getenv("PORT", "5006"))
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")

    DATAPOINTS_URL: str = os.getenv("DATAPOINTS_URL", "http://127.0.0.1:5005")
    DATAPOINTS_API_KEY: str = os.getenv("DATAPOINTS_API_KEY", "")

    # Fallback DataPoints for item refresh: items promoted from the cloud
    # web UI and pulled down here don't exist in the local DataPoints DB,
    # so refresh falls back to this instance (typically the cloud macreader).
    DATAPOINTS_FALLBACK_URL: str = os.getenv("DATAPOINTS_FALLBACK_URL", "")
    DATAPOINTS_FALLBACK_API_KEY: str = os.getenv("DATAPOINTS_FALLBACK_API_KEY", "")

    # Local→cloud sync relay. Set SYNC_TARGET_URL on the LOCAL instance to
    # the Railway base URL to enable the outbox worker; leave unset on the
    # cloud instance. SYNC_API_KEY is sent as X-Ingest-Key and must equal
    # the target's COMPOSER_INGEST_KEY.
    SYNC_TARGET_URL: str = os.getenv("SYNC_TARGET_URL", "")
    SYNC_API_KEY: str = os.getenv("SYNC_API_KEY", "")
    SYNC_INTERVAL: float = float(os.getenv("SYNC_INTERVAL", "5"))
    # How often to pull cloud-ingested items down (web promotions land on
    # the cloud instance and flow back through GET /v1/sync/items).
    SYNC_PULL_INTERVAL: float = float(os.getenv("SYNC_PULL_INTERVAL", "30"))

    CORS_ORIGINS: list[str] = [
        o.strip() for o in os.getenv(
            "CORS_ORIGINS",
            "http://localhost:3001,http://127.0.0.1:3001"
        ).split(",") if o.strip()
    ]


config = Config()


class AppState:
    """Shared application state."""
    db: "Database | None" = None
    items: "ItemRepository | None" = None
    notes: "NotesRepository | None" = None
    collections: "CollectionsRepository | None" = None
    drafts: "DraftsRepository | None" = None
    chunks: "ChunksRepository | None" = None


state = AppState()


def get_db() -> "Database":
    if not state.db:
        raise HTTPException(status_code=500, detail="Database not initialized")
    return state.db


def get_items_repo() -> "ItemRepository":
    if not state.items:
        raise HTTPException(status_code=500, detail="Items repository not initialized")
    return state.items


def get_notes_repo() -> "NotesRepository":
    if not state.notes:
        raise HTTPException(status_code=500, detail="Notes repository not initialized")
    return state.notes


def get_collections_repo() -> "CollectionsRepository":
    if not state.collections:
        raise HTTPException(status_code=500, detail="Collections repository not initialized")
    return state.collections


def get_drafts_repo() -> "DraftsRepository":
    if not state.drafts:
        raise HTTPException(status_code=500, detail="Drafts repository not initialized")
    return state.drafts


def get_chunks_repo() -> "ChunksRepository":
    if not state.chunks:
        raise HTTPException(status_code=500, detail="Chunks repository not initialized")
    return state.chunks
