import cloudscraper
from bs4 import BeautifulSoup
from urllib.parse import urljoin
import time
from datetime import datetime
from pathlib import Path
from requests.exceptions import RequestException
from json_store import load_rows, save_rows as save_json_rows

# ==========================
DATA_DIR = Path("data")
DATA_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_FILE = DATA_DIR / "announcements.json"
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


def parse_published_at(published_date):
    if not published_date:
        return None

    text = published_date.strip()
    if "," in text:
        text = text.split(",", 1)[1].strip()

    for fmt in ("%B %d, %Y - %H:%M", "%B %d, %Y"):
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            continue

    return None

# ==========================
# Web Scraper Setup
# ==========================
scraper = cloudscraper.create_scraper()
base_url = "https://www.bracu.ac.bd"


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
            time.sleep(RETRY_DELAY_SECONDS)

sitemap_page = 0  # Drupal pages start at 0
stop_scrape = False
while True:
    url = f"{base_url}/news-archive/announcements?page={sitemap_page}"
    response = fetch_with_retry(url, f"announcements page {sitemap_page}")
    if response is None:
        break
    
    if response.status_code != 200:
        print(f"Failed to fetch page {sitemap_page}, status code: {response.status_code}")
        break

    soup = BeautifulSoup(response.text, "html.parser")
    articles = soup.select("article.node-announcement")
    
    if not articles:
        print("No more announcements found.")
        break

    for article in articles:
        # Title and relative link
        title_tag = article.select_one("h2.page-h1 a")
        title = title_tag.get_text(strip=True) if title_tag else "No title"
        relative_link = title_tag['href'] if title_tag else None
        full_url = urljoin(base_url, relative_link) if relative_link else None

        # Visit the linked page to get the message
        message = ""
        if full_url:
            linked_resp = fetch_with_retry(full_url, full_url)
            if linked_resp is None:
                continue
            linked_soup = BeautifulSoup(linked_resp.text, "html.parser")
            
            content_divs = linked_soup.select("div.block-content.content")
            if len(content_divs) >= 3:
                content_div = content_divs[2]
                links = []
                message = content_div.get_text(separator="\n", strip=True)
                for a_tag in content_div.find_all("a", href=True):
                    link = a_tag['href']
                    if "https:" not in link:
                        link = "https:" + link
                    links.append(link)
                if links:
                    message += "\nEmbedded Page Links:\n" + "\n".join(links)

            # Published date
            date_tag = linked_soup.select_one("span.date-display-single")
            published_date = date_tag.get_text(strip=True) if date_tag else None
            published_at = parse_published_at(published_date)
            print("published_date", published_date)

            if published_at and published_at.year < YEAR_GUARD:
                save_rows()
                stop_scrape = True
                print(f"Reached year guard {YEAR_GUARD}, stopping announcements scrape.")
                break

        rows.append(
            {
                "title": title,
                "url": full_url,
                "message": message,
                "published_date": published_at.isoformat() if published_at else None,
            }
        )
        save_rows()

        time.sleep(1)

        if stop_scrape:
            break

    if stop_scrape:
        break
    sitemap_page += 1
    time.sleep(3)

save_rows()
