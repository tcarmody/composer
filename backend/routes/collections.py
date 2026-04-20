"""Collections routes. X-API-Key guarded."""

from fastapi import APIRouter, Depends, HTTPException

from ..auth import verify_api_key
from ..config import (
    get_collections_repo,
    get_drafts_repo,
    get_items_repo,
    get_notes_repo,
)
from ..repositories import (
    CollectionsRepository,
    DraftsRepository,
    ItemRepository,
    NotesRepository,
)
from ..schemas import (
    AddMemberRequest,
    CollectionCreateRequest,
    CollectionPatchRequest,
    CollectionResponse,
    CompileCollectionRequest,
    CreateInlineNoteRequest,
    DraftResponse,
    OutlineNodeResponse,
    OutlineResponse,
    ReorderRequest,
)
from ..services.compile import compile_outline_to_markdown

router = APIRouter(
    prefix="/collections",
    tags=["collections"],
    dependencies=[Depends(verify_api_key)],
)


@router.get("", response_model=list[CollectionResponse])
async def list_collections(
    collections: CollectionsRepository = Depends(get_collections_repo),
) -> list[CollectionResponse]:
    return [CollectionResponse.from_collection(c) for c in collections.list()]


@router.post("", response_model=CollectionResponse, status_code=201)
async def create_collection(
    payload: CollectionCreateRequest,
    collections: CollectionsRepository = Depends(get_collections_repo),
) -> CollectionResponse:
    c = collections.create(name=payload.name, description=payload.description)
    return CollectionResponse.from_collection(c)


def _build_outline(
    collections: CollectionsRepository, collection_id: str
) -> OutlineResponse:
    c = collections.get(collection_id)
    if not c:
        raise HTTPException(status_code=404, detail="Collection not found")
    members = collections.list_members(collection_id)
    return OutlineResponse(
        collection=CollectionResponse.from_collection(c),
        members=[OutlineNodeResponse.from_node(m) for m in members],
    )


@router.get("/{collection_id}", response_model=OutlineResponse)
async def get_collection_outline(
    collection_id: str,
    collections: CollectionsRepository = Depends(get_collections_repo),
) -> OutlineResponse:
    return _build_outline(collections, collection_id)


@router.patch("/{collection_id}", response_model=CollectionResponse)
async def patch_collection(
    collection_id: str,
    payload: CollectionPatchRequest,
    collections: CollectionsRepository = Depends(get_collections_repo),
) -> CollectionResponse:
    updated = collections.update(
        collection_id, name=payload.name, description=payload.description
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Collection not found")
    return CollectionResponse.from_collection(updated)


@router.delete("/{collection_id}", status_code=204)
async def delete_collection(
    collection_id: str,
    collections: CollectionsRepository = Depends(get_collections_repo),
) -> None:
    if not collections.delete(collection_id):
        raise HTTPException(status_code=404, detail="Collection not found")


# ─── member ops ─────────────────────────────────────────


@router.post("/{collection_id}/members", response_model=OutlineResponse)
async def add_member(
    collection_id: str,
    payload: AddMemberRequest,
    collections: CollectionsRepository = Depends(get_collections_repo),
    items: ItemRepository = Depends(get_items_repo),
    notes: NotesRepository = Depends(get_notes_repo),
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> OutlineResponse:
    if not collections.get(collection_id):
        raise HTTPException(status_code=404, detail="Collection not found")
    if payload.member_type == "item":
        if not items.get(payload.member_id):
            raise HTTPException(status_code=404, detail="Item not found")
    elif payload.member_type == "note":
        if not notes.get(payload.member_id):
            raise HTTPException(status_code=404, detail="Note not found")
    elif payload.member_type == "draft":
        if not drafts.get(payload.member_id):
            raise HTTPException(status_code=404, detail="Draft not found")
    else:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid member_type '{payload.member_type}'",
        )

    collections.add_member(
        collection_id=collection_id,
        member_type=payload.member_type,
        member_id=payload.member_id,
    )
    return _build_outline(collections, collection_id)


@router.post("/{collection_id}/notes", response_model=OutlineResponse)
async def create_inline_note(
    collection_id: str,
    payload: CreateInlineNoteRequest,
    collections: CollectionsRepository = Depends(get_collections_repo),
    notes: NotesRepository = Depends(get_notes_repo),
) -> OutlineResponse:
    """Create a note and append it to the collection in one call."""
    if not collections.get(collection_id):
        raise HTTPException(status_code=404, detail="Collection not found")
    note = notes.create(title=payload.title, body=payload.body)
    collections.add_member(
        collection_id=collection_id, member_type="note", member_id=note.id
    )
    return _build_outline(collections, collection_id)


@router.delete("/{collection_id}/members/{member_type}/{member_id}", status_code=204)
async def remove_member(
    collection_id: str,
    member_type: str,
    member_id: str,
    collections: CollectionsRepository = Depends(get_collections_repo),
) -> None:
    if member_type not in ("item", "note", "draft"):
        raise HTTPException(status_code=400, detail="Invalid member_type")
    removed = collections.remove_member(
        collection_id=collection_id,
        member_type=member_type,  # type: ignore[arg-type]
        member_id=member_id,
    )
    if not removed:
        raise HTTPException(status_code=404, detail="Member not found")


@router.post("/{collection_id}/reorder", response_model=OutlineResponse)
async def reorder_members(
    collection_id: str,
    payload: ReorderRequest,
    collections: CollectionsRepository = Depends(get_collections_repo),
) -> OutlineResponse:
    if not collections.get(collection_id):
        raise HTTPException(status_code=404, detail="Collection not found")
    collections.reorder(collection_id=collection_id, ordered_members=payload.members)
    return _build_outline(collections, collection_id)


@router.post("/{collection_id}/compile", response_model=DraftResponse, status_code=201)
async def compile_to_draft(
    collection_id: str,
    payload: CompileCollectionRequest,
    collections: CollectionsRepository = Depends(get_collections_repo),
    items: ItemRepository = Depends(get_items_repo),
    drafts: DraftsRepository = Depends(get_drafts_repo),
) -> DraftResponse:
    c = collections.get(collection_id)
    if not c:
        raise HTTPException(status_code=404, detail="Collection not found")

    members = collections.list_members(collection_id)
    body = compile_outline_to_markdown(
        collection_name=c.name,
        collection_description=c.description,
        members=members,
        items_repo=items,
        include_full_content=payload.include_full_content,
    )
    title = payload.title or c.name
    draft = drafts.create(title=title, body=body, status="wip")
    return DraftResponse.from_draft(draft)
