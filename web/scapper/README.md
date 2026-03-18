# BRACU JSON Scraper API

This folder contains a small FastAPI app plus scrapers that write JSON files for:

- `announcements`
- `exam-schedule`
- `academic-dates`
- `news`
- `transport`
- `contact-info`
- `people`

Cloudflare Browser Rendering is used for the HTML/RSS scraping path when the API token is configured. PDF parsing stays in Python.

## Setup

Install the Python packages:

```bash
pip install fastapi uvicorn beautifulsoup4 lxml pdfplumber
```

Copy `.env.example` to `.env` and fill in the Cloudflare values if you want the Cloudflare path enabled.

## Environment

Required for Cloudflare Browser Rendering:

- `CF_ACCOUNT_ID`
- `CF_BROWSER_RENDERING_TOKEN`

Optional:

If the Cloudflare values are not set, the scrapers fall back to direct fetches.

## Initialize data files

Create the JSON files in `data/`:

```bash
python3 bootstrap_data.py
```

## Refresh data

Run all scrapers:

```bash
python3 refresh_data.py
```

This updates the JSON files in `data/`.

## Run the API

Start the FastAPI app:

```bash
fastapi dev api.py
```

Or with Uvicorn:

```bash
uvicorn api:app --reload
```

One-command flow:

```bash
./run.sh
```

`run.sh` auto-selects a free port starting at `8001`, so it won’t fail if that port is already busy.

## Endpoints

- `/announcements`
- `/exam-schedule`
- `/academic-dates`
- `/news`
- `/transport`
- `/contact-info`
- `/people`

## Notes

- `academic-dates` supports `semester=spring|summer|fall`.
- `exam-schedule` data is still derived from PDF parsing.
- Cloudflare `/crawl` is used first for discovery on announcements, news, and people.
