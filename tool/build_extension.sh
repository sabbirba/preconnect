#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NO_PUB=0
OUT_DIR=""
for arg in "$@"; do
  case "$arg" in
    --no-pub) NO_PUB=1 ;;
    --out-dir=*) OUT_DIR="${arg#--out-dir=}" ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *) OUT_DIR="$arg" ;;
  esac
done
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/build/chrome-extension}"

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
IFS='.' read -r APP_MAJOR APP_MINOR APP_PATCH <<<"${APP_VERSION}"
if [[ -z "${APP_MAJOR}" || -z "${APP_MINOR}" || -z "${APP_PATCH}" ]]; then
  echo "Unable to parse app version for Chrome manifest versioning" >&2
  exit 1
fi
CHROME_BUILD_NUMBER_SUFFIX=$((CHROME_BUILD_NUMBER % 10000))
CHROME_VERSION_SUFFIX=$((10000 + CHROME_BUILD_NUMBER_SUFFIX))
if ((CHROME_VERSION_SUFFIX > 65535)); then
  echo "Chrome version suffix ${CHROME_VERSION_SUFFIX} exceeds the manifest limit of 65535" >&2
  exit 1
fi
CHROME_VERSION="${APP_MAJOR}.${APP_MINOR}.${APP_PATCH}.${CHROME_VERSION_SUFFIX}"
CHROME_VERSION_NAME="${CHROME_VERSION}"
FIREFOX_VERSION="${APP_VERSION}.${APP_BUILD_NUMBER}"
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
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "GITHUB_TOKEN=${GITHUB_TOKEN}" > "${TEMP_ENV_FILE}"
  else
    echo "No .env file found; continuing with empty optional dart defines." >&2
  fi
fi

rm -rf "${OUT_DIR}" "${FIREFOX_DIR}" "${COMMON_DIR}"
mkdir -p "${COMMON_DIR}"
rm -rf "${ROOT_DIR}/.dart_tool/flutter_build"

NO_PUB_FLAG=""
if [[ "${NO_PUB}" == "1" ]]; then
  NO_PUB_FLAG="--no-pub"
fi

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
  --output="${COMMON_DIR}" \
  ${NO_PUB_FLAG}

for f in \
  manifest.json \
  favicon.ico \
  favicon.png \
  touch_icon.png \
  auto_logout.js \
  connect_bridge.js \
  remove_hash.js \
  remove_loader.js \
  index.html; do
  src="${ROOT_DIR}/web/${f}"
  if [[ -f "${src}" ]]; then
    cp "${src}" "${COMMON_DIR}/"
  fi
done
if [[ -d "${ROOT_DIR}/web/icons" ]]; then
  cp -R "${ROOT_DIR}/web/icons" "${COMMON_DIR}/"
fi

rm -f "${COMMON_DIR}/_headers"

perl -0pi -e 's/serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*"[^"]+"[^}]*\}/serviceWorkerSettings: null/s' \
  "${COMMON_DIR}/flutter_bootstrap.js"
perl -0pi -e 's#_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*null\s*\}\);#_flutter.loader.load({serviceWorkerSettings:null,config:{renderer:"canvaskit",canvasKitBaseUrl:"canvaskit/",canvasKitVariant:"auto"}});#s' \
  "${COMMON_DIR}/flutter_bootstrap.js"
rm -f "${COMMON_DIR}/flutter_service_worker.js"

