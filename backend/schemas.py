"""
Pydantic request/response schemas.
"""

from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: str
    version: str
    schema_version: int
    auth_enabled: bool
    ingest_auth_enabled: bool
