from pathlib import Path
import json


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / 'data'

DEFAULT_FILES = {
    'announcements.json': [],
    'exam_schedule.json': [],
    'academic_dates.json': [],
    'news.json': [],
    'transport.json': [],
    'contact_info.json': [],
    'people.json': [],
}


def main() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    for name, payload in DEFAULT_FILES.items():
        path = DATA_DIR / name
        if path.exists():
            continue
        with path.open('w', encoding='utf-8') as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
    print(f'Initialized JSON data files in {DATA_DIR}')


if __name__ == '__main__':
    main()
