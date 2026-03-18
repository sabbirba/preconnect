import json
import html
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Sequence, Tuple
from urllib.parse import urljoin, urlsplit, urlunsplit
from urllib.request import Request, urlopen

from scrappers.cloudflare_browser import fetch_jina_markdown, fetch_rendered_html


MIN_EXAM_YEAR = 2025

_BLOCKED_MARKDOWN_TOKENS = (
    'just a moment...',
    'performing security verification',
    'attention required',
    'error 403',
    'target url returned error 403',
    'cloudflare',
)


def load_json_list(file_path: Path):
    if not file_path.exists():
        return []
    try:
        with file_path.open('r', encoding='utf-8') as f:
            payload = json.load(f)
        return payload if isinstance(payload, list) else []
    except Exception:
        return []


def save_json_list(file_path: Path, rows):
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with file_path.open('w', encoding='utf-8') as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)


def is_blocked_markdown(markdown: str) -> bool:
    if not markdown:
        return True
    lowered = markdown.lower()
    return any(token in lowered for token in _BLOCKED_MARKDOWN_TOKENS)


def normalize_url(url: str) -> str:
    cleaned = url.strip().strip('.,;:<>[]()\"\'')
    parts = urlsplit(cleaned)
    if not parts.netloc:
        return ''
    path = parts.path.rstrip('/')
    return urlunsplit(('https', parts.netloc.lower(), path, '', ''))


def clean_jina_markdown_body(markdown: str) -> str:
    if not markdown:
        return ''
    lines = [line.rstrip() for line in markdown.splitlines()]
    cleaned_lines = []
    skip_exact_prefixes = (
        'Title:',
        'URL Source:',
        'Published Time:',
        'Warning:',
        'Markdown Content:',
    )
    for line in lines:
        stripped = line.strip()
        if not stripped:
            cleaned_lines.append('')
            continue
        if any(stripped.startswith(prefix) for prefix in skip_exact_prefixes):
            continue
        cleaned_lines.append(stripped)
    text = '\n'.join(cleaned_lines)
    text = re.sub(r'\n{3,}', '\n\n', text).strip()
    return text


def is_allowed_exam_folder(folder_name: str, min_year: int = MIN_EXAM_YEAR) -> bool:
    normalized = re.sub(r'\s+', ' ', folder_name).replace('\u00a0', ' ').strip()
    if not normalized.startswith(('Final ', 'Mid ')):
        return False
    match = re.search(r'(Spring|Fall|Summer)\s+(\d{4})', normalized, re.IGNORECASE)
    if not match:
        return False
    return int(match.group(2)) >= min_year


def extract_semester_exam_folder(title: str, min_year: int = MIN_EXAM_YEAR):
    title_lower = title.lower()
    if 'final' in title_lower:
        exam_type = 'Final'
    elif 'mid' in title_lower:
        exam_type = 'Mid'
    else:
        return None

    match = re.search(r'(Spring|Fall|Summer)\s+\d{4}', title, re.IGNORECASE)
    if not match:
        return None
    semester = re.sub(r'\s+', ' ', match.group(0).strip())
    year_match = re.search(r'\d{4}', semester)
    if not year_match:
        return None
    if int(year_match.group(0)) < min_year:
        return None
    return f'{exam_type} {semester}'.strip()


def parse_published_iso_date(published_text: str):
    if not published_text:
        return None
    for fmt in ('%Y-%m-%dT%H:%M:%S%z', '%Y-%m-%dT%H:%M:%S+06:00'):
        try:
            return datetime.strptime(published_text, fmt).date().isoformat()
        except Exception:
            continue
    return None


def remove_ordinal_suffixes(text: str) -> str:
    if not text:
        return ''
    return re.sub(r'(\d+)(st|nd|rd|th)', r'\1', text)


def parse_date_to_iso(
    date_text: str,
    formats: Sequence[str],
    *,
    strip_ordinal: bool = False,
) -> Optional[str]:
    if not date_text:
        return None
    value = date_text.strip()
    if not value:
        return None
    if strip_ordinal:
        value = remove_ordinal_suffixes(value)
    for fmt in formats:
        try:
            return datetime.strptime(value, fmt).date().isoformat()
        except (ValueError, TypeError):
            continue
    return None


def parse_time_range_12h(time_str: str) -> Tuple[Optional[str], Optional[str]]:
    if not time_str or not time_str.strip():
        return (None, None)
    value = time_str.replace(' ', '').upper()
    patterns = [
        r'(\d{1,2}:\d{2}[AP]M)-(\d{1,2}:\d{2}[AP]M)',
        r'(\d{1,2}:\d{2}[AP]M)(\d{1,2}:\d{2}[AP]M)',
    ]
    for pattern in patterns:
        match = re.match(pattern, value)
        if not match:
            continue
        start_raw, end_raw = match.groups()
        for fmt in ('%I:%M%p', '%I%p'):
            try:
                start = datetime.strptime(start_raw, fmt).time().isoformat()
                end = datetime.strptime(end_raw, fmt).time().isoformat()
                return (start, end)
            except ValueError:
                continue
    return (None, None)


def fetch_page_with_fallback(url: str, *, timeout: int = 30):
    def fetch_with_backoff(fetcher, *, attempts: int = 3, base_delay: float = 0.5):
        last_content = ''
        for attempt in range(attempts):
            try:
                content = fetcher()
            except Exception:
                content = ''
            if content and not is_blocked_markdown(content):
                return content
            if content:
                last_content = content
            if attempt < attempts - 1:
                time.sleep(base_delay * (2**attempt))
        return last_content

    markdown = fetch_with_backoff(lambda: fetch_jina_markdown(url, timeout=timeout), attempts=3)
    if markdown and not is_blocked_markdown(markdown):
        return {'content': markdown, 'source': 'jina'}

    rendered_html = fetch_with_backoff(lambda: fetch_rendered_html(url, timeout=timeout), attempts=3)
    if rendered_html and not is_blocked_markdown(rendered_html):
        return {'content': rendered_html, 'source': 'rendered_html'}

    def fetch_direct_html():
        request = Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urlopen(request, timeout=timeout) as response:
            return response.read().decode('utf-8', errors='replace')

    direct_html = fetch_with_backoff(fetch_direct_html, attempts=3)
    if direct_html and not is_blocked_markdown(direct_html):
        return {'content': direct_html, 'source': 'direct_html'}

    return {'content': '', 'source': 'none'}


def extract_links_from_content(content: str, base_url: str):
    if not content:
        return []

    discovered = set()
    # Markdown/plain URL extraction.
    for raw in re.findall(r'https?://[^\s\)\]"\']+', content):
        discovered.add(raw.strip())

    # HTML href extraction.
    for href in re.findall(r'href=["\']([^"\']+)["\']', content, re.I):
        href = href.strip()
        if not href:
            continue
        discovered.add(urljoin(base_url, href))

    cleaned = []
    for link in discovered:
        normalized = normalize_url(link)
        if normalized:
            cleaned.append(normalized)
    return sorted(set(cleaned))


def content_to_text(content: str, *, source: str):
    if not content:
        return ''
    if source == 'jina':
        return clean_jina_markdown_body(content)
    text = re.sub(r'<script[\s\S]*?</script>', ' ', content, flags=re.I)
    text = re.sub(r'<style[\s\S]*?</style>', ' ', text, flags=re.I)
    text = re.sub(r'<[^>]+>', '\n', text)
    text = html.unescape(text)
    return re.sub(r'\n{3,}', '\n\n', text).strip()
