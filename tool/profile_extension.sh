#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME_DIR="${ROOT_DIR}/build/chrome-extension"

if [[ ! -d "${CHROME_DIR}" ]]; then
  echo "Building Chrome extension for profiling..."
  "${ROOT_DIR}/tool/build_extension.sh" --no-pub
fi

echo "--- Extension Bundle Size Breakdown ---"
du -sh "${CHROME_DIR}"/*

MAIN_JS="${CHROME_DIR}/main.dart.js"
if [[ -f "${MAIN_JS}" ]]; then
  SIZE_BYTES="$(stat -f %z "${MAIN_JS}" 2>/dev/null || stat -c %s "${MAIN_JS}" 2>/dev/null || echo 0)"
  SIZE_MB=$((SIZE_BYTES / 1048576))
  echo "main.dart.js size: ${SIZE_MB} MB (${SIZE_BYTES} bytes)"
  if [[ "${SIZE_MB}" -gt 25 ]]; then
    echo "Warning: main.dart.js payload exceeds 25MB budget!" >&2
    exit 1
  fi
fi

echo "Extension popup load speed profiling completed successfully."
