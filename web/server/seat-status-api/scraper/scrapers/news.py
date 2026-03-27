import cloudscraper
from bs4 import BeautifulSoup
import json
from datetime import datetime
import re
from pathlib import Path
from requests.exceptions import RequestException
from json_store import load_rows, save_rows as save_json_rows

def clean_ordinal_date(date_str: str):
    """Remove ordinal suffixes like st, nd, rd, th from day numbers."""
    return re.sub(r'(\d+)(st|nd|rd|th)', r'\1', date_str)


base_url = "https://www.bracu.ac.bd"
DATA_DIR = Path("data")
DATA_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_FILE = DATA_DIR / "news.json"
rows = []
YEAR_GUARD = 2025
REQUEST_TIMEOUT_SECONDS = 30
MAX_RETRIES = 4
RETRY_DELAY_SECONDS = 3

def load_existing_rows():
    return load_rows(OUTPUT_FILE)


rows = load_existing_rows()


def save_rows():
    save_json_rows(OUTPUT_FILE, rows, lambda row: (row.get("url"),) if row.get("url") else None)

# === SCRAPER ===
scraper = cloudscraper.create_scraper()


def fetch_with_retry(url, label):
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            return scraper.get(url, timeout=REQUEST_TIMEOUT_SECONDS)
        except RequestException as exc:
            if attempt == MAX_RETRIES:
                print(f"Failed to fetch {label} after {MAX_RETRIES} attempts: {exc}")
                return None
            print(
                f"Attempt {attempt}/{MAX_RETRIES} failed for {label}: {exc}. Retrying in {RETRY_DELAY_SECONDS}s...",
            )
            import time
            time.sleep(RETRY_DELAY_SECONDS)

sitemap_page = 0
stop_scrape = False
while True:
    main_url = f"{base_url}/news-archive?page={sitemap_page}"
    print(f"Fetching: {main_url}")
    # Fetch the main page
    response = fetch_with_retry(main_url, main_url)
    if response is None:
        break
    if response.status_code == 404:
        break
    if response.status_code != 200:
        print(f"Failed to fetch {main_url}, status code: {response.status_code}")
        break

    # Parse the main page
    soup = BeautifulSoup(response.text, "html.parser")

    # Remove parent of pagination div
    pagination_div = soup.find("div", class_="item-list item-list-pagination")
    if pagination_div:
        pagination_div.decompose()

    # Find all divs with class "block-content content"
    blocks = soup.find_all("div", class_="block-content content")

    if len(blocks) < 3:
        print("Less than 3 content blocks found.")
        break

    # Target block
    target_block = blocks[2]

    # Extract all a tags that start with /news
    links = [a for a in target_block.find_all("a", href=True) if a['href'].startswith("/news")]

    for link in links:
        title = link.get_text(strip=True)
        url = base_url + link['href']

        # Fetch the page of the link
        page_resp = fetch_with_retry(url, url)
        if page_resp is None:
            continue
        if page_resp.status_code != 200:
            print(f"  Failed to fetch {url}")
            continue

        # Parse the page
        page_soup = BeautifulSoup(page_resp.text, "html.parser")
        page_blocks = page_soup.find_all("div", class_="block-content content")

        if len(page_blocks) < 3:
            print("  Less than 3 content blocks on the page.")
            continue

        page_content_block = page_blocks[2]
        message = page_content_block.get_text(separator="\n", strip=True)

        # Collect all images
        images = [img['src'] for img in page_content_block.find_all("img", src=True)]
        image_urls_json = json.dumps(images) if images else json.dumps([])

        # === Get published date ===
        date_tag = page_soup.select_one("span.date-display-single")
        published_at = None
        if date_tag:
            published_date = clean_ordinal_date(date_tag.get_text(strip=True))
            try:
                published_at = datetime.strptime(published_date, "%B %d, %Y")
            except Exception as e:
                print(f"  Could not parse date '{published_date}' for {title}: {e}")

        if published_at and published_at.year < YEAR_GUARD:
            save_rows()
            stop_scrape = True
            print(f"Reached year guard {YEAR_GUARD}, stopping news scrape.")
            break

        rows.append(
            {
                "title": title,
                "message": message,
                "image_url": image_urls_json,
                "published_date": published_at.isoformat() if published_at else None,
                "url": url,
            }
        )
        save_rows()

        if stop_scrape:
            break
    sitemap_page += 1

    if stop_scrape:
        break

save_rows()
