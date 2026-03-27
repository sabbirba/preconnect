import os
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
INTERVAL_SECONDS = int(os.environ.get("SCRAPER_INTERVAL_SECONDS", "21600"))


def run_once():
    subprocess.run([sys.executable, "-u", str(ROOT / "bootstrap.py")], check=True, cwd=ROOT)


def main():
    while True:
        try:
            print("[scraper] starting refresh cycle", flush=True)
            run_once()
            print(
                f"[scraper] done, sleeping for {INTERVAL_SECONDS} seconds",
                flush=True,
            )
        except subprocess.CalledProcessError as exc:
            print(f"[scraper] refresh failed: {exc}", flush=True)
        except Exception as exc:
            print(f"[scraper] unexpected error: {exc}", flush=True)

        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
