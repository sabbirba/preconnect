from pathlib import Path
import subprocess
import sys


DATA_DIR = Path("data")
PDF_DIR = Path("pdf")
DATA_FILES = [
    DATA_DIR / "announcements.json",
    DATA_DIR / "news.json",
    DATA_DIR / "academic_dates.json",
    DATA_DIR / "people.json",
    DATA_DIR / "transport.json",
]


def init_storage():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    (PDF_DIR / "FYAT").mkdir(parents=True, exist_ok=True)


def run_scrapers():
    scrapers = [
        "scrapers/announcements.py",
        "scrapers/news.py",
        "scrapers/academic_dates.py",
        "scrapers/people_info.py",
        "scrapers/transport.py",
        "scrapers/download_schedule_pdfs.py",
    ]
    total_steps = len(scrapers) + 1

    for idx, script in enumerate(scrapers, start=1):
        print(f"[{idx}/{total_steps}] Running {script} ...")
        subprocess.run([sys.executable, "-u", script], check=True)

    print(f"[{total_steps}/{total_steps}] Running scrapers/students.py for FYAT extraction ...")
    subprocess.run([sys.executable, "-u", "scrapers/students.py"], check=True)


def main():
    init_storage()
    run_scrapers()
    print("Done. Data files are in /data and PDFs are in /pdf.")


if __name__ == "__main__":
    main()
