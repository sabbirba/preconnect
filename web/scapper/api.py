from datetime import date, datetime
import calendar
import json
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / 'data'
CLIENT_DIR = BASE_DIR / 'client'

app = FastAPI(title='BRACU Info API')


def _load_json(name: str, default):
    path = DATA_DIR / name
    if not path.exists():
        return default
    try:
      with path.open('r', encoding='utf-8') as f:
          return json.load(f)
    except Exception:
        return default


def _write_json(name: str, payload) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    path = DATA_DIR / name
    with path.open('w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def _parse_date(raw: str) -> Optional[datetime.date]:
    text = (raw or '').strip()
    if not text:
        return None
    for fmt in ('%Y-%m-%d', '%d-%m-%Y', '%d/%m/%Y', '%B %d, %Y'):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(text).date()
    except Exception:
        return None


def _filter_by_date_range(items, key, start_date, end_date):
    start = _parse_date(start_date) if start_date else None
    end = _parse_date(end_date) if end_date else None
    if not start and not end:
        return items
    output = []
    for item in items:
        value = _parse_date(item.get(key))
        if value is None:
            continue
        if start and value < start:
            continue
        if end and value > end:
            continue
        output.append(item)
    return output


@app.get('/')
def read_root():
    index = CLIENT_DIR / 'index.html'
    if index.exists():
      return FileResponse(index)
    return {'ok': True, 'message': 'BRACU Info API'}


@app.get('/announcements')
def get_announcements(
    start_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
    end_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
):
    rows = _load_json('announcements.json', [])
    rows = _filter_by_date_range(rows, 'published_date', start_date, end_date)
    rows.sort(key=lambda item: item.get('published_date') or '', reverse=True)
    return rows


@app.get('/exam-schedule')
def get_exam_schedule(
    exam_type: str = Query(..., description='Exam type, e.g. Final Fall 2022'),
    course_code: str = Query(..., description='Course code, e.g. CSE331'),
    section: Optional[str] = None,
    student_id: Optional[str] = None,
):
    rows = _load_json('exam_schedule.json', [])
    output = []
    for item in rows:
        if exam_type and item.get('type') != exam_type:
            continue
        if course_code and item.get('course_code') != course_code:
            continue
        if section and item.get('section') != section:
            continue
        if student_id and item.get('student_id') != student_id:
            continue
        output.append(item)
    output.sort(key=lambda item: (item.get('section') or '', item.get('date') or ''))
    return output


@app.get('/academic-dates')
def get_academic_dates(
    semester: Optional[str] = Query(None, description='spring, summer, fall'),
    event_name: Optional[str] = None,
    start_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
    end_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
):
    rows = _load_json('academic_dates.json', [])
    output = []
    semester_value = (semester or '').strip().lower()
    event_value = (event_name or '').strip().lower()
    for item in rows:
        if semester_value and item.get('semester', '').strip().lower() != semester_value:
            continue
        if event_value and event_value not in item.get('event_name', '').lower():
            continue
        output.append(item)

    output = _filter_by_date_range(output, 'start_date', start_date, end_date)
    output.sort(key=lambda item: item.get('start_date') or '')
    return output


@app.get('/news')
def get_news(
    title: Optional[str] = None,
    start_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
    end_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
    exact_date: Optional[str] = Query(None, description='YYYY-MM-DD'),
):
    rows = _load_json('news.json', [])
    output = []
    title_value = (title or '').strip().lower()
    for item in rows:
        if title_value and title_value not in item.get('title', '').lower():
            continue
        output.append(item)
    if exact_date:
        output = [item for item in output if item.get('published_date') == exact_date]
    else:
        output = _filter_by_date_range(output, 'published_date', start_date, end_date)
    if not any([title, start_date, end_date, exact_date]):
        today = date.today()
        first_day = date(today.year, today.month, 1)
        last_day = date(today.year, today.month, calendar.monthrange(today.year, today.month)[1])
        output = _filter_by_date_range(
            output,
            'published_date',
            first_day.isoformat(),
            last_day.isoformat(),
        )
    output.sort(key=lambda item: item.get('published_date') or '', reverse=True)
    return output


@app.get('/transport')
def get_transport(route_id: Optional[int] = None):
    rows = _load_json('transport.json', [])
    if route_id is None:
        return rows
    route_token = f'route-{int(route_id):02}'
    return [
        item
        for item in rows
        if route_token in item.get('route_name', '').lower()
    ]
