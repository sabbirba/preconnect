import re
from pathlib import Path

from bs4 import BeautifulSoup
from scrappers.shared import content_to_text, extract_links_from_content, fetch_page_with_fallback, load_json_list, parse_published_iso_date, save_json_list


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / 'data'
OUT_FILE = DATA_DIR / 'news.json'
BASE_URL = 'https://www.bracu.ac.bd'
ARCHIVE_URL = 'https://www.bracu.ac.bd/news-archive'


def clean_ordinal_date(date_str: str):
    return re.sub(r'(\d+)(st|nd|rd|th)', r'\1', date_str)
archive_fetch = fetch_page_with_fallback(ARCHIVE_URL, timeout=30)
archive_content = archive_fetch.get('content', '')
existing = load_json_list(OUT_FILE)
seen = {item.get('url') for item in existing if item.get('url')}

if not archive_content:
    save_json_list(OUT_FILE, existing)
    print('News: 0 pages discovered', flush=True)
    raise SystemExit(0)

links = extract_links_from_content(archive_content, BASE_URL)
discovered = [link for link in links if '/news' in link and '/news-archive' not in link]
print(f'News: {len(discovered)} pages discovered', flush=True)

for url in discovered:
    if url in seen:
        continue
    fetched = fetch_page_with_fallback(url, timeout=30)
    page_content = fetched.get('content', '')
    if not page_content:
        continue
    title = url.rsplit('/', 1)[-1]
    pub_date = None
    if fetched.get('source') == 'jina':
        title_match = re.search(r'^Title:\s*(.+)$', page_content, re.M)
        title = title_match.group(1).strip() if title_match else title
        published_match = re.search(r'Published Time:\s*(.+)$', page_content, re.M)
        pub_date = parse_published_iso_date(published_match.group(1).strip()) if published_match else None
    else:
        soup = BeautifulSoup(page_content, 'html.parser')
        h1 = soup.select_one('h1.page-h1') or soup.select_one('h1')
        title = h1.get_text(strip=True) if h1 else (soup.title.get_text(strip=True) if soup.title else title)
        meta_pub = soup.find('meta', attrs={'property': 'article:published_time'})
        if meta_pub and meta_pub.get('content'):
            pub_date = parse_published_iso_date(meta_pub.get('content').strip())

    text = content_to_text(page_content, source=fetched.get('source', 'direct_html'))
    images = [link for link in extract_links_from_content(page_content, BASE_URL) if re.search(r'\.(jpg|jpeg|png|gif|webp|svg)$', link, re.I)]
    existing.append(
        {
            'title': title,
            'url': url,
            'message': text,
            'image_url': images,
            'published_date': pub_date,
        }
    )
    seen.add(url)
    save_json_list(OUT_FILE, existing)

save_json_list(OUT_FILE, existing)
