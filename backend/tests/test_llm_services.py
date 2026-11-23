"""
Composer's Claude-backed services on the shared dpcommon provider.

Most tests use FakeProvider (conftest) to check prompts, models and error
handling. The wire tests at the bottom run the real provider and SDK against a
mock transport, so a request Composer sends in the wrong shape fails here.
"""

import json

import anthropic
import httpx2
import pytest
from dpcommon.llm import AnthropicProvider, RefusalError, StreamEnd

from backend.config import config
from backend.services import assist, chat, factcheck, llm, summarizer
from backend.tests.conftest import message

# ---------------------------------------------------------------------------
# llm helper
# ---------------------------------------------------------------------------


def test_models_are_5_5_tiers():
    assert llm.FAST_MODEL == "claude-haiku-5-5"
    assert llm.STANDARD_MODEL == "claude-sonnet-5-5"


def test_chat_model_honors_llm_model(monkeypatch):
    monkeypatch.setattr(config, "LLM_MODEL", "")
    assert llm.chat_model() == "claude-sonnet-5-5"
    monkeypatch.setattr(config, "LLM_MODEL", "claude-opus-5-5")
    assert llm.chat_model() == "claude-opus-5-5"


def test_get_provider_none_without_key(monkeypatch):
    monkeypatch.setattr(llm.secret_store, "get", lambda name: "")
    assert llm.get_provider() is None


def test_get_provider_cached_per_key_with_workspace(monkeypatch):
    keys = iter(["key-a", "key-a", "key-b"])
    monkeypatch.setattr(llm.secret_store, "get", lambda name: next(keys))
    monkeypatch.setattr(config, "ANTHROPIC_WORKSPACE_ID", "wrkspc_c")
    llm._provider_for.cache_clear()
    a1, a2, b = llm.get_provider(), llm.get_provider(), llm.get_provider()
    assert a1 is a2 and a1 is not b
    assert a1.async_client.default_headers["anthropic-workspace-id"] == "wrkspc_c"


def test_describe_error_messages():
    request = httpx2.Request("POST", "https://api.anthropic.com/v1/messages")
    status = anthropic.APIStatusError(
        "overloaded", response=httpx2.Response(529, request=request), body=None
    )
    assert llm.describe_error(status).startswith("Anthropic API error 529")
    assert llm.describe_error(anthropic.APIConnectionError(request=request)).startswith("Network error")
    assert "cyber" in llm.describe_error(RefusalError("cyber"))


# ---------------------------------------------------------------------------
# assist
# ---------------------------------------------------------------------------


async def test_assist_rewrites_selection(fake_llm, monkeypatch):
    monkeypatch.setattr(config, "LLM_MODEL", "")
    fake_llm.texts = ["  Tighter.  "]
    out = await assist.run_assist(
        action="tighten", draft_body="Full draft. Long sentence.", selection="Long sentence.", instructions=None
    )
    assert out == "Tighter."
    call = fake_llm.calls[0]
    assert call["model"] == "claude-sonnet-5-5"
    assert "Selection to revise:\n\nLong sentence." in call["user_prompt"]
    assert call["max_tokens"] == assist.MAX_TOKENS


async def test_assist_without_key(no_llm_key):
    with pytest.raises(assist.AssistError, match="not configured"):
        await assist.run_assist(action="rewrite", draft_body="x", selection=None, instructions=None)


async def test_assist_maps_refusal(fake_llm):
    fake_llm.error = RefusalError("general_harms")
    with pytest.raises(assist.AssistError, match="declined.*general_harms"):
        await assist.run_assist(action="rewrite", draft_body="x", selection=None, instructions=None)


async def test_assist_empty_answer(fake_llm):
    fake_llm.texts = ["   "]
    with pytest.raises(assist.AssistError, match="empty"):
        await assist.run_assist(action="rewrite", draft_body="x", selection=None, instructions=None)


# ---------------------------------------------------------------------------
# chat
# ---------------------------------------------------------------------------


def _events(chunks: list[bytes]) -> list[tuple[str, dict]]:
    out = []
    for chunk in chunks:
        event, data = chunk.decode().strip().split("\n")
        out.append((event.removeprefix("event: "), json.loads(data.removeprefix("data: "))))
    return out


