import re
from pathlib import Path

from scrappers.shared import content_to_text, fetch_page_with_fallback, load_json_list, save_json_list


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / 'data'
OUT_FILE = DATA_DIR / 'contact_info.json'
PAGE_URL = 'https://www.bracu.ac.bd/contact'
fetched = fetch_page_with_fallback(PAGE_URL, timeout=30)
content = fetched.get('content', '')
existing = load_json_list(OUT_FILE)

if not content:
    save_json_list(OUT_FILE, existing)
    print('Less than 3 blocks found')
    raise SystemExit(0)

text = content_to_text(content, source=fetched.get('source', 'direct_html'))
address = re.search(r'Address\s*:?\s*(.+)', text, re.I)
phone = re.search(r'(?:Tel|Phone)\s*:?\s*(.+)', text, re.I)
email = re.search(r'([\w.+-]+@[\w.-]+\.[A-Za-z]{2,})', text)
contact_block = []
if address:
    contact_block.append(address.group(1).strip())
if phone:
    contact_block.append(phone.group(1).strip())
if email:
    contact_block.append(email.group(1).strip())

if contact_block:
    existing = [
        {
            'name': 'Contact Us',
            'emails': [email.group(1).strip().lower()] if email else [],
            'hours': None,
            'phone_no': [phone.group(1).strip()] if phone else [],
            'address': address.group(1).strip() if address else None,
        }
    ]

save_json_list(OUT_FILE, existing)
