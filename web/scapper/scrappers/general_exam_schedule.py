import os
from datetime import datetime
from pathlib import Path

import pdfplumber
from scrappers.shared import MIN_EXAM_YEAR, is_allowed_exam_folder, parse_date_to_iso, save_json_list


BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / 'data'
OUT_FILE = DATA_DIR / 'exam_schedule.json'
BASE_FOLDER = BASE_DIR / 'exam schedule pdfs'
def get_col_index(headers, keyword):
    for idx, h in enumerate(headers):
        if keyword.lower() in str(h).lower():
            return idx
    return None


def parse_date(date_str):
    if not date_str or date_str == 'N/A':
        return None
    return parse_date_to_iso(
        date_str,
        ('%Y-%m-%d', '%d-%b-%y', '%d-%b-%Y', '%d %B %Y', '%m/%d/%Y'),
    )


existing = []

for root, _, files in os.walk(BASE_FOLDER):
    folder_name = os.path.basename(root).strip()
    if folder_name and not is_allowed_exam_folder(folder_name, min_year=MIN_EXAM_YEAR):
        continue
    for file in files:
        if file.lower().endswith('.pdf') and any(
            sub in file.lower() for sub in ['mid', 'final', 'exam', 'schedule']
        ):
            pdf_path = os.path.join(root, file)
            exam_type = os.path.basename(root) or 'N/A'
            student_id = 'N/A'
            try:
                with pdfplumber.open(pdf_path) as pdf:
                    for page in pdf.pages:
                        tables = page.extract_tables()
                        if not tables:
                            continue
                        table = tables[0]
                        header_index = -1
                        for idx, row in enumerate(table):
                            if row and any('course' in str(c).lower() for c in row):
                                header_index = idx
                                break
                        headers = table[header_index]
                        data_rows = table[header_index + 1 :]
                        for row in data_rows:
                            if not row or all(cell is None for cell in row):
                                continue
                            c_idx = get_col_index(headers, 'course')
                            s_idx = get_col_index(headers, 'section')
                            d_idx = get_col_index(headers, 'date')
                            st_idx = get_col_index(headers, 'start time')
                            e_idx = get_col_index(headers, 'end time')
                            r_idx = get_col_index(headers, 'room')
                            dept_idx = get_col_index(headers, 'dept')
                            start_time = row[st_idx] if st_idx is not None else None
                            end_time = row[e_idx] if e_idx is not None else None
                            try:
                                start_time = datetime.strptime(start_time.strip(), '%I:%M %p').time().isoformat()
                            except Exception:
                                start_time = None
                            try:
                                end_time = datetime.strptime(end_time.strip(), '%I:%M %p').time().isoformat()
                            except Exception:
                                end_time = None
                            exam_date = parse_date(row[d_idx] if d_idx is not None else None)
                            if not exam_date or int(exam_date[:4]) < MIN_EXAM_YEAR:
                                continue
                            existing.append(
                                {
                                    'type': exam_type,
                                    'course_code': row[c_idx] if c_idx is not None else 'N/A',
                                    'section': row[s_idx] if s_idx is not None else 'N/A',
                                    'date': exam_date,
                                    'start_time': start_time,
                                    'end_time': end_time,
                                    'room_no': row[r_idx] if r_idx is not None else 'N/A',
                                    'dept': row[dept_idx] if dept_idx is not None else 'N/A',
                                    'student_id': student_id,
                                }
                            )
            except Exception as e:
                print(f'Error processing {pdf_path}: {e}')

save_json_list(OUT_FILE, existing)
