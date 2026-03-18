import re
from pathlib import Path
from urllib.parse import urljoin

from bs4 import BeautifulSoup

from scrappers.shared import clean_jina_markdown_body, content_to_text, extract_links_from_content, fetch_page_with_fallback, is_blocked_markdown, load_json_list, normalize_url, save_json_list


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / 'data'
OUT_FILE = DATA_DIR / 'people.json'
SITEMAP_URL = 'https://www.bracu.ac.bd/sitemap.xml?page=1'
FACULTY_URL = 'https://www.bracu.ac.bd/faculty'
def pick_image_url(content, *, source, page_url=''):
    if source != 'jina':
        soup = BeautifulSoup(content, 'html.parser')
        for img in soup.find_all('img', src=True):
            src = urljoin(page_url, img.get('src', '').strip())
            lower = src.lower()
            if any(token in lower for token in ('logo', 'social/', 'map', 'icon', 'footer', 'facebook', 'youtube', 'linkedin', 'instagram')):
                continue
            return src.split('?', 1)[0]
        return None

    image_urls = re.findall(r'https?://[^\s\)]+\.(?:jpg|jpeg|png|webp|gif|svg)(?:\?[^\s\)]*)?', content, re.I)
    for url in image_urls:
        lower = url.lower()
        if any(token in lower for token in ('logo', 'social/', 'map', 'icon', 'footer', 'facebook', 'youtube', 'linkedin', 'instagram')):
            continue
        return url.split('?', 1)[0]
    return None


def normalize_people_link(url):
    return normalize_url(url)


def is_homepage_redirect(markdown, link):
    homepage_signatures = (
        'BRAC University',
        'Summer 2026 Admission Going on',
        'From Bangladesh to the World',
    )
    return link in markdown and any(signature in markdown for signature in homepage_signatures)


def is_blocked_or_invalid_profile(markdown):
    if is_blocked_markdown(markdown):
        return True
    title_match = re.search(r'^Title:\s*(.+)$', markdown, re.M)
    if title_match and title_match.group(1).strip().lower() == 'just a moment...':
        return True
    return False


def extract_emails(markdown):
    candidates = set()
    for email in re.findall(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}', markdown):
        candidates.add(email.strip(".,;:<>[]()\"'").lower())
    for match in re.findall(r'mailto:([^\s\)]+)', markdown, re.I):
        match = match.split('?', 1)[0].strip(".,;:<>[]()\"'").lower()
        if '@' in match:
            candidates.add(match)
    candidates.discard('info@bracu.ac.bd')
    return sorted(candidates)


def clean_profile_body(content, source):
    if source == 'jina':
        return clean_jina_markdown_body(content)
    return content_to_text(content, source=source)


def parse_people_markdown(content, source, existing, seen):
    urls = extract_links_from_content(content, 'https://www.bracu.ac.bd')
    people_links = []
    for url in urls:
        if '/people/' not in url:
            continue
        normalized = normalize_people_link(url)
        if normalized:
            people_links.append(normalized)

    for link in people_links[:300]:
        if link in seen:
            continue
        fetched = fetch_page_with_fallback(link, timeout=30)
        page_md = fetched.get('content', '')
        page_source = fetched.get('source', 'none')
        if is_blocked_or_invalid_profile(page_md):
            continue
        if is_homepage_redirect(page_md, link):
            continue
        title_match = re.search(r'^Title:\s*(.+)$', page_md, re.M)
        title = title_match.group(1).strip() if title_match else link.rsplit('/', 1)[-1].replace('-', ' ').title()
        if page_source != 'jina':
            soup = BeautifulSoup(page_md, 'html.parser')
            h1 = soup.select_one('h1.page-h1') or soup.select_one('h1')
            if h1:
                title = h1.get_text(strip=True)
            elif soup.title:
                title = soup.title.get_text(strip=True)

        about_text = clean_profile_body(page_md, page_source)
        if not about_text:
            continue
        image_url = pick_image_url(page_md, source=page_source, page_url=link)
        emails = extract_emails(page_md)
        existing.append(
            {
                'url': link,
                'image_url': image_url,
                'about': f'{title}\n{about_text}',
                'emails': sorted(set(emails)),
            }
        )
        seen.add(link)


def sanitize_existing_rows(rows):
    sanitized = []
    seen = set()
    for item in rows:
        if not isinstance(item, dict):
            continue
        url = normalize_people_link(str(item.get('url', '')))
        if not url or '/people/' not in url or url in seen:
            continue
        about = str(item.get('about', ''))
        if is_blocked_or_invalid_profile(about):
            continue
        about = clean_profile_body(about, 'jina')
        if not about:
            continue
        image_url = item.get('image_url')
        if image_url:
            image_url = str(image_url).strip()
        emails = item.get('emails')
        if not isinstance(emails, list):
            emails = []
        sanitized.append(
            {
                'url': url,
                'image_url': image_url or None,
                'about': about.strip(),
                'emails': sorted({str(e).strip().lower() for e in emails if isinstance(e, str) and '@' in e}),
            }
        )
        seen.add(url)
    return sanitized


existing = sanitize_existing_rows(load_json_list(OUT_FILE))
seen = {item.get('url') for item in existing if item.get('url')}

for source_url in (SITEMAP_URL, FACULTY_URL):
    fetched = fetch_page_with_fallback(source_url, timeout=30)
    markdown = fetched.get('content', '')
    if not markdown:
        continue
    parse_people_markdown(markdown, fetched.get('source', 'none'), existing, seen)

save_json_list(OUT_FILE, existing)
