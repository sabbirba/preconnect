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
FLUTTER_WEB_PWA_STRATEGY="${FLUTTER_WEB_PWA_STRATEGY:-none}"
FLUTTER_WEB_BASE_HREF="${FLUTTER_WEB_BASE_HREF:-/}"
FLUTTER_WEB_OPTIMIZATION_LEVEL="${FLUTTER_WEB_OPTIMIZATION_LEVEL:-4}"

cleanup() {
  if [[ -n "${TEMP_ENV_FILE}" ]]; then
    rm -f "${TEMP_ENV_FILE}"
  fi
}
trap cleanup EXIT

if [[ ! -f "${ENV_FILE}" ]]; then
  TEMP_ENV_FILE="$(mktemp)"
  ENV_FILE="${TEMP_ENV_FILE}"
  echo "No .env file found; continuing with empty optional dart defines." >&2
fi

if [[ ! "${FLUTTER_WEB_OPTIMIZATION_LEVEL}" =~ ^[0-4]$ ]]; then
  echo "FLUTTER_WEB_OPTIMIZATION_LEVEL must be an integer from 0 to 4" >&2
  exit 1
fi

if [[ "${FLUTTER_WEB_BASE_HREF}" != /* || "${FLUTTER_WEB_BASE_HREF}" != */ ]]; then
  echo "FLUTTER_WEB_BASE_HREF must start and end with /" >&2
  exit 1
fi

case "${FLUTTER_WEB_PWA_STRATEGY}" in
  none|offline-first)
    ;;
  *)
    echo "FLUTTER_WEB_PWA_STRATEGY must be one of: none, offline-first" >&2
    exit 1
    ;;
esac

mkdir -p "${OUT_DIR}"
rm -rf "${ROOT_DIR}/.dart_tool/flutter_build"

flutter build web \
  --release \
  --tree-shake-icons \
  --csp \
  --no-wasm-dry-run \
  --no-web-resources-cdn \
  --pwa-strategy="${FLUTTER_WEB_PWA_STRATEGY}" \
  --base-href="${FLUTTER_WEB_BASE_HREF}" \
  --build-name="${APP_VERSION}" \
  --build-number="${APP_BUILD_NUMBER}" \
  --optimization-level="${FLUTTER_WEB_OPTIMIZATION_LEVEL}" \
  --dart-define-from-file="${ENV_FILE}" \
  --dart-define="APP_VERSION=${APP_VERSION}" \
  --dart-define="APP_BUILD_NUMBER=${APP_BUILD_NUMBER}" \
  --target="${ROOT_DIR}/web/extension_app.dart" \
  --output="${OUT_DIR}"

MANIFEST_FILE="${OUT_DIR}/manifest.json"
if [[ -f "${MANIFEST_FILE}" ]]; then
  perl -0pi -e "s/\"version\":\s*\"[^\"]+\"/\"version\": \"${CHROME_VERSION}\"/" "${MANIFEST_FILE}"
  if rg -n '"version_name"\s*:' "${MANIFEST_FILE}" >/dev/null 2>&1; then
    perl -0pi -e "s/\"version_name\":\s*\"[^\"]+\"/\"version_name\": \"${CHROME_VERSION_NAME}\"/" "${MANIFEST_FILE}"
  else
    perl -0pi -e "s/(\"version\":\s*\"[^\"]+\")/\$1,\\n  \"version_name\": \"${CHROME_VERSION_NAME}\"/" "${MANIFEST_FILE}"
  fi
fi

perl -0pi -e 's/serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[^"]+"[^}]*\}/serviceWorkerSettings: null/s' \
  "${OUT_DIR}/flutter_bootstrap.js"
perl -0pi -e 's/"renderer":"canvaskit"/"renderer":"html"/g' \
  "${OUT_DIR}/flutter_bootstrap.js"
perl -pi -e 's/_flutter\.loader\.load\(\)/_flutter.loader.load({config:{renderer:"html"}})/g' \
  "${OUT_DIR}/flutter_bootstrap.js"
rm -f "${OUT_DIR}/flutter_service_worker.js"
rm -rf "${OUT_DIR}/canvaskit"


perl -0pi -e 's#https://www\.gstatic\.com/flutter-canvaskit#canvaskit#g' \
  "${OUT_DIR}"/*.js

perl -pi -e 's/new Function\(s\)\(\)/throw new Error("Deferred loading not supported")/g' \
  "${OUT_DIR}"/*.js

if rg -n "unpkg\.com|gstatic\.com/flutter-canvaskit|eval\\(|new Function" "${OUT_DIR}"/*.js >/dev/null 2>&1; then
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
