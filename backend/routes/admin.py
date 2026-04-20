"""Admin routes. X-API-Key guarded."""

from fastapi import APIRouter, Depends

from ..auth import verify_api_key
from ..services.indexer import reindex_all

router = APIRouter(
    prefix="/v1/admin",
    tags=["admin"],
    dependencies=[Depends(verify_api_key)],
)


@router.post("/reindex")
async def reindex() -> dict[str, int]:
    return await reindex_all()
