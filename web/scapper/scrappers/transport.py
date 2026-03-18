import re
from pathlib import Path

from scrappers.shared import content_to_text, extract_links_from_content, fetch_page_with_fallback, load_json_list, save_json_list


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / 'data'
OUT_FILE = DATA_DIR / 'transport.json'
PAGE_URL = 'https://www.bracu.ac.bd/students-transport-service'
fetched = fetch_page_with_fallback(PAGE_URL, timeout=30)
content = fetched.get('content', '')
existing = load_json_list(OUT_FILE)

if not content:
    save_json_list(OUT_FILE, existing)
    print('Failed to fetch page')
    raise SystemExit(0)

schedule_url = None
for link in extract_links_from_content(content, PAGE_URL):
    if 'schedule' in link.lower() and 'transport' in link.lower():
        schedule_url = link
        break

text = content_to_text(content, source=fetched.get('source', 'direct_html'))
address = re.search(r'Address\s*:?\s*(.+)', text, re.I)
phone = re.search(r'(?:Tel|Phone)\s*:?\s*(.+)', text, re.I)
email = re.search(r'([\w.+-]+@[\w.-]+\.[A-Za-z]{2,})', text)

existing = [
    {
        'route_name': 'Transport Service',
        'stoppage': 'See transport schedule',
        'first_pickup_time': None,
        'second_pickup_time': None,
        'first_dropoff_time': None,
        'second_dropoff_time': None,
        'phone_no': phone.group(1).strip() if phone else None,
        'schedule_url': schedule_url,
        'address': address.group(1).strip() if address else None,
        'email': email.group(1).strip().lower() if email else None,
    }
]

save_json_list(OUT_FILE, existing)
