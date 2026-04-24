#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-${ROOT_DIR}/build/chrome-extension}"

mkdir -p "${OUT_DIR}"

flutter build web \
  --release \
  --csp \
  --no-web-resources-cdn \
  --no-wasm-dry-run \
  --dart-define-from-file="${ROOT_DIR}/.env" \
  --target="${ROOT_DIR}/web/extension_app.dart" \
  --output="${OUT_DIR}"

perl -0pi -e 's/serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[^"]+"[^}]*\}/serviceWorkerSettings: null/s' \
  "${OUT_DIR}/flutter_bootstrap.js"
rm -f "${OUT_DIR}/flutter_service_worker.js"

dart compile js \
  "${ROOT_DIR}/web/background.dart" \
  -O2 \
  -o "${OUT_DIR}/background.dart.js"

echo "Chrome extension build ready at: ${OUT_DIR}"