perl -0pi -e 's#https://www\.gstatic\.com/flutter-canvaskit#canvaskit#g' \
  "${COMMON_DIR}"/*.js

FIREBASE_CORE_WEB_DIR="$(python3 -c "
import json
from pathlib import Path
config = json.loads(Path('${ROOT_DIR}/.dart_tool/package_config.json').read_text())
package = next(item for item in config['packages'] if item['name'] == 'firebase_core_web')
uri = package['rootUri']
print(Path(uri.removeprefix('file://')).resolve())
")"
FIREBASE_JS_VERSION="$(sed -n \
  "s/const String supportedFirebaseJsSdkVersion = '\\([^']*\\)';/\\1/p" \
  "${FIREBASE_CORE_WEB_DIR}/lib/src/firebase_sdk_version.dart")"
if [[ -z "${FIREBASE_JS_VERSION}" ]]; then
  echo "Unable to determine the Firebase web SDK version" >&2
  exit 1
fi
FIREBASE_DIR="${COMMON_DIR}/firebase/${FIREBASE_JS_VERSION}"
mkdir -p "${FIREBASE_DIR}"
for firebase_module in app messaging; do
  curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --output "${FIREBASE_DIR}/firebase-${firebase_module}.js" \
    "https://www.gstatic.com/firebasejs/${FIREBASE_JS_VERSION}/firebase-${firebase_module}.js"
done
perl -0pi -e \
  's#https://www\.gstatic\.com/firebasejs/[^/]+/firebase-app\.js#./firebase-app.js#g' \
  "${FIREBASE_DIR}/firebase-app.js" \
  "${FIREBASE_DIR}/firebase-messaging.js"
perl -0pi -e 's#https://www\.gstatic\.com/firebasejs/#firebase/#g' \
  "${COMMON_DIR}"/*.js

dart compile js \
  "${ROOT_DIR}/web/background.dart" \
  -O4 \
  -o "${COMMON_DIR}/background.dart.js"

if remote_code_match="$(grep -n -r --include="*.js" -E \
  "unpkg\.com|gstatic\.com/flutter-canvaskit|gstatic\.com/firebasejs|eval\(|new Function" \
  "${COMMON_DIR}" 2>/dev/null)"; then
  echo "Unexpected remote code reference found in extension JS output" >&2
  printf '%s\n' "${remote_code_match}" >&2
  exit 1
fi

find "${COMMON_DIR}" -type f \( \
  -name '*.map' -o \
  -name '*.symbols' -o \
  -name '*.deps' \
  \) -delete
find "${COMMON_DIR}" -type f -name '*.dart' -delete
find "${COMMON_DIR}/canvaskit" -maxdepth 1 -type f \
  ! -name 'canvaskit.js' \
  ! -name 'canvaskit.wasm' \
  -delete
rm -rf "${COMMON_DIR}/canvaskit/experimental_webparagraph"

for required_file in \
  canvaskit/canvaskit.js \
  canvaskit/canvaskit.wasm \
  canvaskit/chromium/canvaskit.js \
  canvaskit/chromium/canvaskit.wasm; do
  if [[ ! -f "${COMMON_DIR}/${required_file}" ]]; then
    echo "Missing local CanvasKit resource: ${required_file}" >&2
    exit 1
  fi
done

if [[ ! -f "${COMMON_DIR}/connect_bridge.js" ]]; then
  echo "Missing Connect browser relay: connect_bridge.js" >&2
  exit 1
fi

if ! grep -q 'renderer:"canvaskit"' "${COMMON_DIR}/flutter_bootstrap.js"; then
  echo "Flutter extension bootstrap is not configured for CanvasKit" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
mkdir -p "${FIREFOX_DIR}"
cp -R "${COMMON_DIR}/." "${OUT_DIR}/"
cp -R "${COMMON_DIR}/." "${FIREFOX_DIR}/"

python3 -c "
import json
manifest_path = '${OUT_DIR}/manifest.json'
with open(manifest_path, 'r') as f:
    d = json.load(f)
d['version'] = '${CHROME_VERSION}'
d['version_name'] = '${CHROME_VERSION_NAME}'
d.pop('sidebar_action', None)
d.pop('browser_specific_settings', None)
csp = d.get('content_security_policy', {}).get('extension_pages', '')
if \"'self'\" not in csp or \"'wasm-unsafe-eval'\" not in csp:
    raise SystemExit('Chrome extension CSP does not permit local CanvasKit WASM')
with open(manifest_path, 'w') as f:
    json.dump(d, f, indent=2)
"

python3 -c "
import json
manifest_path = '${FIREFOX_DIR}/manifest.json'
with open(manifest_path, 'r') as f:
    d = json.load(f)
d['version'] = '${FIREFOX_VERSION}'
d.pop('version_name', None)
d.pop('side_panel', None)
if 'permissions' in d:
    d['permissions'] = [p for p in d['permissions'] if p not in ('sidePanel', 'gcm', 'commands')]
if 'background' in d and 'service_worker' in d['background']:
    d['background']['scripts'] = [d['background'].pop('service_worker')]
csp = d.get('content_security_policy', {}).get('extension_pages', '')
if \"'self'\" not in csp or \"'wasm-unsafe-eval'\" not in csp:
    raise SystemExit('Firefox extension CSP does not permit local CanvasKit WASM')
with open(manifest_path, 'w') as f:
    json.dump(d, f, indent=2)
"

mkdir -p "$(dirname "${ZIP_OUT}")"
rm -f "${ZIP_OUT}"
(cd "${OUT_DIR}" && zip -9 -qr "${ZIP_OUT}" .)

mkdir -p "$(dirname "${FIREFOX_ZIP}")"
rm -f "${FIREFOX_ZIP}"
(cd "${FIREFOX_DIR}" && zip -9 -qr "${FIREFOX_ZIP}" .)

echo "Build complete!"
echo "Chrome extension: ${OUT_DIR} (Archive: ${ZIP_OUT})"
echo "Firefox extension: ${FIREFOX_DIR} (Archive: ${FIREFOX_ZIP})"
