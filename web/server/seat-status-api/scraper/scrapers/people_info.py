import cloudscraper
from bs4 import BeautifulSoup
import json
from pathlib import Path
from requests.exceptions import TooManyRedirects
from urllib.parse import urlsplit, urlunsplit
from json_store import load_rows, save_rows as save_json_rows

def decode_cf_email(e):
    """Decode Cloudflare-protected emails"""
    r = int(e[:2], 16)
    return "".join(
        chr(int(e[i:i+2], 16) ^ r)
        for i in range(2, len(e), 2)
    )


def strip_query(url):
    if not url:
        return url
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


DATA_DIR = Path("data")
DATA_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_FILE = DATA_DIR / "people.json"

scraper = cloudscraper.create_scraper()
rows = []


def load_existing_rows():
    return load_rows(OUTPUT_FILE)


rows = load_existing_rows()


def save_rows():
    save_json_rows(OUTPUT_FILE, rows, lambda row: (row.get("url"),) if row.get("url") else None)

sitemap_page = 1
while True:
    sitemap_url = f"https://www.bracu.ac.bd/sitemap.xml?page={sitemap_page}"
    r = scraper.get(sitemap_url)
    if r.status_code != 200:
        break

    # Parse sitemap
    soup = BeautifulSoup(r.content, "lxml-xml")
    urls = soup.find_all("url")
    people_links = [u for u in urls if "/people/" in u.loc.text]
    if not people_links:
        break

    for u in people_links:
        link = u.loc.text
        try:
            r2 = scraper.get(link, allow_redirects=True)
        except TooManyRedirects:
            print(f"Skipped redirect loop: {link}")
            continue

        # Skip if redirected to homepage
        if r2.url.rstrip("/") == "https://www.bracu.ac.bd":
            print(f"Skipped: {link}")
            continue

        soup2 = BeautifulSoup(r2.content, "html.parser")
        divs = soup2.find_all("div", class_="block-content content")
        if len(divs) >= 3:
            # Decode Cloudflare emails
            for span in divs[2].find_all("span", class_="__cf_email__"):
                encoded_email = span.get("data-cfemail")
                if encoded_email:
                    span.string = decode_cf_email(encoded_email)


            about_text = divs[2].get_text(separator="\n", strip=True)
            imgs = divs[2].find_all("img")
            image_url = strip_query(imgs[0].get("src")) if imgs and imgs[0].get("src") else None

            rows.append(
                {
                    "url": strip_query(link),
                    "image_url": image_url,
                    "about": about_text,
                }
            )
            save_rows()

    sitemap_page += 1

save_rows()
