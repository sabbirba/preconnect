import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import pdfplumber


BASE_DIR = Path(__file__).resolve().parent.parent
FYAT_DIR = BASE_DIR / "pdf" / "FYAT"
OUTPUT_FILE = FYAT_DIR / "students.json"


def clean_text(text):
    if text is None:
        return ""
    return re.sub(r"\s+", " ", str(text)).strip()


def extract_students(pdf_path, json_path, students=None, seen_ids=None):
    students = students if students is not None else []
    seen_ids = seen_ids if seen_ids is not None else set()
    now = datetime.now()
    month = now.month
    year = now.year
    if 1 <= month <= 5:
        present_semester = "Spring"
    elif 6 <= month <= 9:
        present_semester = "Summer"
    else:
        present_semester = "Fall"
    present_semester_full = f"{present_semester} {year}"

    dept_map = {
        "ANNT": "ANT",
        "ANT": "ANT",
        "APE": "APE",
        "APPE": "APE",
        "ARC": "ARC",
        "ARRC": "ARC",
        "BBA": "BBA",
        "BBBA": "BBA",
        "BBIO": "BIO",
        "BBS": "BBA",
        "BIIO": "BIO",
        "BIN": "BIO",
        "BIO": "BIO",
        "CCO": "ECO",
        "ECCO": "ECO",
        "ECO": "ECO",
        "CCS": "CS",
        "CSS": "CS",
        "SS": "CS",
        "CS": "CS",
        "CCSE": "CSE",
        "CSE": "CSE",
        "CSEE": "CSE",
        "CSSE": "CSE",
        "KHAN": "CSE",
        "ROYY": "CSE",
        "SSE": "CSE",
        "ECE": "ECE",
        "EECE": "ECE",
        "EEE": "EEE",
        "EEEE": "EEE",
        "EENH": "ENG",
        "ENG": "ENG",
        "ENH": "ENG",
        "ENHH": "ENG",
        "ESS": "ENG",
        "HHY": "PHY",
        "PHHY": "PHY",
        "PHY": "PHY",
        "IIC": "MIC",
        "MIC": "MIC",
        "MIIC": "MIC",
        "MMIC": "MIC",
        "MNS": "MIC",
        "IIO": "BIO",
        "LLB": "LLB",
        "LLLB": "LLB",
        "SOL": "LLB",
        "MAAT": "MAT",
        "MAT": "MAT",
        "PHR": "PHR",
        "SAFI": "CSE",
    }

    def normalize_dept(dept):
        d = clean_text(dept).strip().upper()
        return dept_map.get(d, d)

    def compute_semester_number(admit_semester, present_semester, dept_code):
        if not admit_semester or not present_semester:
            return None

        def parse_sem(s):
            parts = str(s).strip().split()
            if len(parts) < 2:
                return None
            season = parts[0].capitalize()
            year_part = parts[1]
            if len(year_part) == 2 and year_part.isdigit():
                year_part = "20" + year_part if int(year_part) < 50 else "19" + year_part
            try:
                y = int(year_part)
            except Exception:
                return None
            return (y, season)

        parsed_start = parse_sem(admit_semester)
        parsed_end = parse_sem(present_semester)
        if not parsed_start or not parsed_end:
            return None

        start_year, start_season = parsed_start
        end_year, end_season = parsed_end
        global_order = ["Spring", "Summer", "Fall"]
        dept_seasons = {
            "LLB": ["Spring", "Fall"],
            "PHR": ["Spring", "Summer"],
        }
        available = dept_seasons.get(dept_code, global_order)

        def le(a, b):
            ay, aseason = a
            by, bseason = b
            try:
                ai = global_order.index(aseason)
                bi = global_order.index(bseason)
            except ValueError:
                return False
            return (ay < by) or (ay == by and ai <= bi)

        if not le((start_year, start_season), (end_year, end_season)):
            return 0

        count = 0
        cur_year, cur_season = start_year, start_season
        while True:
            if cur_season in available:
                count += 1
            if cur_year == end_year and cur_season == end_season:
                break
            idx = global_order.index(cur_season)
            idx = (idx + 1) % len(global_order)
            if idx == 0:
                cur_year += 1
            cur_season = global_order[idx]
        return count

    def adjust_present_semester(present_semester, dept_code):
        if not present_semester:
            return present_semester
        global_order = ["Spring", "Summer", "Fall"]
        dept_seasons = {
            "LLB": ["Spring", "Fall"],
            "PHR": ["Spring", "Summer"],
        }
        available = dept_seasons.get(dept_code, global_order)

        parts = str(present_semester).strip().split()
        if len(parts) < 2:
            return present_semester
        season = parts[0].capitalize()
        try:
            sem_year = int(parts[1])
        except Exception:
            return present_semester

        if season in available:
            return f"{season} {sem_year}"

        try:
            orig_idx = global_order.index(season)
        except ValueError:
            return present_semester

        idx = orig_idx
        for _ in range(len(global_order)):
            idx = (idx - 1) % len(global_order)
            prev_season = global_order[idx]
            if prev_season in available:
                adj_year = sem_year - 1 if idx > orig_idx else sem_year
                return f"{prev_season} {adj_year}"
        return present_semester

    valid_depts = {
        "ANT",
        "APE",
        "ARC",
        "BBA",
        "BIO",
        "ECO",
        "CS",
        "CSE",
        "ECE",
        "EEE",
        "ENG",
        "PHY",
        "MIC",
        "LLB",
        "MAT",
        "PHR",
    }
    skipped_rows = []
    ambiguous_rows = []
    current_semester = None
    start = time.time()

    def save_output():
        json_path.parent.mkdir(parents=True, exist_ok=True)
        output = {
            "generated_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S"),
            "students": students,
        }
        with open(json_path, "w", encoding="utf-8") as fh:
            json.dump(output, fh, indent=2, ensure_ascii=False)

    with pdfplumber.open(pdf_path) as pdf:
        for page_no, page in enumerate(pdf.pages, start=1):
            page_text = page.extract_text() or ""

            for line in page_text.splitlines():
                m = re.search(
                    r"All freshmen students of ([A-Za-z]+)[-_\s]?(\d{2,4})",
                    line,
                    re.IGNORECASE,
                )
                if m:
                    season = m.group(1).capitalize()
                    sem_year = m.group(2)
                    if len(sem_year) == 2:
                        sem_year = "20" + sem_year if int(sem_year) < 50 else "19" + sem_year
                    current_semester = f"{season} {sem_year}"

            tables = page.extract_tables()
            for table in tables:
                header_idx = None
                for i, row in enumerate(table):
                    if row and any(cell and "Student ID" in str(cell) for cell in row):
                        header_idx = i
                        break
                if header_idx is not None:
                    headers = [clean_text(cell) for cell in table[header_idx]]
                    col_map = {}
                    for idx, h in enumerate(headers):
                        h_clean = h.strip().lower()
                        if "student id" in h_clean:
                            col_map["student_id"] = idx
                        elif "applicant" in h_clean:
                            col_map["applicant_id"] = idx
                        elif "name of student" in h_clean or (
                            h_clean == "name" and "name of student" not in "".join(headers).lower()
                        ):
                            col_map["name"] = idx
                        elif "dept" in h_clean:
                            col_map["dept"] = idx
                    data_rows = table[header_idx + 1 :]
                else:
                    col_map = {"student_id": 1, "applicant_id": 2, "name": 3, "dept": 4}
                    data_rows = table
                prev_entry = None
                for row in data_rows:
                    if not row or all((cell is None or clean_text(cell) == "") for cell in row):
                        continue
                    sid = (
                        clean_text(row[col_map.get("student_id", -1)])
                        if col_map.get("student_id") is not None and len(row) > col_map.get("student_id", -1)
                        else ""
                    )
                    name = (
                        clean_text(row[col_map.get("name", -1)])
                        if col_map.get("name") is not None and len(row) > col_map.get("name", -1)
                        else ""
                    )
                    dept = (
                        clean_text(row[col_map.get("dept", -1)])
                        if col_map.get("dept") is not None and len(row) > col_map.get("dept", -1)
                        else ""
                    )
                    norm_dept = normalize_dept(dept)

                    if not sid and not dept and name and prev_entry is not None:
                        prev_entry["Name"] += " " + name
                        print(
                            f"Page {page_no} - (cont.) - {prev_entry['Student_ID']} - {prev_entry['Name']} - {prev_entry['Dept']} - {current_semester if current_semester else ''}",
                            flush=True,
                        )
                        continue

                    if not sid.isdigit() or len(sid) < 6 or not name or norm_dept not in valid_depts:
                        skipped_rows.append(
                            {"page": page_no, "sid": sid, "name": name, "dept": dept, "reason": "invalid or missing"}
                        )
                        continue
                    if sid in seen_ids:
                        ambiguous_rows.append(
                            {"page": page_no, "sid": sid, "name": name, "dept": dept, "reason": "duplicate"}
                        )
                        continue
                    clean_name = re.sub(r"\d+", "", name).strip()
                    adjusted_present = adjust_present_semester(present_semester_full, norm_dept)
                    entry = {
                        "Student_ID": sid,
                        "Name": clean_name.upper(),
                        "Dept": norm_dept,
                        "Semester": current_semester if current_semester else None,
                        "Present_Semester": adjusted_present,
                        "Semester_Number": compute_semester_number(
                            current_semester if current_semester else None, adjusted_present, norm_dept
                        ),
                    }
                    students.append(entry)
                    seen_ids.add(sid)
                    prev_entry = entry
                    print(
                        f"Page {page_no} - {sid} - {clean_name.upper()} - {norm_dept} - {current_semester if current_semester else ''}",
                        flush=True,
                    )
                    save_output()

            prev_entry = None
            lines = [l.strip() for l in page_text.splitlines() if l.strip()]
            pattern_with_appid = re.compile(
                r"^\s*(?:\d{1,3})\s+(\d{6,10})\s+\d{6,12}\s+(.+?)\s+([A-Z]{2,4})\s*$"
            )
            pattern_no_appid = re.compile(r"^\s*(?:\d{1,3})\s+(\d{6,12})\s+(.+?)\s+([A-Z]{2,4})\s*$")
            pattern_sid_name_dept = re.compile(r"^\s*(\d{6,12})\s+(.+?)\s+([A-Z]{2,4})\s*$")
            for ln in lines:
                sid = name = dept = None
                m = pattern_with_appid.match(ln)
                if m:
                    sid = clean_text(m.group(1))
                    name = clean_text(m.group(2))
                    dept = clean_text(m.group(3))
                else:
                    m = pattern_no_appid.match(ln)
                    if m:
                        sid = clean_text(m.group(1))
                        name = clean_text(m.group(2))
                        dept = clean_text(m.group(3))
                    else:
                        m = pattern_sid_name_dept.match(ln)
                        if m:
                            sid = clean_text(m.group(1))
                            name = clean_text(m.group(2))
                            dept = clean_text(m.group(3))
                if sid and name and dept and sid not in seen_ids:
                    norm_dept = normalize_dept(dept)
                    if norm_dept in valid_depts:
                        clean_name = re.sub(r"\d+", "", name).strip()
                        adjusted_present = adjust_present_semester(present_semester_full, norm_dept)
                        entry = {
                            "Student_ID": sid,
                            "Name": clean_name.upper(),
                            "Dept": norm_dept,
                            "Semester": current_semester if current_semester else None,
                            "Present_Semester": adjusted_present,
                            "Semester_Number": compute_semester_number(
                                current_semester if current_semester else None, adjusted_present, norm_dept
                            ),
                        }
                        students.append(entry)
                        seen_ids.add(sid)
                        print(
                            f"Page {page_no} - {sid} - {clean_name.upper()} - {norm_dept} - {current_semester if current_semester else ''}",
                            flush=True,
                        )
                        save_output()
                    else:
                        skipped_rows.append(
                            {"page": page_no, "sid": sid, "name": name, "dept": dept, "reason": "invalid dept"}
                        )

    save_output()
    elapsed = time.time() - start
    print(f"Wrote total {len(students)} students to {json_path} in {elapsed:.2f} seconds", flush=True)


def main():
    print("Running FYAT student extraction ...", flush=True)
    FYAT_DIR.mkdir(parents=True, exist_ok=True)
    pdf_files = sorted(p for p in FYAT_DIR.iterdir() if p.is_file() and p.suffix.lower() == ".pdf")
    if not pdf_files:
        print(f"No PDF files found in {FYAT_DIR}. Skipping FYAT student extraction.", flush=True)
        return

    all_students = []
    seen_ids = set()
    for pdf_path in pdf_files:
        extract_students(pdf_path, OUTPUT_FILE, all_students, seen_ids)


if __name__ == "__main__":
    main()
