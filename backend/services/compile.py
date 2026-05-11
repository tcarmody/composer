"""
Compile a collection's members into a draft body.

Takes an ordered outline and emits a single markdown document suitable
for further editing. Items quote their title/author/summary (or full
content if requested); notes and drafts are inlined as-is.
"""

from urllib.parse import urlparse

from ..repositories.collections import OutlineNode
from ..repositories.items import ItemRepository


def _outlet_name(url: str | None) -> str | None:
    """Derive a publisher label from the URL host."""
    if not url:
        return None
    host = (urlparse(url).hostname or "").lower()
    if not host:
        return None
    for prefix in ("www.", "m.", "amp."):
        if host.startswith(prefix):
            host = host[len(prefix):]
            break
    return host or None


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

    item = items_repo.get(node.member_id)
    url = item.url if item else None
    outlet = _outlet_name(url)
    if outlet and url:
        lines.append("")
        lines.append(f"*[{outlet}]({url})*")
    elif outlet:
        lines.append("")
        lines.append(f"*{outlet}*")
    elif url:
        lines.append("")
        lines.append(f"[Source]({url})")

    if include_full_content and item:
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
    elif not include_full_content and node.item_summary:
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
