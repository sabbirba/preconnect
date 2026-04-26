#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-${ROOT_DIR}/build/chrome-extension}"
ZIP_OUT="${ZIP_OUT:-${ROOT_DIR}/build/chrome-extension.zip}"

VERSION_LINE="$(grep '^version:' "${ROOT_DIR}/pubspec.yaml" | head -n1 | awk '{print $2}')"
APP_VERSION="${VERSION_LINE%%+*}"
APP_BUILD_NUMBER="${VERSION_LINE#*+}"

if [[ -z "${APP_VERSION}" || -z "${APP_BUILD_NUMBER}" || "${APP_VERSION}" == "${VERSION_LINE}" || "${APP_BUILD_NUMBER}" == "${VERSION_LINE}" ]]; then
  echo "Unable to read app version from pubspec.yaml"
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

perl -0pi -e 's/serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[^"]+"[^}]*\}/serviceWorkerSettings: null/s' \
  "${OUT_DIR}/flutter_bootstrap.js"
rm -f "${OUT_DIR}/flutter_service_worker.js"

dart compile js \
  "${ROOT_DIR}/web/background.dart" \
  -O2 \
  -o "${OUT_DIR}/background.dart.js"

mkdir -p "$(dirname "${ZIP_OUT}")"
rm -f "${ZIP_OUT}"
(cd "${OUT_DIR}" && zip -qr "${ZIP_OUT}" .)

echo "Chrome extension build ready at: ${OUT_DIR}"
echo "Chrome extension zip ready at: ${ZIP_OUT}"
