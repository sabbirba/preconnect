#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_CONFIG="${ROOT_DIR}/.dart_tool/package_config.json"
FORBIDDEN_PATTERNS="GNU AFFERO GENERAL PUBLIC LICENSE|Server Side Public License|Commons Clause"

if [[ ! -f "${PACKAGE_CONFIG}" ]]; then
  echo "Run flutter pub get before the license audit." >&2
  exit 1
fi

PACKAGE_DIRS="$(grep -oE '"rootUri": *"file://[^"]+"' "${PACKAGE_CONFIG}" | sed -E 's/.*"file:\/\/([^"]+)"/\1/' | sort -u)"

if [[ -z "${PACKAGE_DIRS}" ]]; then
  echo "Failed to read package locations from ${PACKAGE_CONFIG}." >&2
  exit 1
fi

CHECKED=0
VIOLATIONS=""
while IFS= read -r package_dir; do
  for license_file in "${package_dir}"/LICENSE* "${package_dir}"/COPYING*; do
    [[ -f "${license_file}" ]] || continue
    CHECKED=$((CHECKED + 1))
    if grep -qiE "${FORBIDDEN_PATTERNS}" "${license_file}"; then
      VIOLATIONS+="${license_file}"$'\n'
    fi
  done
done <<<"${PACKAGE_DIRS}"

if [[ "${CHECKED}" -eq 0 ]]; then
  echo "No dependency license files were found." >&2
  exit 1
fi

if [[ -n "${VIOLATIONS}" ]]; then
  echo "Incompatible dependency license detected:" >&2
  printf '%s' "${VIOLATIONS}" >&2
  exit 1
fi

echo "License audit passed cleanly: ${CHECKED} license files checked, 0 incompatible licenses found."
