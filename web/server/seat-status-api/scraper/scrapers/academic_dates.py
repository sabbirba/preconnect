import time
import cloudscraper
from bs4 import BeautifulSoup
import json
from datetime import datetime
from pathlib import Path
from json_store import load_rows, save_rows as save_json_rows

DATA_DIR = Path("data")
DATA_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_FILE = DATA_DIR / "academic_dates.json"
YEAR_GUARD = 2025

# RSS configuration
base_url = "https://www.bracu.ac.bd/academic/{semester}/{year}/rss.xml"
semesters = ["spring", "summer", "fall"]
end_year = 2014
max_retries = 10
retry_delay = 5

# Determine the current year dynamically.
current_year = datetime.now().year

# Initialize scraper
scraper = cloudscraper.create_scraper()

rows = []


def load_existing_rows():
    return load_rows(OUTPUT_FILE)


rows = load_existing_rows()


def save_rows():
    save_json_rows(
        OUTPUT_FILE,
        rows,
        lambda row: (
            row.get("event_name"),
            row.get("start_date"),
            row.get("end_date"),
        ) if row.get("event_name") and row.get("start_date") and row.get("end_date") else None,
    )

def parse_date(date_str):
    """Parse date using the exact format from the RSS feed."""
    try:
        return datetime.strptime(date_str, "%d/%m/%Y - %H:%M").date()
    except (ValueError, TypeError):
        return None

for year in range(current_year, end_year - 1, -1):  # current year down to 2010
    if year < YEAR_GUARD:
        print(f"Reached year guard {YEAR_GUARD}, stopping academic dates scrape.")
        break

    for semester in semesters:
        url = base_url.format(semester=semester, year=year)
        print(f"Fetching RSS for {semester.capitalize()} {year}: {url}")
        for attempt in range(1, max_retries + 1):
            try:
                response = scraper.get(url)
                if response.status_code == 403:
                    print(f"Attempt {attempt}: 403 Forbidden, retrying in {retry_delay}s...")
                    time.sleep(retry_delay)
                    continue

                response.raise_for_status()
                soup = BeautifulSoup(response.text, "xml")

                for event in soup.find_all("event"):
                    event_name = event.title.text.strip() if event.title else "N/A"
                    start_date_str = event.find("start-date").text.strip() if event.find("start-date") else None
                    end_date_str = event.find("end-date").text.strip() if event.find("end-date") else None

                    start_date = parse_date(start_date_str)
                    end_date = parse_date(end_date_str)

                    if start_date and end_date:
                        rows.append(
                            {
                                "event_name": event_name,
                                "start_date": start_date.isoformat(),
                                "end_date": end_date.isoformat(),
                            }
                        )
                        save_rows()

                break  # exit retry loop if successful

            except Exception as e:
                print(f"Attempt {attempt}: Error - {e}, retrying in {retry_delay}s...")
                time.sleep(retry_delay)

save_rows()
