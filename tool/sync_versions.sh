#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

read_version() {
  local version_line
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git show HEAD:pubspec.yaml >/dev/null 2>&1; then
    version_line="$(git show HEAD:pubspec.yaml | grep '^version:' | head -n1 | awk '{print $2}')"
  else
    version_line="$(grep '^version:' "${ROOT_DIR}/pubspec.yaml" | head -n1 | awk '{print $2}')"
  fi
  local version_name="${version_line%%+*}"
  local version_code="${version_line#*+}"

  if [[ -z "${version_name}" || -z "${version_code}" || "${version_name}" == "${version_line}" || "${version_code}" == "${version_line}" || ! "${version_code}" =~ ^[0-9]+$ ]]; then
    echo "Unable to read a valid version from pubspec.yaml" >&2
    exit 1
  fi

  printf '%s\n%s\n' "${version_name}" "${version_code}"
}

read_latest_changelog() {
  local changelog_file="${ROOT_DIR}/CHANGELOG.md"
  if [[ -f "${changelog_file}" ]]; then
    local notes
    notes="$(perl -0777 -ne 'if (/##\s*\[[0-9]+(?:\.[0-9]+)*\][^\n]*\n+([\s\S]*?)(?=\n+##\s*\[|\z)/) { my $t = $1; $t =~ s/^\s+|\s+$//g; print $t if $t; }' "${changelog_file}")"
    if [[ -n "${notes}" ]]; then
      printf '%s\n' "${notes}"
      return 0
    fi
  fi
  printf 'We update PreConnect regularly to make your academic experience smoother and faster. This release includes performance improvements, bug fixes, and general stability enhancements.\n'
}

sync_store_metadata() {
  local notes
  notes="$(read_latest_changelog)"

  mkdir -p "${ROOT_DIR}/ios/fastlane/metadata/en-US"
  mkdir -p "${ROOT_DIR}/android/fastlane/metadata/android/en-US/changelogs"

  printf '%s\n' "${notes}" >"${ROOT_DIR}/ios/fastlane/metadata/en-US/release_notes.txt"
  printf '%s\n' "${notes}" >"${ROOT_DIR}/android/fastlane/metadata/android/en-US/changelogs/default.txt"
}

bump_release_version() {
  local version_name version_code last_tag_code base_code new_version_code new_version
  local version_output
  version_output="$(read_version)"
  version_name="${version_output%%$'\n'*}"
  version_code="${version_output#*$'\n'}"

  last_tag_code="$(cd "${ROOT_DIR}" && git tag --list 'v*+*' --sort=-v:refname \
    | sed -E -n 's/^v[^+]*\+([0-9]+).*$/\1/p; 1q')"

  base_code="${version_code}"
  if [[ -n "${last_tag_code}" && "${last_tag_code}" -gt "${base_code}" ]]; then
    base_code="${last_tag_code}"
  fi

  new_version_code=$((base_code + 1))
  new_version="${version_name}+${new_version_code}"

  perl -i -pe "s/^version:\\s*.*/version: ${new_version}/" "${ROOT_DIR}/pubspec.yaml"
  perl -0pi -e "s/\"version\":\\s*\"[^\"]+\"/\"version\": \"${version_name}\"/" "${ROOT_DIR}/web/manifest.json"

  sync_store_metadata

  printf '%s\n%s\n' "${version_name}" "${new_version_code}"
}

case "${1:-}" in
  read)
    read_version
    ;;
  bump-release)
    bump_release_version
    ;;
  sync-metadata)
    sync_store_metadata
    ;;
  *)
    echo "Usage: $0 {read|bump-release|sync-metadata}" >&2
    exit 1
    ;;
esac
