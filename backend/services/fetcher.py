"""
Article content fetcher.

One job: take a URL, return readable HTML and basic metadata. Uses trafilatura
(Readability-style) primary, BeautifulSoup heuristics as fallback. Same shape
as DataPoints' fetcher minus the site-specific extractors, archive fallback,
and JS-rendering paths — those can be added back if generic extraction misses.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass

import httpx

from .url_validator import SSRFError, validate_url

try:
    import trafilatura
    from trafilatura.settings import use_config
    _TRAFILATURA_AVAILABLE = True
except ImportError:
    _TRAFILATURA_AVAILABLE = False

try:
    from bs4 import BeautifulSoup
    _BS4_AVAILABLE = True
except ImportError:
    _BS4_AVAILABLE = False


class FetchError(Exception):
    """Fetcher couldn't return usable content."""


@dataclass
class FetchedArticle:
    url: str
    title: str
    content_html: str
    author: str | None
    published_at: str | None
    word_count: int | None
    reading_time_minutes: int | None
    extractor_used: str
    is_paywalled: bool
    site_name: str | None
    content_hash: str


_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)

_HEADERS = {
    "User-Agent": _USER_AGENT,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}

_MIN_CONTENT_LENGTH = 500

_PAYWALL_DOMAINS = (
    "wsj.com", "nytimes.com", "ft.com", "economist.com", "bloomberg.com",
    "washingtonpost.com", "theathletic.com", "businessinsider.com",
    "barrons.com", "telegraph.co.uk", "thetimes.co.uk",
)

_PAYWALL_PHRASES = (
    "subscribe to continue", "subscription required", "sign in to read",
    "become a member", "subscribers only", "paywall",
    "this article is for subscribers", "to read the full article",
    "free articles remaining",
)


async def fetch_article(url: str, *, timeout: float = 30.0) -> FetchedArticle:
    """Fetch an article URL and extract its main content as HTML."""
    if not _TRAFILATURA_AVAILABLE or not _BS4_AVAILABLE:
        raise FetchError(
            "Fetch dependencies missing — install trafilatura and "
            "beautifulsoup4 (`pip install -r requirements.txt`)."
        )
    try:
        validate_url(url)
    except SSRFError as e:
        raise FetchError(str(e)) from e

    try:
        async with httpx.AsyncClient(
            headers=_HEADERS, timeout=timeout, follow_redirects=True
        ) as client:
            resp = await client.get(url)
            resp.raise_for_status()
    except httpx.HTTPError as e:
        raise FetchError(f"HTTP error fetching {url}: {e}") from e

    final_url = str(resp.url)
    html = resp.text

    article = _extract_with_trafilatura(final_url, html) or _extract_with_bs4(
        final_url, html
    )
    if not article or len(article.content_html) < 50:
        raise FetchError(
            "No readable content found — page may be JS-rendered or blocked."
        )

    return article


def _extract_with_trafilatura(url: str, html: str) -> FetchedArticle | None:
    try:
        config = use_config()
        config.set("DEFAULT", "EXTRACTION_TIMEOUT", "30")
        content = trafilatura.extract(
            html,
            url=url,
            output_format="html",
            include_links=True,
            include_images=False,
            include_tables=True,
            favor_recall=True,
            config=config,
        )
        if not content or len(content) < _MIN_CONTENT_LENGTH:
            return None

        metadata = trafilatura.extract_metadata(html, default_url=url)
        soup = BeautifulSoup(html, "html.parser")

        title = (metadata.title if metadata else None) or _title_from_soup(soup)
        author = metadata.author if metadata else None
        published = (metadata.date if metadata else None) or None

        text = BeautifulSoup(content, "html.parser").get_text(" ", strip=True)
        word_count = len(text.split()) if text else None
        reading_time = max(1, round(word_count / 225)) if word_count else None

        site_name = None
        if og_site := soup.find("meta", property="og:site_name"):
            site_name = og_site.get("content")

        return FetchedArticle(
            url=url,
            title=title or "Untitled",
            content_html=content,
            author=author,
            published_at=published,
            word_count=word_count,
            reading_time_minutes=reading_time,
            extractor_used="trafilatura",
            is_paywalled=_looks_paywalled(content, url),
            site_name=site_name,
            content_hash=hashlib.sha256(content.encode()).hexdigest()[:16],
        )
    except Exception:
        return None


def _extract_with_bs4(url: str, html: str) -> FetchedArticle | None:
    soup = BeautifulSoup(html, "html.parser")

    for tag in soup.find_all([
        "script", "style", "nav", "header", "footer", "aside",
        "noscript", "iframe", "form", "button", "input",
    ]):
        tag.decompose()

    article = (
        soup.find("article")
        or soup.find(class_=re.compile(
            r"^(article|post|post-content|entry-content|story)$", re.I
        ))
        or soup.find(attrs={"role": "main"})
        or soup.find("main")
        or soup.find(class_=re.compile(r"content|body", re.I))
        or soup.body
    )
    if not article:
        return None

    parts: list[str] = []
    for elem in article.find_all([
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "blockquote", "pre",
    ]):
        if elem.get_text(strip=True):
            parts.append(str(elem))
    content_html = "\n".join(parts) or str(article)
    content_html = re.sub(r"\n{3,}", "\n\n", content_html)

    title = _title_from_soup(soup)
    author = None
    if author_meta := soup.find("meta", {"name": "author"}):
        author = author_meta.get("content")
    elif author_meta := soup.find("meta", property="article:author"):
        author = author_meta.get("content")

    published = None
    if date_meta := soup.find("meta", property="article:published_time"):
        published = date_meta.get("content")
    elif time_elem := soup.find("time", datetime=True):
        published = time_elem.get("datetime")

    text = BeautifulSoup(content_html, "html.parser").get_text(" ", strip=True)
    word_count = len(text.split()) if text else None
    reading_time = max(1, round(word_count / 225)) if word_count else None

    site_name = None
    if og_site := soup.find("meta", property="og:site_name"):
        site_name = og_site.get("content")

    return FetchedArticle(
        url=url,
        title=title or "Untitled",
        content_html=content_html,
        author=author,
        published_at=published,
        word_count=word_count,
        reading_time_minutes=reading_time,
        extractor_used="beautifulsoup",
        is_paywalled=_looks_paywalled(content_html, url),
        site_name=site_name,
        content_hash=hashlib.sha256(content_html.encode()).hexdigest()[:16],
    )


def _title_from_soup(soup) -> str | None:
    title = None
    if title_tag := soup.find("title"):
        title = title_tag.get_text(strip=True)
    if not title:
        if h1 := soup.find("h1"):
            title = h1.get_text(strip=True)
    if not title:
        if og_title := soup.find("meta", property="og:title"):
            title = og_title.get("content", "")
    if title:
        title = re.sub(r"\s*[|\-–—]\s*[^|\-–—]+$", "", title)
    return title


def _looks_paywalled(content: str, url: str) -> bool:
    lower = content.lower()
    if any(d in url.lower() for d in _PAYWALL_DOMAINS) and len(content) < 1000:
        return True
    if any(p in lower for p in _PAYWALL_PHRASES) and len(content) < 2000:
        return True
    return False


def html_to_text(html: str) -> str:
    """Extract visible text from HTML — used to feed content to summarizer."""
    if not _BS4_AVAILABLE:
        return html
    soup = BeautifulSoup(html, "html.parser")
    return soup.get_text("\n", strip=True)
