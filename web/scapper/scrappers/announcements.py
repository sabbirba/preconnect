import time
from datetime import datetime
from pathlib import Path
from urllib.parse import urljoin

from bs4 import BeautifulSoup
from scrappers.cloudflare_browser import crawl_urls
from scrappers.shared import content_to_text, extract_links_from_content, fetch_page_with_fallback, load_json_list, save_json_list


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / 'data'
OUT_FILE = DATA_DIR / 'announcements.json'
base_url = 'https://www.bracu.ac.bd'
existing = load_json_list(OUT_FILE)
seen = {item.get('url') for item in existing}

discovered = crawl_urls(
    f'{base_url}/news-archive/announcements',
    path_prefix='/news-archive/announcements',
)
if not discovered:
    discovered = []
    page = 0
    while True:
        url = f'{base_url}/news-archive/announcements?page={page}'
        fetched = fetch_page_with_fallback(url, timeout=30)
        content = fetched.get('content', '')
        if not content:
            break

        page_links = [
            link
            for link in extract_links_from_content(content, base_url)
            if '/news-archive/announcements/' in link
        ]
        if not page_links:
            break
        discovered.extend(page_links)
        page += 1

discovered = sorted(set(discovered))

print(f'Announcements: {len(discovered)} pages discovered', flush=True)

for full_url in discovered:
    if full_url in seen:
        continue
    print(f'Announcements: fetching {full_url}', flush=True)

    title = full_url.rsplit('/', 1)[-1].replace('-', ' ').strip() or 'No title'
    message = ''
    images = []
    published_date = None

    fetched = fetch_page_with_fallback(full_url, timeout=30)
    linked_content = fetched.get('content', '')
    if not linked_content:
        continue
    linked_soup = BeautifulSoup(linked_content, 'html.parser')
    title_tag = linked_soup.select_one('h1.page-h1')
    if title_tag:
        title = title_tag.get_text(strip=True)

    if fetched.get('source') == 'jina':
        message = content_to_text(linked_content, source='jina')
    else:
        content_divs = linked_soup.select('div.block-content.content')
        if len(content_divs) >= 3:
            content_div = content_divs[2]
            message = content_div.get_text(separator='\n', strip=True)
        else:
            message = content_to_text(linked_content, source=fetched.get('source', 'direct_html'))

    images = [
        link
        for link in extract_links_from_content(linked_content, base_url)
        if link != full_url
    ]
    if images:
        message += '\nEmbedded Page Links :\n' + '\n'.join(images)

    date_tag = linked_soup.select_one('span.date-display-single')
    if date_tag:
        published_date = date_tag.get_text(strip=True)
        try:
            published_date = datetime.strptime(
                published_date.split(',', 1)[1].strip(),
                '%B %d, %Y - %H:%M',
            ).date().isoformat()
        except Exception:
            published_date = None

    existing.append(
        {
            'title': title,
            'url': full_url,
            'message': message,
            'published_date': published_date,
        }
    )
    seen.add(full_url)
    save_json_list(OUT_FILE, existing)
    time.sleep(0.1)

save_json_list(OUT_FILE, existing)
