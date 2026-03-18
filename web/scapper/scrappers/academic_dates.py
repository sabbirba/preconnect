import re
from datetime import datetime
from pathlib import Path

from bs4 import BeautifulSoup

from scrappers.shared import fetch_page_with_fallback, load_json_list, parse_date_to_iso, save_json_list


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / 'data'
OUT_FILE = DATA_DIR / 'academic_dates.json'
PAGE_URL = 'https://www.bracu.ac.bd/academic-dates'


def parse_date(date_str):
    return parse_date_to_iso(
        date_str,
        ('%d/%m/%Y', '%d/%m/%Y - %H:%M', '%d %b, %Y', '%d %B, %Y'),
        strip_ordinal=True,
    )
fetched = fetch_page_with_fallback(PAGE_URL, timeout=30)
content = fetched.get('content', '')
existing = load_json_list(OUT_FILE)
dedup = {
    (item.get('semester'), item.get('year'), item.get('event_name'), item.get('start_date'), item.get('end_date'))
    for item in existing
}

if not content:
    save_json_list(OUT_FILE, existing)
    print('Failed to fetch academic dates page')
    raise SystemExit(0)

rows = []
if fetched.get('source') == 'jina':
    rows = re.findall(r'\| ([^|]+) \| ([^|]+) \| ([^|]+) \|', content)
else:
    soup = BeautifulSoup(content, 'html.parser')
    for tr in soup.select('table tr'):
        cells = [c.get_text(' ', strip=True) for c in tr.find_all(['th', 'td'])]
        if len(cells) >= 3:
            rows.append((cells[0], cells[1], cells[2]))

for date_text, day_text, event_name in rows:
    if date_text.strip().lower() == 'date':
        continue
    semester_match = re.search(r'(Spring|Summer|Fall)\s+(\d{4})', event_name, re.I) or re.search(r'(Spring|Summer|Fall)\s+(\d{4})', date_text, re.I)
    if semester_match:
        semester = semester_match.group(1).lower()
        year = int(semester_match.group(2))
    else:
        semester = 'unknown'
        year = datetime.now().year

    start_text = date_text.split(' to ', 1)[0].strip()
    end_text = date_text.split(' to ', 1)[1].strip() if ' to ' in date_text else start_text
    start_date = parse_date(start_text)
    end_date = parse_date(end_text)
    if not start_date or not end_date:
        continue
    row = {
        'semester': semester,
        'year': year,
        'event_name': f'{day_text} {event_name}'.strip(),
        'start_date': start_date,
        'end_date': end_date,
    }
    key = (semester, year, row['event_name'], start_date, end_date)
    if key in dedup:
        continue
    existing.append(row)
    dedup.add(key)

save_json_list(OUT_FILE, existing)
print('Done writing academic dates JSON.')
