#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-${ROOT_DIR}/build/chrome-extension}"
ZIP_OUT="${ZIP_OUT:-${ROOT_DIR}/build/chrome-extension.zip}"
FIREFOX_DIR="${ROOT_DIR}/build/firefox-extension"
FIREFOX_ZIP="${ROOT_DIR}/build/firefox-extension.zip"
COMMON_DIR="${ROOT_DIR}/build/extension-common"

VERSION_OUTPUT="$("${ROOT_DIR}/tool/sync_versions.sh" read)"
APP_VERSION="$(printf '%s\n' "${VERSION_OUTPUT}" | sed -n '1p')"
APP_BUILD_NUMBER="$(printf '%s\n' "${VERSION_OUTPUT}" | sed -n '2p')"
if [[ -z "${APP_VERSION}" || -z "${APP_BUILD_NUMBER}" ]]; then
  echo "Unable to parse version output from sync_versions.sh" >&2
  exit 1
fi
if [[ ! "${APP_BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "Unable to parse app build number for Chrome manifest versioning" >&2
  exit 1
fi

CHROME_BUILD_NUMBER=${APP_BUILD_NUMBER}
IFS='.' read -r APP_MAJOR APP_MINOR APP_PATCH <<< "${APP_VERSION}"
if [[ -z "${APP_MAJOR}" || -z "${APP_MINOR}" || -z "${APP_PATCH}" ]]; then
  echo "Unable to parse app version for Chrome manifest versioning" >&2
  exit 1
fi
CHROME_BUILD_NUMBER_SUFFIX=$((CHROME_BUILD_NUMBER % 10000))
CHROME_VERSION_SUFFIX=$((10000 + CHROME_BUILD_NUMBER_SUFFIX))
if (( CHROME_VERSION_SUFFIX > 65535 )); then
  echo "Chrome version suffix ${CHROME_VERSION_SUFFIX} exceeds the manifest limit of 65535" >&2
  exit 1
fi
CHROME_VERSION="${APP_MAJOR}.${APP_MINOR}.${APP_PATCH}.${CHROME_VERSION_SUFFIX}"
CHROME_VERSION_NAME="${CHROME_VERSION}"
ENV_FILE="${ROOT_DIR}/.env"
TEMP_ENV_FILE=""
FLUTTER_WEB_BASE_HREF="/"
FLUTTER_WEB_OPTIMIZATION_LEVEL="4"

cleanup() {
  if [[ -n "${TEMP_ENV_FILE}" ]]; then
    rm -f "${TEMP_ENV_FILE}"
  fi
  rm -rf "${COMMON_DIR}"
}
trap cleanup EXIT

if [[ ! -f "${ENV_FILE}" ]]; then
  TEMP_ENV_FILE="$(mktemp)"
  ENV_FILE="${TEMP_ENV_FILE}"
  echo "No .env file found; continuing with empty optional dart defines." >&2
fi

rm -rf "${OUT_DIR}" "${FIREFOX_DIR}" "${COMMON_DIR}"
mkdir -p "${COMMON_DIR}"
rm -rf "${ROOT_DIR}/.dart_tool/flutter_build"

flutter build web \
  --release \
  --tree-shake-icons \
  --csp \
  --no-wasm-dry-run \
  --no-web-resources-cdn \
  --base-href="${FLUTTER_WEB_BASE_HREF}" \
  --build-name="${APP_VERSION}" \
  --build-number="${APP_BUILD_NUMBER}" \
  --optimization-level="${FLUTTER_WEB_OPTIMIZATION_LEVEL}" \
  --dart-define-from-file="${ENV_FILE}" \
  --dart-define="APP_VERSION=${APP_VERSION}" \
  --dart-define="APP_BUILD_NUMBER=${APP_BUILD_NUMBER}" \
  --target="${ROOT_DIR}/web/extension_app.dart" \
  --output="${COMMON_DIR}"

cp -R "${ROOT_DIR}/web/"* "${COMMON_DIR}/"
rm -f "${COMMON_DIR}/extension_app.dart"
rm -f "${COMMON_DIR}/background.dart"

rm -f "${COMMON_DIR}/_headers"

perl -0pi -e 's/serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[^"]+"[^}]*\}/serviceWorkerSettings: null/s' \
  "${COMMON_DIR}/flutter_bootstrap.js"
perl -0pi -e 's/"renderer":"canvaskit"/"renderer":"html"/g' \
  "${COMMON_DIR}/flutter_bootstrap.js"
perl -pi -e 's/_flutter\.loader\.load\(\)/_flutter.loader.load({config:{renderer:"html"}})/g' \
  "${COMMON_DIR}/flutter_bootstrap.js"
rm -f "${COMMON_DIR}/flutter_service_worker.js"

perl -0pi -e 's#https://www\.gstatic\.com/flutter-canvaskit#canvaskit#g' \
  "${COMMON_DIR}"/*.js

perl -pi -e 's/new Function\(s\)\(\)/throw new Error("Deferred loading not supported")/g' \
  "${COMMON_DIR}"/*.js

if rg -n "unpkg\.com|gstatic\.com/flutter-canvaskit|eval\\(|new Function" "${COMMON_DIR}"/*.js >/dev/null 2>&1; then
  echo "Unexpected remote code reference found in Chrome extension JS output" >&2
  exit 1
fi

dart compile js \
  "${ROOT_DIR}/web/background.dart" \
  -O2 \
  -o "${COMMON_DIR}/background.dart.js"

mkdir -p "${OUT_DIR}"
mkdir -p "${FIREFOX_DIR}"
cp -R "${COMMON_DIR}/" "${OUT_DIR}/"
cp -R "${COMMON_DIR}/" "${FIREFOX_DIR}/"

python3 -c "
import json
manifest_path = '${OUT_DIR}/manifest.json'
with open(manifest_path, 'r') as f:
    d = json.load(f)
d['version'] = '${CHROME_VERSION}'
d['version_name'] = '${CHROME_VERSION_NAME}'
d.pop('sidebar_action', None)
d.pop('browser_specific_settings', None)
with open(manifest_path, 'w') as f:
    json.dump(d, f, indent=2)
"

python3 -c "
import json
manifest_path = '${FIREFOX_DIR}/manifest.json'
with open(manifest_path, 'r') as f:
    d = json.load(f)
d['version'] = '${CHROME_VERSION}'
d['version_name'] = '${CHROME_VERSION_NAME}'
d.pop('side_panel', None)
if 'permissions' in d:
    d['permissions'] = [p for p in d['permissions'] if p not in ('sidePanel', 'gcm')]
with open(manifest_path, 'w') as f:
    json.dump(d, f, indent=2)
"

mkdir -p "$(dirname "${ZIP_OUT}")"
rm -f "${ZIP_OUT}"
(cd "${OUT_DIR}" && zip -qr "${ZIP_OUT}" .)

mkdir -p "$(dirname "${FIREFOX_ZIP}")"
rm -f "${FIREFOX_ZIP}"
(cd "${FIREFOX_DIR}" && zip -qr "${FIREFOX_ZIP}" .)

echo "Build complete!"
echo "Chrome extension: ${OUT_DIR} (Archive: ${ZIP_OUT})"
echo "Firefox extension: ${FIREFOX_DIR} (Archive: ${FIREFOX_ZIP})"
