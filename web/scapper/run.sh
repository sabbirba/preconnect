#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

python3 bootstrap_data.py
python3 refresh_data.py
if [ -z "${PORT:-}" ]; then
  PORT=8001
  while lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do
    PORT=$((PORT + 1))
  done
fi
exec python3 -m uvicorn api:app --reload --port "$PORT"
