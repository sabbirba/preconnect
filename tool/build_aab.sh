#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

DART_DEFINES=""
if [[ -f "${ENV_FILE}" ]]; then
  while IFS= read -r definition || [[ -n "${definition}" ]]; do
    [[ -z "${definition}" ]] && continue
    encoded="$(printf '%s' "${definition}" | base64 | tr -d '\n')"
    DART_DEFINES+="${encoded},"
  done <"${ENV_FILE}"
  DART_DEFINES="${DART_DEFINES%,}"
fi

VERSION_LINE="$(grep '^version:' "${ROOT_DIR}/pubspec.yaml" | head -n1 | awk '{print $2}')"
VERSION_NAME="${VERSION_LINE%%+*}"
VERSION_CODE="${VERSION_LINE#*+}"

(
  cd "${ROOT_DIR}/android"
  ./gradlew bundleRelease \
    --no-daemon \
    -Ptarget-platform=android-arm,android-arm64 \
    -Ptree-shake-icons=true \
    -Pdart-obfuscation=true \
    -Psplit-debug-info="${ROOT_DIR}/build/symbols/android" \
    -Pextra-gen-snapshot-options=--strip \
    -Pdart-defines="${DART_DEFINES}" \
    -Pbuild-name="${VERSION_NAME}" \
    -Pbuild-number="${VERSION_CODE}"
)
