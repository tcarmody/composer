"""
LLM API key management.

`status()` and the `/llm-keys` endpoints never expose key values — only
whether a key is set and whether it came from the file or env.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..auth import verify_api_key
from ..services import secret_store

router = APIRouter(
    prefix="/v1/settings",
    tags=["settings"],
    dependencies=[Depends(verify_api_key)],
)


class LLMKeyStatus(BaseModel):
    set: bool
    source: str | None = Field(None, description="'file', 'env', or null")


class LLMKeysStatusResponse(BaseModel):
    keys: dict[str, LLMKeyStatus]


class LLMKeysUpdateRequest(BaseModel):
    """Body for PUT — provide only the keys you want to change.

    Empty strings are rejected; to clear a key use the DELETE endpoint.
    """

    anthropic: str | None = None
    openai: str | None = None
    voyage: str | None = None


def _status_response() -> LLMKeysStatusResponse:
    raw = secret_store.status()
    return LLMKeysStatusResponse(
        keys={k: LLMKeyStatus(**v) for k, v in raw.items()}  # type: ignore[arg-type]
    )


@router.get("/llm-keys", response_model=LLMKeysStatusResponse)
async def get_llm_keys() -> LLMKeysStatusResponse:
    return _status_response()


@router.put("/llm-keys", response_model=LLMKeysStatusResponse)
async def update_llm_keys(payload: LLMKeysUpdateRequest) -> LLMKeysStatusResponse:
    updates = payload.model_dump(exclude_none=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No keys provided")
    for name, value in updates.items():
        try:
            secret_store.set_value(name, value)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))
    return _status_response()


@router.delete("/llm-keys/{name}", response_model=LLMKeysStatusResponse)
async def clear_llm_key(name: str) -> LLMKeysStatusResponse:
    try:
        secret_store.clear(name)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return _status_response()
