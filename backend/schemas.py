"""
Pydantic request/response schemas.
"""

from typing import Any

from pydantic import BaseModel, Field

from .repositories.items import Item


class HealthResponse(BaseModel):
    status: str
    version: str
    schema_version: int
    auth_enabled: bool
    ingest_auth_enabled: bool


class RelatedLink(BaseModel):
    url: str
    title: str | None = None
    score: float | None = None


class IngestItemRequest(BaseModel):
    """Payload DataPoints sends to promote an article into Composer."""

    source: str = Field(..., description="e.g. 'datapoints', 'manual'")
    source_ref: str | None = Field(None, description="Opaque ID in the source system")
    url: str | None = None
    title: str
    author: str | None = None
    published_at: str | None = None
    content: str | None = None
    summary: str | None = None
    key_points: list[str] = Field(default_factory=list)
    keywords: list[str] = Field(default_factory=list)
    related_links: list[RelatedLink] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)


class IngestItemResponse(BaseModel):
    id: str
    url: str
    already_existed: bool


class IngestBatchResponse(BaseModel):
    items: list[IngestItemResponse]
    created: int
    skipped: int


class ItemResponse(BaseModel):
    id: str
    source: str
    source_ref: str | None
    url: str | None
    title: str
    author: str | None
    published_at: str | None
    promoted_at: str
    content: str | None
    summary: str | None
    key_points: list[str]
    keywords: list[str]
    related_links: list[dict[str, Any]]
    metadata: dict[str, Any]
    archived_at: str | None

    @classmethod
    def from_item(cls, item: Item) -> "ItemResponse":
        return cls(
            id=item.id,
            source=item.source,
            source_ref=item.source_ref,
            url=item.url,
            title=item.title,
            author=item.author,
            published_at=item.published_at,
            promoted_at=item.promoted_at,
            content=item.content,
            summary=item.summary,
            key_points=item.key_points,
            keywords=item.keywords,
            related_links=item.related_links,
            metadata=item.metadata,
            archived_at=item.archived_at,
        )


class ItemSummaryResponse(BaseModel):
    """Trimmed shape for list views — drops full content."""

    id: str
    source: str
    url: str | None
    title: str
    author: str | None
    published_at: str | None
    promoted_at: str
    summary: str | None
    key_points: list[str]
    keywords: list[str]
    archived_at: str | None

    @classmethod
    def from_item(cls, item: Item) -> "ItemSummaryResponse":
        return cls(
            id=item.id,
            source=item.source,
            url=item.url,
            title=item.title,
            author=item.author,
            published_at=item.published_at,
            promoted_at=item.promoted_at,
            summary=item.summary,
            key_points=item.key_points,
            keywords=item.keywords,
            archived_at=item.archived_at,
        )


class ItemListResponse(BaseModel):
    items: list[ItemSummaryResponse]
    total: int
    limit: int
    offset: int


class ItemPatchRequest(BaseModel):
    archived: bool | None = None
