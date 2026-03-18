import os
import re
import shutil
import time
from pathlib import Path
from urllib.parse import unquote, urlparse
from urllib.request import Request, urlopen

from scrappers.shared import MIN_EXAM_YEAR, extract_semester_exam_folder, is_allowed_exam_folder, load_json_list


BASE_FOLDER = Path(__file__).resolve().parents[1] / 'exam schedule pdfs'
BASE_FOLDER.mkdir(parents=True, exist_ok=True)

MAX_RETRIES = 5
RETRY_DELAY = 3


def fetch_and_download_exam_schedule_pdfs():
    query_file = Path(__file__).resolve().parents[1] / 'data' / 'announcements.json'
    if not query_file.exists():
        print('No announcements.json found')
        return
    results = load_json_list(query_file)

    cleanup_legacy_exam_folders()

    for row in results:
        title = row.get('title', '')
        message = row.get('message', '')
        folder_name = extract_semester_exam_folder(title, min_year=MIN_EXAM_YEAR)
        if not folder_name:
            continue
        full_folder_path = BASE_FOLDER / folder_name
        full_folder_path.mkdir(parents=True, exist_ok=True)
        downloaded_count = 0

        if 'Embedded Page Links :' in message:
            content_after = message.split('Embedded Page Links :', 1)[1].strip()
            urls = [url.strip() for url in content_after.splitlines() if url.strip()]
            for url in urls:
                if download_pdf_with_retry(url, full_folder_path):
                    downloaded_count += 1
        if downloaded_count == 0 and not any(full_folder_path.iterdir()):
            full_folder_path.rmdir()
def cleanup_legacy_exam_folders():
    if not BASE_FOLDER.exists():
        return
    for child in list(BASE_FOLDER.iterdir()):
        if not child.is_dir():
            continue
        normalized_name = re.sub(r'\s+', ' ', child.name).replace('\u00a0', ' ').strip()
        match = re.search(r'(Spring|Fall|Summer)\s+(\d{4})', normalized_name, re.IGNORECASE)
        if not match:
            shutil.rmtree(child, ignore_errors=True)
            continue
        year = int(match.group(2))
        if year < MIN_EXAM_YEAR:
            shutil.rmtree(child, ignore_errors=True)
            continue
        if not is_allowed_exam_folder(normalized_name, min_year=MIN_EXAM_YEAR):
            shutil.rmtree(child, ignore_errors=True)
            continue
        if child.name != normalized_name:
            target = BASE_FOLDER / normalized_name
            target.mkdir(parents=True, exist_ok=True)
            for item in child.iterdir():
                if item.is_file():
                    dest = target / item.name
                    if not dest.exists():
                        item.replace(dest)
                    else:
                        item.unlink(missing_ok=True)
            child.rmdir()
    prune_empty_directories(BASE_FOLDER)


def prune_empty_directories(root_path):
    for current, dirs, files in os.walk(root_path, topdown=False):
        current_path = Path(current)
        if current_path == root_path:
            continue
        if not dirs and not files:
            current_path.rmdir()


def download_pdf_with_retry(url, folder_path):
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            request = Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urlopen(request, timeout=60) as response:
                if getattr(response, 'status', 200) == 404:
                    return False
                content_type = response.headers.get('Content-Type', '')
                content_disposition = response.headers.get('Content-Disposition', '')
                parsed = urlparse(url)
                raw_name = os.path.basename(parsed.path)
                raw_name_lower = unquote(raw_name).lower()
                looks_like_pdf = (
                    'pdf' in content_type.lower()
                    or '.pdf' in content_disposition.lower()
                    or raw_name_lower.endswith('.pdf')
                )
                if not looks_like_pdf:
                    return False
                content = response.read()

            decoded_name = unquote(raw_name).strip()
            safe_name = re.sub(r'[^A-Za-z0-9._ -]+', '_', decoded_name)
            if not safe_name.lower().endswith('.pdf'):
                safe_name = f'{safe_name}.pdf' if safe_name else 'downloaded_schedule.pdf'

            filename = os.path.join(folder_path, safe_name)
            with open(filename, 'wb') as f:
                f.write(content)
            return True
        except Exception:
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_DELAY)
    return False


if __name__ == '__main__':
    fetch_and_download_exam_schedule_pdfs()