async def _run_chat(monkeypatch, **kwargs):
    async def no_hits(**_):
        return [], False

    monkeypatch.setattr(chat, "hybrid_search", no_hits)
    return _events([
        c async for c in chat.stream_chat(
            query="What did I save about WAL?", source_types=None, limit=5,
            chunks_repo=None, items_repo=None, notes_repo=None, drafts_repo=None, **kwargs,
        )
    ])


async def test_chat_streams_citations_deltas_done(fake_llm, monkeypatch):
    events = await _run_chat(monkeypatch)
    assert [e for e, _ in events] == ["citations", "delta", "delta", "done"]
    assert "".join(d["text"] for e, d in events if e == "delta") == "Hello world"
    assert events[-1][1] == {"stop_reason": "end_turn"}
    call = fake_llm.calls[0]
    assert call["system_prompt"] == chat.SYSTEM_PROMPT
    assert "No sources were retrieved" in call["messages"][-1]["content"]


async def test_chat_passes_history(fake_llm, monkeypatch):
    from backend.schemas import ChatMessage

    history = [ChatMessage(role="user", content="hi"), ChatMessage(role="assistant", content="hello")]
    await _run_chat(monkeypatch, history=history)
    roles = [m["role"] for m in fake_llm.calls[0]["messages"]]
    assert roles == ["user", "assistant", "user"]


async def test_chat_refusal_becomes_error(fake_llm, monkeypatch):
    fake_llm.stream_items = ["Part", StreamEnd(stop_reason="refusal", refusal_category="cyber")]
    events = await _run_chat(monkeypatch)
    assert [e for e, _ in events] == ["citations", "delta", "error"]
    assert "cyber" in events[-1][1]["message"]


async def test_chat_without_key(no_llm_key, monkeypatch):
    assert [e for e, _ in await _run_chat(monkeypatch)] == ["error"]


# ---------------------------------------------------------------------------
# factcheck
# ---------------------------------------------------------------------------

PASSAGE = "SQLite added WAL mode in 2010. It made mixed workloads four times faster."


async def _factcheck():
    return [e async for e in factcheck.factcheck_events(draft_body=PASSAGE, selection=None)]


async def test_factcheck_extracts_then_verifies(fake_llm):
    fake_llm.messages = [
        message('{"claims": [{"claim": "SQLite added WAL mode in 2010", "kind": "date"}]}'),
        message(
            "Searching for the release notes.",
            '{"verdict": "supported", "explanation": "3.7.0, July 2010.", '
            '"sources": [{"title": "SQLite WAL", "url": "https://sqlite.org/wal.html"}]}',
        ),
    ]
    events = await _factcheck()
    kinds = [type(e).__name__ for e in events]
    assert kinds == ["ExtractedEvent", "VerdictEvent", "DoneEvent"]
    claim = events[0].claims[0]
    assert PASSAGE[claim.offset:claim.offset + claim.length] == "SQLite added WAL mode in 2010"
    assert events[1].verdict == "supported"
    assert events[1].sources[0].url == "https://sqlite.org/wal.html"
    assert events[2].model_used == "claude-sonnet-5-5"

    extract, verify = fake_llm.calls
    assert extract["model"] == "claude-haiku-5-5"
    assert "tools" not in extract
    assert verify["model"] == "claude-sonnet-5-5"
    assert verify["tools"][0]["type"] == "web_search_20260209"
    assert verify["tools"][0]["max_uses"] == factcheck.VERIFY_MAX_SEARCHES


async def test_factcheck_resumes_a_paused_turn(fake_llm):
    paused = message("Still searching", stop_reason="pause_turn")
    fake_llm.messages = [
        message('{"claims": [{"claim": "SQLite added WAL mode in 2010"}]}'),
        paused,
        message('{"verdict": "unverified", "explanation": "No source found."}'),
    ]
    events = await _factcheck()
    assert events[1].verdict == "unverified"
    resumed = fake_llm.calls[2]["messages"]
    assert resumed[-1] == {"role": "assistant", "content": paused.content}


async def test_factcheck_extraction_error(fake_llm):
    fake_llm.error = RefusalError("cyber")
    events = await _factcheck()
    assert [type(e).__name__ for e in events] == ["ErrorEvent"]
    assert "declined" in events[0].message


async def test_factcheck_without_key(no_llm_key):
    assert [type(e).__name__ for e in await _factcheck()] == ["ErrorEvent"]


