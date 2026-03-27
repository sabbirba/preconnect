# BRACU Info Scraper

This project scrapes BRAC University information into local JSON files and downloads exam schedule PDFs into local folders.

## What It Does

- Scrapes announcements, news, academic dates, people, and transport info
- Stores scraped data in `data/*.json`
- Downloads exam schedule PDFs into `pdf/`
- Serves the data through a FastAPI app

## Current Layout

- `api.py` - FastAPI app that reads from the JSON files
- `bootstrap.py` - Runs all scrapers in sequence
- `scrapers/` - Scraper scripts, including FYAT student extraction, and the shared JSON helper
- `data/` - Generated JSON output
- `pdf/` - Downloaded PDF files
- `urls.txt` - Local endpoint list

## Requirements

- Python 3.9+
- Internet access

## Install

Create a virtual environment and install the packages:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install fastapi uvicorn cloudscraper beautifulsoup4 lxml
```

## Run

Generate the JSON files and PDFs:

```bash
python3 bootstrap.py
```

Start the API:

```bash
python3 -m uvicorn api:app --reload
```

Open the API in your browser:

```bash
http://127.0.0.1:8000
```

## Endpoints

- `/announcements`
- `/academic-dates`
- `/news`
- `/transport`
- `/people`

## Notes

- The scrapers are configured to stop at year `2025` for archive-based data.
- The PDF downloader keeps only `Final` and `Mid` exam folders.
- FYAT notices from `2021` and newer are saved into `pdf/FYAT/` regardless of semester.
- Existing JSON files are merged instead of being fully overwritten on each save.
- A few downloaded PDFs may still be from older runs already present in `pdf/`.

## Generated Files

- `data/announcements.json`
- `data/news.json`
- `data/academic_dates.json`
- `data/people.json`
- `data/transport.json`

## Git Ignore

The repo ignores generated data, PDFs, virtual environments, and common macOS/editor files.
