"""
Compile a collection's members into a draft body.

Takes an ordered outline and emits a single markdown document suitable
for further editing. Items quote their title/author/summary (or full
content if requested); notes and drafts are inlined as-is.
"""

from ..repositories.collections import OutlineNode
from ..repositories.items import ItemRepository


def compile_outline_to_markdown(
    *,
    collection_name: str,
    collection_description: str | None,
    members: list[OutlineNode],
    items_repo: ItemRepository,
    include_full_content: bool = False,
) -> str:
    parts: list[str] = []
    parts.append(f"# {collection_name}")
    if collection_description:
        parts.append("")
        parts.append(collection_description.strip())

    for node in members:
        section = _render_node(node, items_repo, include_full_content)
        if section:
            parts.append("")
            parts.append("---")
            parts.append("")
            parts.append(section)

    return "\n".join(parts).strip() + "\n"


def _render_node(
    node: OutlineNode,
    items_repo: ItemRepository,
    include_full_content: bool,
) -> str:
    if node.member_type == "item":
        return _render_item(node, items_repo, include_full_content)
    if node.member_type == "note":
        return _render_note(node)
    if node.member_type == "draft":
        return _render_draft(node)
    return ""


def _render_item(
    node: OutlineNode, items_repo: ItemRepository, include_full_content: bool
) -> str:
    title = node.item_title or "(untitled)"
    lines: list[str] = [f"## {title}"]

    meta: list[str] = []
    if node.item_author:
        meta.append(node.item_author)
    if node.item_published_at:
        meta.append(node.item_published_at)
    if meta:
        lines.append("")
        lines.append(f"*{' · '.join(meta)}*")

    if include_full_content:
        item = items_repo.get(node.member_id)
        if item:
            if item.url:
                lines.append("")
                lines.append(f"[Source]({item.url})")
            if item.summary:
                lines.append("")
                lines.append(item.summary.strip())
            if item.key_points:
                lines.append("")
                for kp in item.key_points:
                    lines.append(f"- {kp}")
            if item.content:
                lines.append("")
                lines.append(item.content.strip())
    else:
        item = items_repo.get(node.member_id)
        if item and item.url:
            lines.append("")
            lines.append(f"[Source]({item.url})")
        if node.item_summary:
            lines.append("")
            lines.append(node.item_summary.strip())

    return "\n".join(lines)


def _render_note(node: OutlineNode) -> str:
    lines: list[str] = []
    if node.note_title:
        lines.append(f"## {node.note_title}")
    body = (node.note_body or "").strip()
    if body:
        if lines:
            lines.append("")
        lines.append(body)
    return "\n".join(lines)


def _render_draft(node: OutlineNode) -> str:
    lines: list[str] = []
    if node.draft_title:
        lines.append(f"## {node.draft_title}")
    body = (node.draft_body or "").strip()
    if body:
        if lines:
            lines.append("")
        lines.append(body)
    return "\n".join(lines)
