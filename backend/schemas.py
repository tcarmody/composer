"""
Pydantic request/response schemas.
"""

from typing import Any, Literal

from pydantic import BaseModel, Field

from .repositories.collections import Collection, OutlineNode
from .repositories.drafts import Draft
from .repositories.items import Item
from .repositories.notes import Note


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


# ─── notes ──────────────────────────────────────────────

class NoteCreateRequest(BaseModel):
    title: str | None = None
    body: str = ""


class NotePatchRequest(BaseModel):
    title: str | None = None
    body: str | None = None


class NoteResponse(BaseModel):
    id: str
    title: str | None
    body: str
    created_at: str
    updated_at: str

    @classmethod
    def from_note(cls, note: Note) -> "NoteResponse":
        return cls(
            id=note.id,
            title=note.title,
            body=note.body,
            created_at=note.created_at,
            updated_at=note.updated_at,
        )


class NoteListResponse(BaseModel):
    notes: list[NoteResponse]
    total: int


# ─── drafts ─────────────────────────────────────────────

DraftStatus = Literal["wip", "final"]


class DraftCreateRequest(BaseModel):
    title: str | None = None
    body: str = ""
    status: DraftStatus = "wip"


class DraftPatchRequest(BaseModel):
    title: str | None = None
    body: str | None = None
    status: DraftStatus | None = None


class DraftResponse(BaseModel):
    id: str
    title: str | None
    body: str
    status: DraftStatus
    created_at: str
    updated_at: str

    @classmethod
    def from_draft(cls, draft: Draft) -> "DraftResponse":
        return cls(
            id=draft.id,
            title=draft.title,
            body=draft.body,
            status=draft.status,
            created_at=draft.created_at,
            updated_at=draft.updated_at,
        )


class DraftListResponse(BaseModel):
    drafts: list[DraftResponse]
    total: int


AssistAction = Literal["rewrite", "expand", "summarize", "tighten"]


class DraftAssistRequest(BaseModel):
    action: AssistAction
    selection: str | None = None
    instructions: str | None = None


class DraftAssistResponse(BaseModel):
    suggestion: str


# ─── collections ────────────────────────────────────────

MemberType = Literal["item", "note", "draft"]


class CollectionCreateRequest(BaseModel):
    name: str
    description: str | None = None


class CollectionPatchRequest(BaseModel):
    name: str | None = None
    description: str | None = None


class CollectionResponse(BaseModel):
    id: str
    name: str
    description: str | None
    created_at: str
    member_count: int

    @classmethod
    def from_collection(cls, c: Collection) -> "CollectionResponse":
        return cls(
            id=c.id,
            name=c.name,
            description=c.description,
            created_at=c.created_at,
            member_count=c.member_count,
        )


class AddMemberRequest(BaseModel):
    member_type: MemberType
    member_id: str


class ReorderRequest(BaseModel):
    members: list[tuple[MemberType, str]] = Field(
        ..., description="Ordered list of (member_type, member_id)"
    )


class CreateInlineNoteRequest(BaseModel):
    """Create a note and append it to a collection in one call."""

    title: str | None = None
    body: str = ""


class CompileCollectionRequest(BaseModel):
    """Compile a collection's members into a new draft."""

    title: str | None = None
    include_full_content: bool = False


class OutlineItemPayload(BaseModel):
    id: str
    title: str | None
    author: str | None
    summary: str | None
    published_at: str | None
    archived: bool


class OutlineNotePayload(BaseModel):
    id: str
    title: str | None
    body: str
    updated_at: str | None


class OutlineDraftPayload(BaseModel):
    id: str
    title: str | None
    body: str
    status: DraftStatus
    updated_at: str | None


class OutlineNodeResponse(BaseModel):
    member_type: MemberType
    member_id: str
    position: int
    item: OutlineItemPayload | None = None
    note: OutlineNotePayload | None = None
    draft: OutlineDraftPayload | None = None

    @classmethod
    def from_node(cls, n: OutlineNode) -> "OutlineNodeResponse":
        item_payload: OutlineItemPayload | None = None
        note_payload: OutlineNotePayload | None = None
        draft_payload: OutlineDraftPayload | None = None
        if n.member_type == "item":
            item_payload = OutlineItemPayload(
                id=n.member_id,
                title=n.item_title,
                author=n.item_author,
                summary=n.item_summary,
                published_at=n.item_published_at,
                archived=n.item_archived,
            )
        elif n.member_type == "note":
            note_payload = OutlineNotePayload(
                id=n.member_id,
                title=n.note_title,
                body=n.note_body or "",
                updated_at=n.note_updated_at,
            )
        elif n.member_type == "draft":
            draft_payload = OutlineDraftPayload(
                id=n.member_id,
                title=n.draft_title,
                body=n.draft_body or "",
                status=n.draft_status or "wip",  # type: ignore[arg-type]
                updated_at=n.draft_updated_at,
            )
        return cls(
            member_type=n.member_type,
            member_id=n.member_id,
            position=n.position,
            item=item_payload,
            note=note_payload,
            draft=draft_payload,
        )


class OutlineResponse(BaseModel):
    collection: CollectionResponse
    members: list[OutlineNodeResponse]
