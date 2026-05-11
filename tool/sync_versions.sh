#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

read_version() {
  local version_line
  version_line="$(grep '^version:' "${ROOT_DIR}/pubspec.yaml" | head -n1 | awk '{print $2}')"
  local version_name="${version_line%%+*}"
  local version_code="${version_line#*+}"

  if [[ -z "${version_name}" || -z "${version_code}" || "${version_name}" == "${version_line}" || "${version_code}" == "${version_line}" || ! "${version_code}" =~ ^[0-9]+$ ]]; then
    echo "Unable to read a valid version from pubspec.yaml" >&2
    exit 1
  fi

  printf '%s\n%s\n' "${version_name}" "${version_code}"
}

sync_chrome_manifest_version() {
  local version_name="$1"
  local manifest_file="${ROOT_DIR}/web/manifest.json"

  if [[ -f "${manifest_file}" ]]; then
    perl -0pi -e "s/\"version\":\\s*\"[^\"]+\"/\"version\": \"${version_name}\"/" "${manifest_file}"
  fi
}

bump_release_version() {
  local version_name version_code last_tag_code base_code new_version_code new_version
  mapfile -t version_parts < <(read_version)
  version_name="${version_parts[0]}"
  version_code="${version_parts[1]}"

  last_tag_code="$(cd "${ROOT_DIR}" && git tag --list 'v*+*' --sort=-v:refname \
    | sed -n 's/^v[^+]*+\([0-9]\+\)$/\1/p' \
    | head -n1)"

  base_code="${version_code}"
  if [[ -n "${last_tag_code}" && "${last_tag_code}" -gt "${base_code}" ]]; then
    base_code="${last_tag_code}"
  fi

  new_version_code=$((base_code + 1))
  new_version="${version_name}+${new_version_code}"

  perl -i -pe "s/^version:\\s*.*/version: ${new_version}/" "${ROOT_DIR}/pubspec.yaml"
  sync_chrome_manifest_version "${version_name}"

  printf '%s\n%s\n' "${version_name}" "${new_version_code}"
}

case "${1:-}" in
  read)
    read_version
    ;;
  bump-release)
    bump_release_version
    ;;
  sync-manifest)
    if [[ $# -ne 2 ]]; then
      echo "Usage: $0 sync-manifest <version_name>" >&2
      exit 1
    fi
    sync_chrome_manifest_version "$2"
    ;;
  *)
    echo "Usage: $0 {read|bump-release|sync-manifest <version_name>}" >&2
    exit 1
    ;;
esac
