#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME_DIR="${ROOT_DIR}/build/chrome-extension"
FIREFOX_DIR="${ROOT_DIR}/build/firefox-extension"

if [[ ! -d "${CHROME_DIR}" || ! -d "${FIREFOX_DIR}" ]]; then
  echo "Building extensions for validation..."
  "${ROOT_DIR}/tool/build_extension.sh" --no-pub
fi

check_manifest() {
  local dir="${1}"
  local target="${2}"
  local manifest="${dir}/manifest.json"

  if [[ ! -f "${manifest}" ]]; then
    echo "Manifest missing for ${target}: ${manifest}" >&2
    exit 1
  fi

  if grep -q -i -E "script-src[[:space:]]+'self'[[:space:]]*;[[:space:]]*object-src" "${manifest}" || grep -q -i "content_security_policy" "${manifest}"; then
    if grep -i -E "https?://" "${manifest}" | grep -q -i "script-src"; then
      echo "Remote script domain detected in CSP for ${target}" >&2
      exit 1
    fi
  else
    echo "Invalid or missing CSP in manifest for ${target}" >&2
    exit 1
  fi

  local external_scripts
  external_scripts="$(grep -r -I -i -E "<script[^>]+src=['\"]https?://" "${dir}" || true)"
  if [[ -n "${external_scripts}" ]]; then
    echo "Remote script tags found in ${target} build files:" >&2
    echo "${external_scripts}" >&2
    exit 1
  fi

  echo "Extension ${target} manifest & CSP validation passed."
}

check_manifest "${CHROME_DIR}" "Chrome"
check_manifest "${FIREFOX_DIR}" "Firefox"

echo "All extension validation checks passed."
