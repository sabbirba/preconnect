from __future__ import annotations

import html
import json
import os
import re
import subprocess
import tempfile
import sys
import socket
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Optional, Sequence
from urllib.parse import urljoin, urlsplit, urlunsplit
from urllib.request import Request, urlopen

from bs4 import BeautifulSoup
import calendar
from fastapi import FastAPI, Query
from fastapi.responses import FileResponse


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / 'data'
PDF_DIR = BASE_DIR / 'pdf'
BASE_URL = 'https://www.bracu.ac.bd'


app = FastAPI(title='BRACU Scraper API')


def _load_env_file() -> None:
    env_path = BASE_DIR / '.env'
    if not env_path.exists():
        return
    for raw_line in env_path.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


_load_env_file()


@dataclass(frozen=True)
class FetchResult:
    content: str
    source: str


def _load_json(name: str, default):
    path = DATA_DIR / name
    if not path.exists():
        return default
    try:
        with path.open('r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return default


def _save_json(name: str, payload) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    target = DATA_DIR / name
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=DATA_DIR, delete=False) as tmp:
        json.dump(payload, tmp, ensure_ascii=False, indent=2)
        tmp.flush()
        os.fsync(tmp.fileno())
        temp_name = tmp.name
    Path(temp_name).replace(target)


def _init_data() -> None:
    defaults = {
        'announcements.json': [],
        'academics.json': [],
        'news.json': [],
        'transport.json': [],
    }
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    expected = set(defaults)
    for path in DATA_DIR.glob('*.json'):
        if path.name not in expected:
            path.unlink(missing_ok=True)
    for name, payload in defaults.items():
        path = DATA_DIR / name
        if not path.exists():
            _save_json(name, payload)


def _cloudflare_configured() -> bool:
    return bool(os.getenv('CF_BROWSER_RENDERING_TOKEN', '').strip() and os.getenv('CF_ACCOUNT_ID', '').strip())


def _find_free_port(start: int = 8001, limit: int = 8100) -> int:
    for port in range(start, limit + 1):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                sock.bind(('0.0.0.0', port))
            except OSError:
                continue
            return port
    return start


def _parse_api_date(raw: str) -> Optional[date]:
    text = (raw or '').strip()
    if not text:
        return None
    for fmt in ('%Y-%m-%d', '%d-%m-%Y', '%d/%m/%Y', '%B %d, %Y'):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(text).date()
    except Exception:
        return None


def _filter_by_date_range(items, key, start_date, end_date):
    start = _parse_api_date(start_date) if start_date else None
    end = _parse_api_date(end_date) if end_date else None
    if not start and not end:
        return items
    output = []
    for item in items:
        value = _parse_api_date(item.get(key))
        if value is None:
            continue
        if start and value < start:
            continue
        if end and value > end:
            continue
        output.append(item)
    return output


def normalize_url(url: str) -> str:
    cleaned = url.strip().strip('.,;:<>[]()\"\'')
    parts = urlsplit(cleaned)
    if not parts.netloc:
        return ''
    path = parts.path.rstrip('/')
    return urlunsplit(('https', parts.netloc.lower(), path, '', ''))


def extract_links_from_content(content: str, base_url: str):
    if not content:
        return []
    discovered = set()
    for raw in re.findall(r'https?://[^\s\)\]"\']+', content):
        discovered.add(raw.strip())
    for href in re.findall(r'href=["\']([^"\']+)["\']', content, re.I):
        href = href.strip()
        if href:
            discovered.add(urljoin(base_url, href))
    cleaned = []
    for link in discovered:
        normalized = normalize_url(link)
        if normalized:
            cleaned.append(normalized)
    return sorted(set(cleaned))


def content_to_text(content: str) -> str:
    if not content:
        return ''
    text = re.sub(r'<script[\s\S]*?</script>', ' ', content, flags=re.I)
    text = re.sub(r'<style[\s\S]*?</style>', ' ', text, flags=re.I)
    text = re.sub(r'<[^>]+>', '\n', text)
    text = html.unescape(text)
    return re.sub(r'\n{3,}', '\n\n', text).strip()


def remove_ordinal_suffixes(text: str) -> str:
    if not text:
        return ''
    return re.sub(r'(\d+)(st|nd|rd|th)', r'\1', text)


def parse_date_to_iso(date_text: str, formats: Sequence[str], *, strip_ordinal: bool = False) -> Optional[str]:
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


def parse_published_iso_date(published_text: str):
    if not published_text:
        return None
    for fmt in ('%Y-%m-%dT%H:%M:%S%z', '%Y-%m-%dT%H:%M:%S+06:00'):
        try:
            return datetime.strptime(published_text, fmt).date().isoformat()
        except Exception:
            continue
    return None


