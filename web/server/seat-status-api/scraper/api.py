from fastapi import FastAPI, Query, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from typing import Optional
import json
from datetime import timedelta, datetime, date
import calendar
from pathlib import Path


## Helper Functions
def format_time(seconds):
    if seconds is None:
        return None

    if isinstance(seconds, timedelta):
        td = seconds
    else:
        td = timedelta(seconds=float(seconds))

    # Format into HH:MM:SS
    total_seconds = int(td.total_seconds())
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


DATA_DIR = Path("data")
DATA_DIR.mkdir(parents=True, exist_ok=True)
ANNOUNCEMENTS_FILE = DATA_DIR / "announcements.json"
NEWS_FILE = DATA_DIR / "news.json"
ACADEMIC_DATES_FILE = DATA_DIR / "academic_dates.json"
PEOPLE_FILE = DATA_DIR / "people.json"
TRANSPORT_FILE = DATA_DIR / "transport.json"


def load_json_file(path: Path):
    if not path.exists():
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


def to_date(value):
    if value in (None, ""):
        return None
    if isinstance(value, date):
        return value
    try:
        return datetime.fromisoformat(str(value)).date()
    except Exception:
        try:
            return datetime.strptime(str(value), "%Y-%m-%d").date()
        except Exception:
            return None


def sort_desc(items, key):
    return sorted(items, key=lambda item: item.get(key) or "", reverse=True)


def sort_asc(items, key):
    return sorted(items, key=lambda item: item.get(key) or "")

app = FastAPI(title="BRACU Info API")

CLIENT_DIR = Path("client")
if CLIENT_DIR.exists():
    app.mount("/client/", StaticFiles(directory=str(CLIENT_DIR)), name="client")

@app.get("/")
def read_root():
    if CLIENT_DIR.exists():
        return FileResponse(CLIENT_DIR / "index.html")
    return {"status": "ok", "message": "BRACU Info API is running."}

@app.get("/announcements")
def get_announcements(
    start_date: Optional[str] = Query(None, description="YYYY-MM-DD"),
    end_date: Optional[str] = Query(None, description="YYYY-MM-DD"),
    limit: Optional[int] = Query(None, description="Max number of results to return")
):

    rows = load_json_file(ANNOUNCEMENTS_FILE)
    if start_date:
        start = to_date(start_date)
        rows = [row for row in rows if to_date(row.get("published_date")) and to_date(row["published_date"]) >= start]
    if end_date:
        end = to_date(end_date)
        rows = [row for row in rows if to_date(row.get("published_date")) and to_date(row["published_date"]) <= end]
    rows = sort_desc(rows, "published_date")
    return rows[:limit] if limit else rows[:10]

@app.get("/academic-dates")
def get_academic_dates(
    event_name: Optional[str] = None,
    start_date: Optional[str] = Query(None, description="YYYY-MM-DD"),
    end_date: Optional[str] = Query(None, description="YYYY-MM-DD")
):
    rows = load_json_file(ACADEMIC_DATES_FILE)
    if event_name:
        rows = [row for row in rows if event_name.lower() in str(row.get("event_name", "")).lower()]
    if start_date:
        start = to_date(start_date)
        rows = [row for row in rows if to_date(row.get("start_date")) and to_date(row["start_date"]) >= start]
    if end_date:
        end = to_date(end_date)
        rows = [row for row in rows if to_date(row.get("end_date")) and to_date(row["end_date"]) <= end]
    return sort_asc(rows, "start_date")

@app.get("/news")
def get_news(
    title: Optional[str] = None,
    start_date: Optional[str] = Query(None, description="YYYY-MM-DD"),
    end_date: Optional[str] = Query(None, description="YYYY-MM-DD"),
    exact_date: Optional[str] = Query(None, description="YYYY-MM-DD")
):
    rows = load_json_file(NEWS_FILE)
    if title:
        rows = [row for row in rows if row.get("title") == title]
    if start_date:
        start = to_date(start_date)
        rows = [row for row in rows if to_date(row.get("published_date")) and to_date(row["published_date"]) >= start]
    if end_date:
        end = to_date(end_date)
        rows = [row for row in rows if to_date(row.get("published_date")) and to_date(row["published_date"]) <= end]
    if exact_date:
        exact = to_date(exact_date)
        rows = [row for row in rows if to_date(row.get("published_date")) == exact]
    for item in rows:
        if isinstance(item.get("image_url"), str):
            try:
                item["image_url"] = json.loads(item["image_url"])
            except Exception:
                item["image_url"] = None
    return sort_asc(rows, "published_date")

@app.get("/transport")
def get_transport(route_id: Optional[int] = None):
    rows = load_json_file(TRANSPORT_FILE)
    if route_id:
        rows = [row for row in rows if f"Route-{route_id:02}" in str(row.get("route_name", ""))]
    return rows

@app.get("/people")
def get_people(name: Optional[str] = None):
    rows = load_json_file(PEOPLE_FILE)
    if name:
        rows = [row for row in rows if name.lower() in str(row.get("url", "")).lower()]
    return rows[:50]
