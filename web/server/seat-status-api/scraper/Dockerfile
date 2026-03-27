FROM python:3.11-slim

WORKDIR /app/scraper

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    SCRAPER_INTERVAL_SECONDS=21600

COPY scraper/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY scraper ./

CMD ["python", "-u", "runner.py"]