# ---------------------------------------------------------------------------
# summarizer
# ---------------------------------------------------------------------------

SUMMARY_JSON = json.dumps({
    "headline": "SQLite WAL mode lets readers run during writes",
    "summary": "One paragraph.",
    "key_points": ["a", "b", "c"],
    "content_type": "analysis",
})


async def test_summarizer_short_article_uses_fast_model(fake_llm):
    fake_llm.texts = [SUMMARY_JSON]
    result = await summarizer.summarize_article(content="word " * 300, title="T", url="https://x.test")
    assert result.model_used == "claude-haiku-5-5"
    assert result.key_points == ["a", "b", "c"]
    call = fake_llm.calls[0]
    assert call["model"] == "claude-haiku-5-5"
    assert [b["cache_control"] for b in call["system"]] == [{"type": "ephemeral"}] * 2
    assert call["user_prompt"].startswith("Original title: T\nURL: https://x.test\nArticle:")


async def test_summarizer_long_article_uses_standard_model(fake_llm):
    fake_llm.texts = [SUMMARY_JSON]
    result = await summarizer.summarize_article(content="word " * 2500)
    assert result.model_used == "claude-sonnet-5-5"


async def test_summarizer_api_error(fake_llm):
    request = httpx2.Request("POST", "https://api.anthropic.com/v1/messages")
    fake_llm.error = anthropic.APIConnectionError(request=request)
    with pytest.raises(summarizer.SummarizeError, match="Network error"):
        await summarizer.summarize_article(content="word " * 300)


# ---------------------------------------------------------------------------
# Wire format: the real shared provider and SDK, mock transport
# ---------------------------------------------------------------------------


def _wired_provider(monkeypatch, responses):
    sent = []

    def handler(request):
        sent.append(json.loads(request.content))
        return httpx2.Response(200, json=responses.pop(0))

    provider = AnthropicProvider(api_key="sk-test", workspace_id="")
    provider.async_client = provider.async_client.copy(
        http_client=anthropic.DefaultAsyncHttpxClient(transport=httpx2.MockTransport(handler))
    )
    monkeypatch.setattr(llm, "get_provider", lambda: provider)
    return sent


def _api_message(text, model):
    return {
        "id": "msg_t", "type": "message", "role": "assistant", "model": model,
        "content": [{"type": "text", "text": text}], "stop_reason": "end_turn",
        "stop_sequence": None, "usage": {"input_tokens": 1, "output_tokens": 1},
    }


async def test_factcheck_requests_on_the_wire(monkeypatch):
    sent = _wired_provider(monkeypatch, [
        _api_message('{"claims": [{"claim": "SQLite added WAL mode in 2010"}]}', "claude-haiku-5-5"),
        _api_message('{"verdict": "supported", "explanation": "ok"}', "claude-sonnet-5-5"),
    ])
    monkeypatch.setattr(config, "LLM_MODEL", "")
    events = await _factcheck()
    assert events[1].verdict == "supported"

    extract, verify = sent
    assert extract["model"] == "claude-haiku-5-5"
    assert extract["thinking"] == {"type": "disabled"}
    assert "fallbacks" not in extract
    assert verify["model"] == "claude-sonnet-5-5"
    assert verify["thinking"] == {"type": "between_tools"}
    assert verify["fallbacks"] == "default"
    assert verify["tools"][0]["type"] == "web_search_20260209"
    assert not {"temperature", "top_p", "top_k"} & (extract.keys() | verify.keys())


async def test_summarizer_request_on_the_wire(monkeypatch):
    sent = _wired_provider(monkeypatch, [_api_message(SUMMARY_JSON, "claude-haiku-5-5")])
    await summarizer.summarize_article(content="word " * 300)
    (body,) = sent
    assert body["model"] == "claude-haiku-5-5"
    assert len(body["system"]) == 2
    assert all(b["cache_control"] == {"type": "ephemeral"} for b in body["system"])


def test_factcheck_final_text_joins_cited_blocks_after_last_tool():
    from types import SimpleNamespace as B

    content = [
        B(type="text", text="Searching first."),
        B(type="server_tool_use"),
        B(type="web_search_tool_result"),
        B(type="text", text='{"verdict": "supported", '),
        B(type="text", text='"explanation": "cited"}'),
    ]
    assert factcheck._final_text(content) == '{"verdict": "supported", "explanation": "cited"}'