def _is_real_content_url(url: str, *, kind: str) -> bool:
    path = urlsplit(url).path.lower()
    if kind == 'news':
        return '/news/' in path and '/news-archive' not in path
    if kind == 'announcement':
        if '/news-archive' in path:
            return False
        if path in {'', '/'}:
            return False
        blocked = (
            '/announcements',
            '/apply-now',
            '/admissions',
            '/academic-dates',
            '/students-transport-service',
            '/contact',
            '/career',
        )
        return not any(block in path for block in blocked)
    return True


def _is_real_page_text(text: str) -> bool:
    if not text:
        return False
    lower = text.lower()
    bad_markers = (
        'please wait while your request is being verified',
        'one moment, please',
        'choose your application type',
        'news archive | page',
    )
    return not any(marker in lower for marker in bad_markers)


def _archive_entry_from_anchor(anchor, base_url: str):
    href = anchor.get('href', '').strip()
    title = ' '.join(anchor.get_text(' ', strip=True).split())
    if not href or not title:
        return None
    url = urljoin(base_url, href)
    parent = anchor
    for _ in range(3):
        if parent.parent is None:
            break
        parent = parent.parent
    message = ' '.join(parent.get_text(' ', strip=True).split()) if parent else title
    published_date = None
    match = re.search(r'([A-Z][a-z]+ \d{1,2}(?:st|nd|rd|th)?(?:, \d{4})?)', message)
    if match:
        published_date = parse_date_to_iso(match.group(1), ('%B %d, %Y', '%B %d %Y'), strip_ordinal=True)
    return {'title': title, 'url': url, 'message': message, 'published_date': published_date}


def fetch_rendered_page(url: str, *, timeout: int = 10, wait_for_selector: Optional[str] = None) -> str:
    token = os.getenv('CF_BROWSER_RENDERING_TOKEN', '').strip()
    account_id = os.getenv('CF_ACCOUNT_ID', '').strip()
    if not token or not account_id:
        return ''
    payload = {'url': url, 'gotoOptions': {'waitUntil': 'networkidle2'}}
    if wait_for_selector:
        payload['waitForSelector'] = wait_for_selector
    request = Request(
        f'https://api.cloudflare.com/client/v4/accounts/{account_id}/browser-rendering/content',
        data=json.dumps(payload).encode('utf-8'),
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
        },
        method='POST',
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            raw = response.read().decode('utf-8', errors='replace')
        data = json.loads(raw)
    except Exception:
        return ''

    def extract(node) -> str:
        if isinstance(node, str) and node.strip():
            return node.strip()
        if isinstance(node, dict):
            for key in ('content', 'html', 'body', 'result'):
                value = node.get(key)
                extracted = extract(value)
                if extracted:
                    return extracted
        if isinstance(node, list):
            for item in node:
                extracted = extract(item)
                if extracted:
                    return extracted
        return ''

    return extract(data)


def fetch_direct_page(url: str, *, timeout: int = 30) -> str:
    request = Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urlopen(request, timeout=timeout) as response:
            return response.read().decode('utf-8', errors='replace')
    except Exception:
        return ''


def fetch_cloudflare_page(url: str, *, timeout: int = 30) -> FetchResult:
    rendered_html = fetch_rendered_page(url, timeout=timeout)
    if rendered_html:
        return FetchResult(content=rendered_html, source='cloudflare')
    direct_html = fetch_direct_page(url, timeout=timeout)
    if direct_html:
        return FetchResult(content=direct_html, source='direct')
    return FetchResult(content='', source='none')


def scrape_announcements():
    existing = _load_json('announcements.json', [])
    seen = {item.get('url') for item in existing}
    for page in range(1, 12):
        fetched = fetch_cloudflare_page(f'{BASE_URL}/announcements?page={page}', timeout=30)
        content = fetched.content
        if not content:
            break
        soup = BeautifulSoup(content, 'html.parser')
        page_items = []
        for anchor in soup.select('.view-content a[href], .views-row a[href], article a[href], h2 a[href], h3 a[href], h4 a[href], h5 a[href]'):
            item = _archive_entry_from_anchor(anchor, BASE_URL)
            if item and _is_real_content_url(item['url'], kind='announcement'):
                page_items.append(item)
        if not page_items:
            break
        for item in page_items:
            if item['url'] in seen:
                continue
            existing.append(item)
            seen.add(item['url'])
            _save_json('announcements.json', existing)
        if not soup.find('a', string=re.compile(r'next', re.I)):
            break


def _parse_announcements_date(soup):
    date_tag = soup.select_one('span.date-display-single')
    if not date_tag:
        return None
    published_date = date_tag.get_text(strip=True)
    try:
        return datetime.strptime(published_date.split(',', 1)[1].strip(), '%B %d, %Y - %H:%M').date().isoformat()
    except Exception:
        return None


