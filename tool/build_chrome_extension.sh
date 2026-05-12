#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-${ROOT_DIR}/build/chrome-extension}"
ZIP_OUT="${ZIP_OUT:-${ROOT_DIR}/build/chrome-extension.zip}"

VERSION_OUTPUT="$("${ROOT_DIR}/tool/sync_versions.sh" read)"
APP_VERSION="$(printf '%s\n' "${VERSION_OUTPUT}" | sed -n '1p')"
APP_BUILD_NUMBER="$(printf '%s\n' "${VERSION_OUTPUT}" | sed -n '2p')"
if [[ -z "${APP_VERSION}" || -z "${APP_BUILD_NUMBER}" ]]; then
  echo "Unable to parse version output from sync_versions.sh" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
rm -rf "${ROOT_DIR}/.dart_tool/flutter_build"

flutter build web \
  --release \
  --csp \
  --no-web-resources-cdn \
  --no-wasm-dry-run \
  --dart-define-from-file="${ROOT_DIR}/.env" \
  --dart-define="APP_VERSION=${APP_VERSION}" \
  --dart-define="APP_BUILD_NUMBER=${APP_BUILD_NUMBER}" \
  --target="${ROOT_DIR}/web/extension_app.dart" \
  --output="${OUT_DIR}"

MANIFEST_FILE="${OUT_DIR}/manifest.json"
if [[ -f "${MANIFEST_FILE}" ]]; then
  perl -0pi -e "s/\"version\":\s*\"[^\"]+\"/\"version\": \"${APP_VERSION}\"/" "${MANIFEST_FILE}"
fi

perl -0pi -e 's/serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[^"]+"[^}]*\}/serviceWorkerSettings: null/s' \
  "${OUT_DIR}/flutter_bootstrap.js"
rm -f "${OUT_DIR}/flutter_service_worker.js"

if rg -n "unpkg\.com|eval\\(|new Function" "${OUT_DIR}"/*.js >/dev/null 2>&1; then
  echo "Unexpected remote code reference found in Chrome extension JS output" >&2
  exit 1
fi

dart compile js \
  "${ROOT_DIR}/web/background.dart" \
  -O2 \
  -o "${OUT_DIR}/background.dart.js"

mkdir -p "$(dirname "${ZIP_OUT}")"
rm -f "${ZIP_OUT}"
(cd "${OUT_DIR}" && zip -qr "${ZIP_OUT}" .)

echo "Chrome extension build ready at: ${OUT_DIR}"
echo "Chrome extension zip ready at: ${ZIP_OUT}"
