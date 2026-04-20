"""
Paragraph-accumulator chunker.

Splits markdown on blank lines, then packs paragraphs into chunks of
~TARGET_CHARS each (with a small carryover for context). A single
oversized paragraph becomes its own chunk. Empty input returns [].
"""

from dataclasses import dataclass

TARGET_CHARS = 900
SOFT_MIN_CHARS = 400
CARRY_CHARS = 120


@dataclass
class Chunk:
    content: str


def chunk_text(text: str, *, title: str | None = None) -> list[Chunk]:
    source = text.strip()
    if not source:
        return []

    paragraphs = [p.strip() for p in source.split("\n\n") if p.strip()]
    if not paragraphs:
        return []

    chunks: list[str] = []
    buf: list[str] = []
    buf_len = 0
    carry = ""

    def flush() -> None:
        nonlocal buf, buf_len, carry
        if not buf:
            return
        body = "\n\n".join(buf)
        if carry:
            body = f"{carry}\n\n{body}"
        chunks.append(body)
        tail = buf[-1]
        carry = tail[-CARRY_CHARS:] if len(tail) > CARRY_CHARS else tail
        buf = []
        buf_len = 0

    for p in paragraphs:
        if len(p) >= TARGET_CHARS and buf:
            flush()
        buf.append(p)
        buf_len += len(p) + 2
        if buf_len >= TARGET_CHARS:
            flush()
    if buf:
        flush()

    if title:
        prefix = f"[{title}]\n\n"
        chunks = [prefix + c for c in chunks]

    return [Chunk(content=c) for c in chunks]
