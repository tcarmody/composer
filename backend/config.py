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
    from .repositories import ItemRepository


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

    DB_PATH: Path = Path(os.getenv("DB_PATH", "./data/composer.db"))
    PORT: int = int(os.getenv("PORT", "5006"))
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")

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


state = AppState()


def get_db() -> "Database":
    if not state.db:
        raise HTTPException(status_code=500, detail="Database not initialized")
    return state.db


def get_items_repo() -> "ItemRepository":
    if not state.items:
        raise HTTPException(status_code=500, detail="Items repository not initialized")
    return state.items
