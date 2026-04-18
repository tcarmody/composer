"""Health check route — public, no auth required."""

from fastapi import APIRouter

from ..config import config, state
from ..schemas import HealthResponse

router = APIRouter(tags=["health"])


@router.get("/v1/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    return HealthResponse(
        status="ok",
        version="0.1.0",
        schema_version=state.db.version() if state.db else 0,
        auth_enabled=bool(config.AUTH_API_KEY),
        ingest_auth_enabled=bool(config.INGEST_API_KEY),
    )
