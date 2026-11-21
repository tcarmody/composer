"""
Claude access for Composer's services, through the shared dpcommon provider.

`dpcommon.llm.AnthropicProvider` owns the request shape the current models need
(thinking settings, effort, refusal fallback, no sampling parameters), so the
services here only build prompts and read answers.
"""

from __future__ import annotations

from functools import lru_cache

import anthropic
from dpcommon.llm import AnthropicProvider, ModelTier, RefusalError

from ..config import config
from . import secret_store

FAST_MODEL = AnthropicProvider.TIER_MODELS[ModelTier.FAST]          # claude-haiku-5-5
STANDARD_MODEL = AnthropicProvider.TIER_MODELS[ModelTier.STANDARD]  # claude-sonnet-5-5

KEY_MISSING_MESSAGE = (
    "Anthropic API key is not configured. Set it in Settings → LLM Keys."
)

# What a provider call can raise: API errors (HTTP status, network, timeout)
# and a refusal that survived the server-side fallback.
LLM_ERRORS = (anthropic.APIError, RefusalError)


def get_provider() -> AnthropicProvider | None:
    """The provider for the key set in Settings (or the environment), else None."""
    api_key = secret_store.get("anthropic")
    if not api_key:
        return None
    return _provider_for(api_key, config.ANTHROPIC_WORKSPACE_ID)


@lru_cache(maxsize=4)
def _provider_for(api_key: str, workspace_id: str) -> AnthropicProvider:
    # Cached per key so requests share the SDK clients' connection pools; a
    # key changed in Settings gets a new provider.
    return AnthropicProvider(api_key=api_key, default_model=STANDARD_MODEL, workspace_id=workspace_id)


def chat_model() -> str:
    """Model for chat and assist: LLM_MODEL if set, else the STANDARD tier."""
    return config.LLM_MODEL or STANDARD_MODEL


def describe_error(exc: BaseException) -> str:
    """A message for the UI, in the wording the services used before."""
    if isinstance(exc, RefusalError):
        return f"Claude declined this request (category: {exc.category})."
    if isinstance(exc, anthropic.APIStatusError):
        return f"Anthropic API error {exc.status_code}: {str(exc.message)[:400]}"
    if isinstance(exc, anthropic.APIConnectionError):
        return f"Network error: {exc}"
    return str(exc) or repr(exc)
