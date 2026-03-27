import json
from pathlib import Path
from typing import Callable, Iterable, List, Dict, Any, Optional, Tuple


def load_rows(path: Path) -> List[Dict[str, Any]]:
    if not path.exists():
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def save_rows(path: Path, rows: Iterable[Dict[str, Any]], key_fn: Callable[[Dict[str, Any]], Optional[Tuple[Any, ...]]]) -> None:
    merged = {}
    for row in rows:
        key = key_fn(row)
        if key:
            merged[key] = row

    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(list(merged.values()), f, ensure_ascii=False, indent=2)
    tmp_path.replace(path)
