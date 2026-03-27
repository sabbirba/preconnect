import cloudscraper
import time
import re
from pathlib import Path
import json
from urllib.parse import urlparse

# Base folders for saved files
DATA_DIR = Path("data")
PDF_DIR = Path("pdf")
DATA_DIR.mkdir(parents=True, exist_ok=True)
PDF_DIR.mkdir(parents=True, exist_ok=True)

# Initialize cloudscraper
scraper = cloudscraper.create_scraper()

# Maximum number of retries
MAX_RETRIES = 5
RETRY_DELAY = 3
YEAR_GUARD = 2025

def fetch_and_download_exam_schedule_pdfs():
    announcements_file = DATA_DIR / "announcements.json"
    if not announcements_file.exists():
        return

    try:
        with open(announcements_file, "r", encoding="utf-8") as f:
            results = json.load(f)

        for row in results:
            title = row.get("title")
            message = row.get("message", "")
            published_date = row.get("published_date")
            is_fyat_notice = is_fyat_title(title)
            published_year = None
            if published_date:
                try:
                    published_year = int(str(published_date)[:4])
                except Exception:
                    published_year = None

            if (
                published_year is not None
                and published_year < YEAR_GUARD
                and not is_fyat_notice
            ):
                continue

            # Determine folder name from title
            title_year = extract_year_from_title(title)
            if is_fyat_notice:
                if title_year is not None and title_year < YEAR_GUARD:
                    continue
                folder_name = "FYAT"
            elif title_year is not None and title_year < YEAR_GUARD:
                continue
            else:
                folder_name = get_folder_name_from_title(title)
            if not is_fyat_notice and not folder_name.startswith(("Final ", "Mid ")):
                continue

            full_folder_path = PDF_DIR / folder_name
            full_folder_path.mkdir(parents=True, exist_ok=True)

            if "Embedded Page Links:" in message:
                content_after = message.split("Embedded Page Links:", 1)[1].strip()
                urls = [url.strip() for url in content_after.splitlines() if url.strip()]
                for url in urls:
                    download_pdf_with_retry(url, full_folder_path)
            else:
                print(f"No Embedded Page Links found in message: {title}")

    except Exception as err:
        print(f"Error: {err}")

def get_folder_name_from_title(title):
    # Detect exam type
    title_lower = title.lower()
    if "final" in title_lower:
        exam_type = "Final"
    elif "mid" in title_lower:
        exam_type = "Mid"
    else:
        exam_type = "Other"

    # Detect semester and year
    match = re.search(r"(Spring|Fall|Summer)\s+\d{4}", title, re.IGNORECASE)
    semester = match.group(0) if match else "Unknown Semester"

    return f"{exam_type} {semester}".strip()


def extract_year_from_title(title):
    match = re.search(r"\b(20\d{2})\b", title or "")
    return int(match.group(1)) if match else None


def is_fyat_title(title):
    normalized = re.sub(r"[^a-z0-9]+", " ", (title or "").lower()).strip()
    return bool(re.search(r"\bfyat\b", normalized))

def download_pdf_with_retry(url, folder_path):
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = scraper.get(url)
            if response.status_code == 404:
                print(f"404 Not Found: {url}, skipping download.")
                break  # do not retry on 404
            response.raise_for_status()  # raise exception for other bad status
            content_type = response.headers.get("content-type", "").lower()
            if "text/html" in content_type or response.text.lstrip().startswith("<html"):
                print(f"Skipping HTML response for {url}")
                break

            parsed_url = urlparse(url)
            filename = folder_path / Path(parsed_url.path).name
            with open(filename, "wb") as f:
                f.write(response.content)
            print(f"Downloaded: {filename}")
            break  # success, exit loop
        except Exception as e:
            # Only retry if it's not a 404
            if "404" in str(e):
                print(f"404 Error encountered, skipping: {url}")
                break
            if attempt < MAX_RETRIES:
                print(f"Attempt {attempt} failed for {url}: {e}")
                print(f"Retrying in {RETRY_DELAY} seconds...")
                time.sleep(RETRY_DELAY)
            else:
                print(f"Failed to download {url} after {MAX_RETRIES} attempts.")

if __name__ == "__main__":
    fetch_and_download_exam_schedule_pdfs()
