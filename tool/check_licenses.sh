#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required to run license audit." >&2
  exit 1
fi

DEPS_OUTPUT="$(cd "${ROOT_DIR}" && flutter pub deps --json || true)"

if [[ -z "${DEPS_OUTPUT}" ]]; then
  echo "Failed to query package dependencies." >&2
  exit 1
fi

FORBIDDEN_PATTERNS="agpl|sspl|commons-clause|non-commercial"
VIOLATIONS=$(echo "${DEPS_OUTPUT}" | grep -i -E "${FORBIDDEN_PATTERNS}" || true)

if [[ -n "${VIOLATIONS}" ]]; then
  echo "Incompatible dependency license detected:" >&2
  echo "${VIOLATIONS}" >&2
  exit 1
fi

echo "License audit passed cleanly: 0 incompatible licenses found."
