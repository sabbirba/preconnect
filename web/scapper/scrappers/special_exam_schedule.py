import os
from pathlib import Path

import pdfplumber
from scrappers.shared import MIN_EXAM_YEAR, is_allowed_exam_folder, parse_date_to_iso, parse_time_range_12h, save_json_list


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / 'data'
OUT_FILE = DATA_DIR / 'exam_schedule.json'
BASE_FOLDER = BASE_DIR / 'exam schedule pdfs'
def parse_date(date_str):
    return parse_date_to_iso(
        date_str,
        ('%d-%b-%y', '%Y-%m-%d', '%d/%m/%Y', '%m/%d/%Y', '%d %B %Y'),
    )


def parse_time_range(time_str):
    return parse_time_range_12h(time_str)


existing = []

for root, _, files in os.walk(BASE_FOLDER):
    folder_name = os.path.basename(root).strip()
    if folder_name and not is_allowed_exam_folder(folder_name, min_year=MIN_EXAM_YEAR):
        continue
    for filename in files:
        if not filename.lower().endswith('.pdf'):
            continue
        if any(sub in filename.lower() for sub in ['mid', 'final', 'exam', 'schedule']):
            continue
        pdf_path = os.path.join(root, filename)
        course_code = filename[:6]
        exam_type = os.path.basename(root) or 'N/A'
        try:
            with pdfplumber.open(pdf_path) as pdf:
                for page in pdf.pages:
                    tables = page.extract_tables()
                    if not tables:
                        continue
                    table = tables[0]
                    header_idx = -1
                    header_map = {}
                    for idx in range(min(5, len(table))):
                        row = table[idx]
                        if not row:
                            continue
                        if any('schedule' in str(c).lower() for c in row):
                            continue
                        if any('sl' in str(c).lower() for c in row):
                            header_idx = idx
                            header_map = {col.lower().strip(): col_idx for col_idx, col in enumerate(row) if col}
                            break
                    start_row = header_idx + 1
                    for row in table[start_row:]:
                        if not row:
                            continue
                        def safe_get(key):
                            key_lower = key.lower()
                            idx = next((i for k, i in header_map.items() if key_lower in k), None)
                            return row[idx].strip() if idx is not None and row[idx] else 'N/A'
                        student_id = safe_get('id')
                        section = safe_get('section')
                        date_str = safe_get('date')
                        time_str = safe_get('time')
                        room = safe_get('room')
                        start_time, end_time = parse_time_range(time_str)
                        exam_date = parse_date(date_str) or '1900-01-01'
                        if int(exam_date[:4]) < MIN_EXAM_YEAR:
                            continue
                        existing.append(
                            {
                                'type': exam_type,
                                'course_code': course_code,
                                'section': section,
                                'date': exam_date,
                                'start_time': start_time or '00:00:00',
                                'end_time': end_time or '00:00:00',
                                'room_no': room,
                                'dept': 'N/A',
                                'student_id': student_id,
                            }
                        )
        except Exception as e:
            print(f'Error processing {pdf_path}: {e}')

save_json_list(OUT_FILE, existing)
