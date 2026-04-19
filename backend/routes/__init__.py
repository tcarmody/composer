"""API route modules."""

from .collections import router as collections_router
from .health import router as health_router
from .ingest import router as ingest_router
from .items import router as items_router
from .notes import router as notes_router

__all__ = [
    "collections_router",
    "health_router",
    "ingest_router",
    "items_router",
    "notes_router",
]
