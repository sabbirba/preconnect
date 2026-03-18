import os
from pathlib import Path
import subprocess
import sys


BASE_DIR = Path(__file__).resolve().parent

SCRIPTS = [
    'scrappers.announcements',
    'scrappers.news',
    'scrappers.academic_dates',
    'scrappers.contact_info',
    'scrappers.transport',
    'scrappers.download_schedule_pdfs',
    'scrappers.general_exam_schedule',
    'scrappers.special_exam_schedule',
    'scrappers.people_info',
]


def main() -> int:
    for relative in SCRIPTS:
        print(f'Running {relative}...', flush=True)
        result = subprocess.run(
            [sys.executable, '-u', '-m', relative],
            cwd=BASE_DIR,
            env=os.environ.copy(),
        )
        if result.returncode != 0:
            print(f'{relative} failed with exit code {result.returncode}', flush=True)
            return result.returncode
        print(f'Finished {relative}', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