def scrape_news():
    existing = _load_json('news.json', [])
    seen = {item.get('url') for item in existing if item.get('url')}
    for page in range(1, 12):
        archive_fetch = fetch_cloudflare_page(f'{BASE_URL}/news-archive?page={page}', timeout=30)
        archive_content = archive_fetch.content
        if not archive_content:
            break
        soup = BeautifulSoup(archive_content, 'html.parser')
        page_items = []
        for anchor in soup.select('.view-content a[href], .views-row a[href], article a[href], h2 a[href], h3 a[href], h4 a[href], h5 a[href]'):
            item = _archive_entry_from_anchor(anchor, BASE_URL)
            if item and _is_real_content_url(item['url'], kind='news'):
                page_items.append(item)
        if not page_items:
            break
        for item in page_items:
            if item['url'] in seen:
                continue
            existing.append({
                'title': item['title'],
                'url': item['url'],
                'message': item['message'],
                'image_url': [],
                'published_date': item['published_date'],
            })
            seen.add(item['url'])
            _save_json('news.json', existing)
        if not soup.find('a', string=re.compile(r'next', re.I)):
            break


def scrape_academics():
    fetched = fetch_cloudflare_page(f'{BASE_URL}/academic-dates', timeout=30)
    content = fetched.content
    existing = _load_json('academics.json', [])
    dedup = {(item.get('semester'), item.get('year'), item.get('event_name'), item.get('start_date'), item.get('end_date')) for item in existing}
    if not content:
        return
    soup = BeautifulSoup(content, 'html.parser')
    rows = []
    for table in soup.select('table'):
        for tr in table.select('tr'):
            cells = [' '.join(cell.get_text(' ', strip=True).split()) for cell in tr.select('th,td')]
            if len(cells) < 3:
                continue
            if [c.lower() for c in cells[:3]] == ['date', 'day', 'event']:
                continue
            rows.append((cells[0], cells[1], ' '.join(cells[2:])))
    for date_text, day_text, event_name in rows:
        if not re.search(r'\b(19|20)\d{2}\b', date_text):
            continue
        semester_match = re.search(r'(Spring|Summer|Fall)\s+(\d{4})', event_name, re.I) or re.search(r'(Spring|Summer|Fall)\s+(\d{4})', date_text, re.I)
        if semester_match:
            semester = semester_match.group(1).lower()
            year = int(semester_match.group(2))
        else:
            semester = 'unknown'
            year = datetime.now().year
        start_text = date_text.split(' to ', 1)[0].strip()
        end_text = date_text.split(' to ', 1)[1].strip() if ' to ' in date_text else start_text
        start_date = parse_date_to_iso(start_text, ('%d/%m/%Y', '%d/%m/%Y - %H:%M', '%d %b, %Y', '%d %B, %Y'), strip_ordinal=True)
        end_date = parse_date_to_iso(end_text, ('%d/%m/%Y', '%d/%m/%Y - %H:%M', '%d %b, %Y', '%d %B, %Y'), strip_ordinal=True)
        if not start_date or not end_date:
            continue
        row = {'semester': semester, 'year': year, 'event_name': f'{day_text} {event_name}'.strip(), 'start_date': start_date, 'end_date': end_date}
        key = (semester, year, row['event_name'], start_date, end_date)
        if key in dedup:
            continue
        existing.append(row)
        dedup.add(key)
        _save_json('academics.json', existing)


def scrape_transport():
    content = fetch_rendered_page(f'{BASE_URL}/students-transport-service', timeout=45, wait_for_selector='body')
    fetched = FetchResult(content=content, source='cloudflare') if content else fetch_cloudflare_page(f'{BASE_URL}/students-transport-service', timeout=45)
    content = fetched.content
    existing = _load_json('transport.json', [])
    if not content:
        return
    schedule_url = None
    for link in extract_links_from_content(content, BASE_URL):
        lower = link.lower()
        if 'drive.google.com' in lower or lower.endswith('.pdf'):
            schedule_url = link
            break
    if not schedule_url:
        schedule_link = BeautifulSoup(content, 'html.parser').find('a', href=re.compile(r'(drive\.google\.com|\.pdf(?:\?|$))', re.I))
        if schedule_link and schedule_link.get('href'):
            schedule_url = schedule_link.get('href')
            if schedule_url.startswith('/'):
                schedule_url = urljoin(BASE_URL, schedule_url)
    if not schedule_url:
        return
    _save_json('transport.json', [
        {
            'route_name': 'Transport Service',
            'stoppage': 'See transport schedule',
            'schedule_url': schedule_url,
        }
    ])


