"""
Composer API Server.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import config, state
from .database import Database
from .repositories import (
    ChunksRepository,
    CollectionsRepository,
    DraftsRepository,
    ItemRepository,
    NotesRepository,
)
from .routes import (
    admin_router,
    chat_router,
    collections_router,
    drafts_router,
    health_router,
    ingest_router,
    items_router,
    notes_router,
    search_router,
)

logging.basicConfig(
    level=getattr(logging, config.LOG_LEVEL, logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    if state.db is None:
        state.db = Database(config.DB_PATH)
        state.items = ItemRepository(state.db)
        state.notes = NotesRepository(state.db)
        state.collections = CollectionsRepository(state.db)
        state.drafts = DraftsRepository(state.db)
        state.chunks = ChunksRepository(state.db)
        logger.info(
            "Database ready at %s (schema v%d)", config.DB_PATH, state.db.version()
        )
    yield


app = FastAPI(
    title="Composer API",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=config.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(ingest_router)
app.include_router(items_router)
app.include_router(notes_router)
app.include_router(drafts_router)
app.include_router(collections_router)
app.include_router(admin_router)
app.include_router(search_router)
app.include_router(chat_router)
