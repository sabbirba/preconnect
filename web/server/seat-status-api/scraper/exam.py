import sys
import json
import re
import time
from datetime import datetime
import pdfplumber
import logging
import platform

print("\033[96m" + "="*70)
print("  ______  __   __    _    __  __ ")
print(" |  ____| \\ \\ / /   / \\  |  \\/  |")
print(" | |__     \\ V /   / _ \\ | \\  / |")
print(" |  __|     > <   / ___ \\| |\\/| |")
print(" | |____   / . \\ / /   \\ \\ |  | |")
print(" |______| /_/ \\_\\_/     \\_\\_|  |_|")
print(" ")
print("\033[92mContains exam schedules extracted from BRAC University PDF files.\033[0m")
print("By            \033[93mSabbir Bin Abbas\033[96m")
print("Email:        sabbir.bin.abbas@g.bracu.ac.bd")
print("GitHub:       https://github.com/sabbirba")
print("Social links: https://sabbirba.github.io")
print("="*70 + "\033[0m")
print(" ")
print("\033[93mProcessing...\033[0m")
import os
script_dir = os.path.dirname(os.path.abspath(__file__))
logfile = os.path.join(script_dir, "exam.log")
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    handlers=[
        logging.FileHandler(logfile, mode='w', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
def log(msg):
    logging.info(msg)

def clean_text(text):
    if text is None:
        return None
    return re.sub(r'\s+', ' ', text).strip()

def standardize_date(date_str):
    if not date_str or not isinstance(date_str, str):
        return date_str
    try:
        dt = datetime.strptime(date_str.strip(), "%d-%b-%y")
        return dt.strftime("%Y-%m-%d")
    except ValueError:
        return date_str

def standardize_time(time_str):
    if not time_str or not isinstance(time_str, str):
        return time_str
    try:
        dt = datetime.strptime(time_str.strip(), "%I:%M %p")
        return dt.strftime("%H:%M")
    except ValueError:
        return time_str

def bil_standardize_date(date_str):
    if not date_str or not isinstance(date_str, str):
        return date_str
    for fmt in ("%d-%b-%y", "%d/%m/%Y", "%Y-%m-%d"):
        try:
            dt = datetime.strptime(date_str.strip(), fmt)
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            continue
    return date_str

def extract_times(time_str):
    if not time_str or not isinstance(time_str, str):
        return None, None
    time_str = time_str.replace('–', '-').replace('—', '-').replace('−', '-')
    time_str = re.sub(r'\s*-\s*', '-', time_str)
    matches = re.findall(r'(\d{1,2}:\d{2}\s*[APMapm]{2})', time_str)
    if len(matches) >= 2:
        return matches[0].replace(' ', '').upper(), matches[-1].replace(' ', '').upper()
    elif len(matches) == 1:
        return matches[0].replace(' ', '').upper(), ""
    return "", ""

def bil_standardize_time(time_str):
    if not time_str or not isinstance(time_str, str):
        return ""
    time_str = time_str.strip().upper().replace(' ', '')
    for fmt in ("%I:%M%p", "%I:%M %p", "%H:%M"):
        try:
            dt = datetime.strptime(time_str, fmt)
            return dt.strftime("%H:%M")
        except ValueError:
            continue
    return ""

def is_valid_entry(entry, exam_type):
    required_fields = ["Course", "Section"]
    if exam_type == "Mid":
        required_fields.append("Mid Date")
    else:
        required_fields.append("Final Date")
    return all(field in entry and entry[field] for field in required_fields)

def bil_is_valid_entry(entry, exam_type):
    required_fields = ["Course", "Section", "Start Time", "End Time", "Room."]
    if exam_type == "Mid":
        required_fields.append("Mid Date")
    else:
        required_fields.append("Final Date")
    return all(field in entry and entry[field] for field in required_fields)

def is_header_row(row, headers):
    if not row:
        return False
    header_texts = ['course', 'section', 'date', 'time', 'room', 'dept']
    row_text = ' '.join(str(cell).lower() for cell in row if cell)
    return any(text in row_text for text in header_texts)

def extract_course_codes_per_page(page_data):
    course_codes_per_page = []
    last_code = None
    for pdata in page_data:
        match = re.search(r"SCHEDULE\s*:\s*([A-Z0-9]+)", pdata["text"])
        if match:
            last_code = match.group(1)
        course_codes_per_page.append(last_code)
    return course_codes_per_page

def extract_general_entries(page_data, exam_type):
    all_entries = []
    global_headers = []
    first_tables = page_data[0]["tables"]
    if first_tables and len(first_tables) > 0 and len(first_tables[0]) > 0:
        headers = [clean_text(cell) if cell else "" for cell in first_tables[0][0]]
        for header in headers:
            if not header:
                global_headers.append("")
                continue
            if "course" in header.lower():
                global_headers.append("Course")
            elif "section" in header.lower() or "sec" in header.lower():
                global_headers.append("Section")
            elif "date" in header.lower():
                if exam_type == "Mid":
                    global_headers.append("Mid Date")
                else:
                    global_headers.append("Final Date")
            elif "start" in header.lower() or "from" in header.lower():
                global_headers.append("Start Time")
            elif "end" in header.lower() or "to" in header.lower():
                global_headers.append("End Time")
            elif "room" in header.lower():
                global_headers.append("Room.")
            elif "dept" in header.lower():
                global_headers.append("Dept.")
            elif "sl" in header.lower() or "serial" in header.lower() or "#" in header:
                global_headers.append("SL.")
            else:
                global_headers.append(header)
    else:
        if exam_type == "Mid":
            global_headers = ["Course", "Section", "Mid Date", "Start Time", "End Time", "Room.", "Dept."]
        else:
            global_headers = ["Course", "Section", "Final Date", "Start Time", "End Time", "Room.", "Dept."]

    for page_num, pdata in enumerate(page_data, 1):
        tables = pdata["tables"]
        page_text = pdata["text"]
        words = pdata["words"]
        text_lines = page_text.splitlines()
        if tables:
            for table_idx, table in enumerate(tables):
                if not table:
                    continue
                for row_idx, row in enumerate(table):
                    if row == table[0]:
                        continue
                    if not row or all(cell is None or (isinstance(cell, str) and cell.strip() == "") for cell in row):
                        continue
                    if is_header_row(row, global_headers):
                        continue
                    entry = {}
                    for i, cell in enumerate(row):
                        if i < len(global_headers) and cell and global_headers[i]:
                            value = clean_text(cell)
                            if value:
                                entry[global_headers[i]] = value
                    row_text = ' '.join([v for v in (clean_text(str(cell)) for cell in row if cell and str(cell).strip()) if v])
                    entry["RowText"] = row_text
                    try:
                        sl_cell = None
                        if len(row) > 0 and row[0] is not None:
                            sl_cell = clean_text(str(row[0]))
                        sl_index = -1
                        for i, header in enumerate(global_headers):
                            if header == "SL.":
                                sl_index = i
                                break
                        if sl_index >= 0 and sl_index < len(row) and row[sl_index] is not None:
                            sl_cell = clean_text(str(row[sl_index]))
                        matched_words = []
                        if sl_cell:
                            sl_matches = [w for w in words if clean_text(w.get('text', '')) == sl_cell]
                            if sl_matches:
                                matched_words = [sl_matches[0]]
                            else:
                                for cell in row:
                                    cell_text = clean_text(str(cell))
                                    if not cell_text:
                                        continue
                                    cell_matches = [w for w in words if clean_text(w.get('text', '')) == cell_text and w not in matched_words]
                                    if cell_matches:
                                        matched_words.append(cell_matches[0])
                                        break
                        if not matched_words:
                            for cell in row:
                                cell_text = clean_text(str(cell))
                                if not cell_text:
                                    continue
                                cell_matches = [w for w in words if clean_text(w.get('text', '')) == cell_text and w not in matched_words]
                                if cell_matches:
                                    matched_words.append(cell_matches[0])
                                    break
                        if matched_words:
                            standard_x0 = 89.664
                            standard_x1 = 506.66303999999997
                            y0 = float(matched_words[0]['top'])
                            y1 = float(matched_words[0]['bottom'])
                            entry["BoundingBox"] = {
                                "x0": standard_x0,
                                "y0": y0,
                                "x1": standard_x1,
                                "y1": y1
                            }
                        else:
                            base_y = 100 + (row_idx * 15)
                            entry["BoundingBox"] = {
                                "x0": 90.0,
                                "y0": base_y,
                                "x1": 500.0,
                                "y1": base_y + 10
                            }
                    except Exception as e:
                        base_y = 100 + (row_idx * 15)
                        entry["BoundingBox"] = {
                            "x0": 90.0,
                            "y0": base_y,
                            "x1": 500.0,
                            "y1": base_y + 10,
                            "error": str(e)
                        }
                    if exam_type == "Mid" and "Mid Date" in entry:
                        entry["Mid Date"] = standardize_date(entry["Mid Date"])
                    elif exam_type == "Final" and "Final Date" in entry:
                        entry["Final Date"] = standardize_date(entry["Final Date"])
                    if "Start Time" in entry:
                        entry["Start Time"] = standardize_time(entry["Start Time"])
                    if "End Time" in entry:
                        entry["End Time"] = standardize_time(entry["End Time"])
                    if "Section" in entry:
                        entry["Section"] = str(entry["Section"])
                    line_number_in_pdf = None
                    for idx, line in enumerate(text_lines, 1):
                        if entry.get("Course") and entry.get("Section"):
                            if entry["Course"] in line and entry["Section"] in line:
                                line_number_in_pdf = idx
                                break
                        def _norm(s):
                            return re.sub(r"\s+", "", str(s or "")).lower()

                        line_number_in_pdf = -1
                        course_norm = _norm(entry.get("Course"))
                        section_norm = _norm(entry.get("Section"))
                        rowtext_norm = _norm(entry.get("RowText"))

                        for idx, line in enumerate(text_lines, 1):
                            l = _norm(line)
                           
                            if course_norm and section_norm:
                                if course_norm in l and section_norm in l:
                                    line_number_in_pdf = idx
                                    break
                            if course_norm and course_norm in l:
                                line_number_in_pdf = idx
                                break
                            if rowtext_norm and rowtext_norm in l:
                                line_number_in_pdf = idx
                                break
                    entry["Page Number"] = page_num
                    entry["Line Number"] = line_number_in_pdf
                    if is_valid_entry(entry, exam_type) and len(str(entry.get("Course", ""))) <= 7:
                        all_entries.append(entry)
                        log(
                            f"Added Course: {entry.get('Course','')}, Section: {entry.get('Section','')}, "
                            f"{'Mid Date' if exam_type=='Mid' else 'Final Date'}: {entry.get('Mid Date','') if exam_type=='Mid' else entry.get('Final Date','')}, Room: {entry.get('Room.','')}, "
                            f"Dept: {entry.get('Dept.','')}, Start Time: {entry.get('Start Time','')}, "
                            f"End Time: {entry.get('End Time','')}, Page: {entry.get('Page Number','')}"
                        )
                    elif not is_valid_entry(entry, exam_type):
                        pass
                    elif len(str(entry.get("Course", ""))) >= 7:
                        pass
        else:
            pass
    log(f"Total valid entries extracted (General): {len(all_entries)}")
    return all_entries
def extract_bil_entries(page_data, exam_type):
    all_entries = []
    unique_entries = set()
    course_codes_per_page = extract_course_codes_per_page(page_data)
    for page_num, pdata in enumerate(page_data, 1):
        course_code = course_codes_per_page[page_num - 1]
        tables = pdata["tables"]
        page_text = pdata["text"]
        words = pdata["words"]
        text_lines = page_text.splitlines()
        if tables:
            for table_idx, table in enumerate(tables):
                if not table:
                    continue
                start_row = 1 if page_num == 1 else 0
                for row_idx, row in enumerate(table[start_row:]):
                    if not row or all(cell is None or (isinstance(cell, str) and cell.strip() == "") for cell in row):
                        continue
                    id_number = clean_text(row[1]) if len(row) > 1 else ""
                    section = clean_text(row[2]) if len(row) > 2 else ""
                    exam_date = clean_text(row[3]) if len(row) > 3 else ""
                    exam_time = clean_text(row[4]) if len(row) > 4 else ""
                    classroom = clean_text(row[5]) if len(row) > 5 else ""
                    if course_code and id_number:
                        course_field = f"{course_code} {id_number}"
                    else:
                        course_field = course_code
                    minimal_entry = {
                        "Course": course_field,
                        "Section": section,
                        "Room.": classroom,
                        "Dept.": "BIL"
                    }
                    start, end = extract_times(exam_time)
                    minimal_entry["Start Time"] = bil_standardize_time(start)
                    minimal_entry["End Time"] = bil_standardize_time(end)
                    row_text = ' '.join([v for v in (clean_text(str(cell)) for cell in row if cell and str(cell).strip()) if v])
                    minimal_entry["RowText"] = row_text
                    minimal_entry["Page Number"] = page_num 

                    if exam_type == "Mid":
                        minimal_entry["Mid Date"] = bil_standardize_date(exam_date)
                    else:
                        minimal_entry["Final Date"] = bil_standardize_date(exam_date)

                    line_number_in_pdf = -1
                    matched_line = ""
                    for idx, line in enumerate(text_lines, 1):
                        if id_number and id_number in line:
                            line_number_in_pdf = idx
                            matched_line = line
                            break
            
                        def _norm_id(s):
                            return re.sub(r"\s+", "", str(s or "")).lower()

                        line_number_in_pdf = -1
                        matched_line = ""
                        id_norm = _norm_id(id_number)
                        for idx, line in enumerate(text_lines, 1):
                            if id_norm and id_norm in _norm_id(line):
                                line_number_in_pdf = idx
                                matched_line = line
                                break
                
                        if line_number_in_pdf == -1 and id_number:
                            for idx, line in enumerate(text_lines, 1):
                                if id_number in line:
                                    line_number_in_pdf = idx
                                    matched_line = line
                                    break
                        minimal_entry["Line Number"] = line_number_in_pdf

                    bounding_box = None
                    if matched_line:
                        found_y0 = None
                        for w in words:
                            if id_number in w['text']:
                                found_y0 = w['top']
                                break
                        if found_y0 is not None:
                            line_words = [word for word in words if abs(word['top'] - found_y0) < 2]
                        else:
                            line_words = [w for w in words if id_number in w['text']]
                        if line_words:
                            bounding_box = {
                                "x0": min(w['x0'] for w in line_words),
                                "y0": min(w['top'] for w in line_words),
                                "x1": max(w['x1'] for w in line_words),
                                "y1": max(w['bottom'] for w in line_words)
                            }
                    if not bounding_box:
                        base_y = 100 + (row_idx * 15)
                        bounding_box = {
                            "x0": 90.0,
                            "y0": base_y,
                            "x1": 500.0,
                            "y1": base_y + 10
                        }
                    minimal_entry["BoundingBox"] = bounding_box
        
                    if exam_type == "Mid":
                        unique_key = (
                            minimal_entry.get("Course", ""),
                            minimal_entry.get("Section", ""),
                            minimal_entry.get("Mid Date", ""),
                            minimal_entry.get("Start Time", ""),
                            minimal_entry.get("End Time", ""),
                            minimal_entry.get("Room.", "")
                        )
                    else:
                        unique_key = (
                            minimal_entry.get("Course", ""),
                            minimal_entry.get("Section", ""),
                            minimal_entry.get("Final Date", ""),
                            minimal_entry.get("Start Time", ""),
                            minimal_entry.get("End Time", ""),
                            minimal_entry.get("Room.", "")
                        )
                    if bil_is_valid_entry(minimal_entry, exam_type) and unique_key not in unique_entries:
                        all_entries.append(minimal_entry)
                        unique_entries.add(unique_key)
                        log(
                            f"Added Course: {minimal_entry.get('Course','')}, Section: {minimal_entry.get('Section','')}, "
                            f"{'Mid Date' if exam_type=='Mid' else 'Final Date'}: {minimal_entry.get('Mid Date','') if exam_type=='Mid' else minimal_entry.get('Final Date','')}, Room: {minimal_entry.get('Room.','')}, "
                            f"Dept: {minimal_entry.get('Dept.','')}, Start Time: {minimal_entry.get('Start Time','')}, "
                            f"End Time: {minimal_entry.get('End Time','')}, Page: {minimal_entry.get('Page Number','')}"
                        )
                    elif not bil_is_valid_entry(minimal_entry, exam_type):
                        pass
                    elif unique_key in unique_entries:
                        log(f"Skipped: Duplicate Course entry (Course: {minimal_entry.get('Course','')}, Section: {minimal_entry.get('Section','')})")
        else:
            pass
    log(f"Total valid entries extracted (BIL): {len(all_entries)}")
    return all_entries

def merge_fields_description(*descs):
    merged = {}
    for d in descs:
        merged.update(d)
    return merged

def extract_exam_name(text):
    for line in text.splitlines():
        if "Exam Schedule" in line:
            return line.strip()
    for line in text.splitlines():
        if "Exam" in line:
            return line.strip()
    return ""

def main(pdf_path, json_path):
    start_time = time.time()
    general_fields_description = {
        "Course": "Course code",
        "Section": "Class section number",
        "Final Date": "Examination date (YYYY-MM-DD)",
        "Mid Date": "Examination date (YYYY-MM-DD)",
        "Start Time": "Exam start time (24-hour format)",
        "End Time": "Exam end time (24-hour format)",
        "Room.": "Examination room",
        "Dept.": "Department offering the course",
        "Page Number": "Page number from which the entry was extracted",
        "Line Number": "Line number from which the entry was extracted",
        "RowText": "Full concatenated text of the row as it appears in the PDF",
        "BoundingBox": "Coordinates of the row in the PDF (x0, y0, x1, y1)"
    }
    bil_fields_description = {
        "Course": "Course code",
        "Section": "Class section number",
        "Final Date": "Examination date (YYYY-MM-DD)",
        "Mid Date": "Examination date (YYYY-MM-DD)",
        "Start Time": "Exam start time (24-hour format, first in range)",
        "End Time": "Exam end time (24-hour format, last in range)",
        "Room.": "Examination room (Classroom)",
        "Dept.": "Department offering the course",
        "Page Number": "Page number from which the entry was extracted",
        "Line Number": "Line number from which the entry was extracted",
        "RowText": "Full concatenated text of the row as it appears in the PDF",
        "BoundingBox": "Coordinates of the row in the PDF (x0, y0, x1, y1)"
    }
    with pdfplumber.open(pdf_path) as pdf:
       
        first_page_text = pdf.pages[0].extract_text() or ""
        if "Mid" in first_page_text:
            exam_type = "Mid"
        elif "Final" in first_page_text:
            exam_type = "Final"
        else:
            exam_type = "Final" 

        exam_name = extract_exam_name(first_page_text)

        page_data = []
        for page in pdf.pages:
            page_data.append({
                "tables": page.extract_tables(),
                "text": page.extract_text() or "",
                "words": page.extract_words()
            })
        general_entries = extract_general_entries(page_data, exam_type)
        bil_entries = extract_bil_entries(page_data, exam_type)
    all_entries = general_entries + bil_entries
    fields_description = merge_fields_description(general_fields_description, bil_fields_description)
    now = datetime.now()
    output = {
        "banner": [
            "Contains exam schedules extracted from BRAC University exam PDF files.",
            "By            Sabbir Bin Abbas",
            "Email:        sabbir.bin.abbas@g.bracu.ac.bd",
            "GitHub:       https://github.com/sabbirba",
            "Social links: https://sabbirba.github.io",
        ],
        "metadata": {
            "source": "https://www.bracu.ac.bd/news-archive/announcements",
            "generated_at": now.strftime('%A, %Y-%m-%d %H:%M:%S.%f')[:-3],
            "total_entries": len(all_entries),
            "bracu_exam_name": exam_name,
            "fields_description": fields_description,
            "exam_type": exam_type
        },
        "exams": all_entries
    }
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    log(f"Total valid entries extracted from General: {len(general_entries)} and BIL: {len(bil_entries)}")
    log(f"Successfully wrote and merged General and BIL entries to {json_path}: {len(all_entries)}")
    elapsed = time.time() - start_time
    log(f"Total time taken to successfully run the script: {elapsed:.2f} seconds")
    now = datetime.now()
    log(
        f"Script execution time: {now.strftime('%A, %Y-%m-%d %H:%M:%S')} "
        f"on {platform.system()} {platform.release()} ({platform.machine()}) | "
        f"Python: {platform.python_version()} | Node: {platform.node()}"
    )

if __name__ == "__main__":
    if len(sys.argv) < 3:
        log("Usage: python3 exam.py input.pdf output.json")
        sys.exit(1)
    pdf_path = sys.argv[1]
    json_path = sys.argv[2]
    main(pdf_path, json_path)