def scrape_exam_pdf():
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    target = PDF_DIR / 'exam.pdf'
    pdf_url = None

    fetched = fetch_cloudflare_page(BASE_URL, timeout=45)
    content = fetched.content
    if content:
        for link in extract_links_from_content(content, BASE_URL):
            lower = link.lower()
            if 'exam' in lower and lower.endswith('.pdf'):
                pdf_url = link
                break
        if not pdf_url:
            soup = BeautifulSoup(content, 'html.parser')
            for anchor in soup.find_all('a', href=True):
                href = anchor.get('href', '').strip()
                text = anchor.get_text(' ', strip=True).lower()
                if 'exam' in href.lower() and href.lower().endswith('.pdf'):
                    pdf_url = urljoin(BASE_URL, href)
                    break
                if 'exam' in text and href.lower().endswith('.pdf'):
                    pdf_url = urljoin(BASE_URL, href)
                    break

    if not pdf_url:
        return 0

    try:
        request = Request(pdf_url, headers={'User-Agent': 'Mozilla/5.0'})
        with urlopen(request, timeout=60) as response:
            target.write_bytes(response.read())
    except Exception:
        return 1
    return 0


@app.get('/')
def read_root():
    index = BASE_DIR / 'client' / 'index.html'
    if index.exists():
        return FileResponse(index)
    return {'ok': True, 'message': 'BRACU Scraper API'}


@app.get('/announcements')
def get_announcements(
    start_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
    end_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
):
    rows = _load_json('announcements.json', [])
    rows = _filter_by_date_range(rows, 'published_date', start_date, end_date)
    rows.sort(key=lambda item: item.get('published_date') or '', reverse=True)
    return rows


@app.get('/academic-dates')
def get_academic_dates(
    semester: Optional[str] = Query(None, description='spring, summer, fall'),
    event_name: Optional[str] = None,
    start_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
    end_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
):
    rows = _load_json('academics.json', [])
    output = []
    semester_value = (semester or '').strip().lower()
    event_value = (event_name or '').strip().lower()
    for item in rows:
        if semester_value and item.get('semester', '').strip().lower() != semester_value:
            continue
        if event_value and event_value not in item.get('event_name', '').lower():
            continue
        output.append(item)

    output = _filter_by_date_range(output, 'start_date', start_date, end_date)
    output.sort(key=lambda item: item.get('start_date') or '')
    return output


@app.get('/news')
def get_news(
    title: Optional[str] = None,
    start_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
    end_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
    exact_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
):
    rows = _load_json('news.json', [])
    output = []
    title_value = (title or '').strip().lower()
    for item in rows:
        if title_value and title_value not in item.get('title', '').lower():
            continue
        output.append(item)
    if exact_date:
        output = [item for item in output if item.get('published_date') == exact_date]
    else:
        output = _filter_by_date_range(output, 'published_date', start_date, end_date)
    if not any([title, start_date, end_date, exact_date]):
        today = date.today()
        first_day = date(today.year, today.month, 1)
        last_day = date(today.year, today.month, calendar.monthrange(today.year, today.month)[1])
        output = _filter_by_date_range(
            output,
            'published_date',
            first_day.isoformat(),
            last_day.isoformat(),
        )
    output.sort(key=lambda item: item.get('published_date') or '', reverse=True)
    return output


@app.get('/transport')
def get_transport(route_id: Optional[int] = None):
    rows = _load_json('transport.json', [])
    if route_id is None:
        return rows
    route_token = f'route-{int(route_id):02}'
    return [
        item
        for item in rows
        if route_token in item.get('route_name', '').lower()
    ]


def main() -> int:
    if not _cloudflare_configured():
        print('Cloudflare credentials not found. Check web/scraper/.env or your shell environment.', flush=True)
    serve_api = '--serve' in sys.argv or '--api' in sys.argv
    steps = [
        ('init', lambda: (_init_data() or 0)),
        ('announcements', scrape_announcements),
        ('news', scrape_news),
        ('academics', scrape_academics),
        ('transport', scrape_transport),
        ('exam pdf', scrape_exam_pdf),
    ]

    for index, (label, step) in enumerate(steps, start=1):
        print(f'[{index}/{len(steps)}] Running {label}...', flush=True)
        code = step() or 0
        if code != 0:
            print(f'Step failed with exit code {code}: {label}', flush=True)
            return code
    if not serve_api:
        return 0
    print(f'[{len(steps) + 1}/{len(steps) + 1}] Running api...', flush=True)
    code = subprocess.run(
        [sys.executable, '-m', 'uvicorn', 'run:app', '--host', '0.0.0.0', '--port', str(_find_free_port())],
        cwd=BASE_DIR,
        env=os.environ.copy(),
    ).returncode
    if code != 0:
        print(f'Step failed with exit code {code}: api', flush=True)
        return code
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
