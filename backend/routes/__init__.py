"""API route modules."""

from .admin import router as admin_router
from .collections import router as collections_router
from .drafts import router as drafts_router
from .health import router as health_router
from .ingest import router as ingest_router
from .items import router as items_router
from .notes import router as notes_router
from .search import router as search_router

__all__ = [
    "admin_router",
    "collections_router",
    "drafts_router",
    "health_router",
    "ingest_router",
    "items_router",
    "notes_router",
    "search_router",
]
