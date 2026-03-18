import json
import os
from urllib.parse import urlparse
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from typing import Optional


CF_API_BASE = 'https://api.cloudflare.com/client/v4'


def _cf_headers():
    token = os.getenv('CF_BROWSER_RENDERING_TOKEN', '').strip()
    account_id = os.getenv('CF_ACCOUNT_ID', '').strip()
    if not token or not account_id:
        return None
    return token, account_id


def fetch_rendered_html(
    url: str,
    *,
    timeout: int = 10,
    wait_for_selector: Optional[str] = None,
) -> str:
    credentials = _cf_headers()
    if credentials:
        token, account_id = credentials
        api_url = f'{CF_API_BASE}/accounts/{account_id}/browser-rendering/content'
        payload = {'url': url, 'gotoOptions': {'waitUntil': 'networkidle2'}}
        if wait_for_selector:
            payload['waitForSelector'] = wait_for_selector
        payload = json.dumps(payload).encode('utf-8')
        request = Request(
            api_url,
            data=payload,
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
            if isinstance(data, dict):
                for key in ('result', 'content', 'html', 'body'):
                    value = data.get(key)
                    if isinstance(value, str) and value.strip():
                        return value
                if 'result' in data and isinstance(data['result'], dict):
                    for key in ('content', 'html', 'body'):
                        value = data['result'].get(key)
                        if isinstance(value, str) and value.strip():
                            return value
            return raw
        except Exception:
            pass

    request = Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urlopen(request, timeout=timeout) as response:
            return response.read().decode('utf-8', errors='replace')
    except Exception:
        return ''


def crawl_urls(
    url: str,
    *,
    timeout: int = 15,
    path_prefix: Optional[str] = None,
    wait_for_selector: Optional[str] = None,
):
    credentials = _cf_headers()
    if not credentials:
        return []

    token, account_id = credentials
    api_url = f'{CF_API_BASE}/accounts/{account_id}/browser-rendering/links'
    payload = {'url': url, 'gotoOptions': {'waitUntil': 'networkidle2'}}
    if wait_for_selector:
        payload['waitForSelector'] = wait_for_selector
    payload = json.dumps(payload).encode('utf-8')
    request = Request(
        api_url,
        data=payload,
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
        return []

    candidates = []
    queue = [data]
    while queue:
        node = queue.pop(0)
        if isinstance(node, dict):
            for key in ('result', 'data', 'items', 'results', 'pages', 'links'):
                value = node.get(key)
                if value is not None:
                    queue.append(value)
            for key in ('url', 'href', 'link'):
                value = node.get(key)
                if isinstance(value, str) and value.strip():
                    candidates.append(value.strip())
        elif isinstance(node, list):
            queue.extend(node)
        elif isinstance(node, str) and node.strip():
            candidates.append(node.strip())

    unique = []
    seen = set()
    for item in candidates:
        parsed = urlparse(item)
        if parsed.scheme not in ('http', 'https') or not parsed.netloc:
            continue
        if path_prefix and not parsed.path.startswith(path_prefix):
            continue
        if item in seen:
            continue
        seen.add(item)
        unique.append(item)
    return unique


def scrape_elements(
    url: str,
    selectors,
    *,
    timeout: int = 30,
    wait_for_selector: Optional[str] = None,
):
    credentials = _cf_headers()
    if not credentials:
        return []

    token, account_id = credentials
    api_url = f'{CF_API_BASE}/accounts/{account_id}/browser-rendering/scrape'
    payload = {'url': url, 'elements': [{'selector': selector} for selector in selectors]}
    if wait_for_selector:
        payload['waitForSelector'] = wait_for_selector
    request = Request(
        api_url,
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
        return []

    result = data.get('result') if isinstance(data, dict) else data
    if isinstance(result, list):
        return result
    return []


def fetch_jina_markdown(url: str, *, timeout: int = 30) -> str:
    jina_url = f'https://r.jina.ai/http://{url.replace("https://", "").replace("http://", "")}'
    request = Request(jina_url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urlopen(request, timeout=timeout) as response:
            return response.read().decode('utf-8', errors='replace')
    except Exception:
        return ''
