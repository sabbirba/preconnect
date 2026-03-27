import cloudscraper
from bs4 import BeautifulSoup
from datetime import datetime
import json
from pathlib import Path
from json_store import load_rows, save_rows as save_json_rows

url = "https://www.bracu.ac.bd/students-transport-service"
DATA_DIR = Path("data")
DATA_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_FILE = DATA_DIR / "transport.json"
rows = []


def load_existing_rows():
    return load_rows(OUTPUT_FILE)


rows = load_existing_rows()


def save_rows():
    save_json_rows(
        OUTPUT_FILE,
        rows,
        lambda row: (
            row.get("route_name"),
            row.get("stoppage"),
            row.get("first_pickup_time"),
            row.get("second_pickup_time"),
            row.get("first_dropoff_time"),
            row.get("second_dropoff_time"),
            row.get("phone_no"),
        ) if row.get("route_name") and row.get("stoppage") else None,
    )

# === SCRAPE PAGE ===
scraper = cloudscraper.create_scraper(delay=2)
response = scraper.get(url)
if response.status_code != 200:
    print(f"Failed to fetch page: {response.status_code}")
    exit()

soup = BeautifulSoup(response.text, "html.parser")

# === GET ROUTE CONTACT INFO ===
columns = soup.select("div.columns.medium-6.small-12")
route_phone_numbers = []
for col in columns:
    items = col.select("ul li")
    for li in items:
        strong = li.find("strong")
        phone_no = li.get_text(strip=True).replace(strong.get_text(strip=True), "").strip()
        route_phone_numbers.append(phone_no)

# === GET DROP OFF TIMINGS ===
divs = soup.select("div.block-content.content")
if len(divs) < 3:
    print("Less than 3 block-content divs found")
    exit()

third_div = divs[2]
accordion_items = third_div.select("li.accordion-item")
if len(accordion_items) < 3:
    print("Transport page format changed; not enough accordion items.")
    exit()

# The last two accordion items are drop-off timings.
first_dropoff_times_text = accordion_items[-2].select_one("div.accordion-content").get_text(separator="\n", strip=True)
second_dropoff_times_text = accordion_items[-1].select_one("div.accordion-content").get_text(separator="\n", strip=True)

# Parse drop-off timings into a dict: route_no -> time
def parse_dropoff_lines(text):
    timings = {}
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    i = 0
    while i < len(lines) - 1:  # at least 2 lines needed
        route_info = lines[i]
        # If ':' not in route_info, join with next line(s)
        while ":" not in route_info and i+1 < len(lines)-1:
            i += 1
            route_info += " " + lines[i]
        # Next line is time
        time_str = lines[i+1]
        try:
            time_obj = datetime.strptime(time_str, "%I:%M %p").time()
            # Extract destination between "to" and ":"
            if "to" in route_info and ":" in route_info:
                start = route_info.index("to") + 3
                end = route_info.index(":")
                destination = route_info[start:end].strip()
                timings[destination] = time_obj
        except:
            pass
        i += 2  # move to next pair
    return timings

first_dropoff_times = parse_dropoff_lines(first_dropoff_times_text)
print(first_dropoff_times)
second_dropoff_times = parse_dropoff_lines(second_dropoff_times_text)
print(second_dropoff_times)
rows = []

# === INSERT ROUTE DATA ===
for index, item in enumerate(accordion_items[:-2]):
    title_tag = item.select_one("a.accordion-title")
    route_name = title_tag.get_text(strip=True) if title_tag else "No title"
    
    # Extract route number from route_name
    body_tag = item.select_one("div.accordion-content")
    if not body_tag:
        continue

    # Remove all <tr> that contain <strong> tags
    # SO this remove the headings
    for tr in body_tag.select("tr"):
        if tr.find("strong"):
            tr.decompose()  # remove from the DOM


    # Filter body lines
    # body_lines = [line for line in body_tag.get_text(separator="\n", strip=True).splitlines() if not any(sub in line for sub in ignore_substrings)]
    # body_lines = [line for line in body_tag.get_text(separator="\n", strip=True).splitlines()]
    # body_lines = body_tag.get_text(separator="\n", strip=True).splitlines()[7:]
    body_lines = body_tag.get_text(separator="\n", strip=True).splitlines()

    # Process stoppages in chunks of 3 (stoppage, first pickup, second pickup).
    # Advance carefully so we still handle cases with only one pickup time.
    i = 0
    while i < len(body_lines):
        stoppage = body_lines[i]
        i += 1
        try:
            first_pickup = datetime.strptime(body_lines[i], "%I:%M %p").time()
            i += 1
        except:
            first_pickup = None
        try:
            second_pickup = datetime.strptime(body_lines[i], "%I:%M %p").time()
            i+= 1
        except:
            second_pickup = None

        # Find destination substring in route name
        first_dropoff = None
        second_dropoff = None
        for destination, time in first_dropoff_times.items():
            if destination in route_name:  # substring match
                first_dropoff = time
                break

        for destination, time in second_dropoff_times.items():
            if destination in route_name:
                second_dropoff = time
                break



        phone_no = route_phone_numbers[index] if index < len(route_phone_numbers) else None

        rows.append(
            {
                "route_name": route_name,
                "stoppage": stoppage,
                "first_pickup_time": first_pickup.isoformat() if first_pickup else None,
                "second_pickup_time": second_pickup.isoformat() if second_pickup else None,
                "first_dropoff_time": first_dropoff.isoformat() if first_dropoff else None,
                "second_dropoff_time": second_dropoff.isoformat() if second_dropoff else None,
                "phone_no": phone_no,
            }
        )
        save_rows()

save_rows()
print("Data inserted successfully.")
