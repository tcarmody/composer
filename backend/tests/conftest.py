"""
Fixtures: an app wired to a fresh SQLite file per test, and a fake LLM provider.

Pre-populating `state` makes the app's lifespan skip its own database setup,
so tests never touch data/composer.db.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from dpcommon.llm import LLMResponse, StreamEnd
from fastapi.testclient import TestClient

from backend.config import config, state
from backend.database import Database
from backend.repositories import (
    ChunksRepository,
    CollectionsRepository,
    DraftsRepository,
    ItemRepository,
    NotesRepository,
)
from backend.services import llm


@pytest.fixture
def db(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "DB_PATH", tmp_path / "composer.db")
    monkeypatch.setattr(config, "SYNC_TARGET_URL", "")
    database = Database(tmp_path / "composer.db", track_sync=False)
    monkeypatch.setattr(state, "db", database)
    monkeypatch.setattr(state, "items", ItemRepository(database))
    monkeypatch.setattr(state, "notes", NotesRepository(database))
    monkeypatch.setattr(state, "collections", CollectionsRepository(database))
    monkeypatch.setattr(state, "drafts", DraftsRepository(database))
    monkeypatch.setattr(state, "chunks", ChunksRepository(database))
    return database


@pytest.fixture
def client(db, monkeypatch):
    monkeypatch.setattr(config, "INGEST_API_KEY", "")
    indexed = []

    async def fake_index(item):
        indexed.append(item.id)
        return 0

    # Indexing embeds text through Voyage; ingest tests only need the item
    monkeypatch.setattr("backend.routes.ingest.index_item", fake_index)
    from backend.server import app

    with TestClient(app) as test_client:
        test_client.indexed = indexed
        yield test_client


class FakeProvider:
    """
    Stands in for dpcommon's AnthropicProvider: records every call and replays
    queued responses. `messages` are SDK-like objects (stop_reason, content).
    """

    def __init__(self):
        self.calls: list[dict] = []
        self.texts: list[str] = []
        self.messages: list = []
        self.stream_items: list = ["Hello", " world", StreamEnd(stop_reason="end_turn")]
        self.error: BaseException | None = None

    def _record(self, kind, kwargs):
        self.calls.append({"kind": kind, **kwargs})
        if self.error is not None:
            raise self.error

    async def complete_async(self, user_prompt, **kwargs):
        self._record("complete", {"user_prompt": user_prompt, **kwargs})
        return LLMResponse(text=self.texts.pop(0), model=kwargs.get("model") or "fake")

    async def create_message_async(self, **kwargs):
        self._record("message", kwargs)
        return self.messages.pop(0)

    async def stream_chat_async(self, messages, **kwargs):
        self._record("stream", {"messages": messages, **kwargs})
        for item in self.stream_items:
            yield item


def message(*texts, stop_reason="end_turn"):
    return SimpleNamespace(
        stop_reason=stop_reason,
        content=[SimpleNamespace(type="text", text=t) for t in texts],
    )


@pytest.fixture
def fake_llm(monkeypatch):
    provider = FakeProvider()
    monkeypatch.setattr(llm, "get_provider", lambda: provider)
    return provider


@pytest.fixture
def no_llm_key(monkeypatch):
    monkeypatch.setattr(llm, "get_provider", lambda: None)
