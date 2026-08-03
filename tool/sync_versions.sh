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

sync_local_properties() {
  local version_name="${1}"
  local version_code="${2}"
  local local_props="${ROOT_DIR}/android/local.properties"

  if [[ -f "${local_props}" ]]; then
    local tmp_props="${local_props}.tmp"
    grep -v '^flutter\.versionName=' "${local_props}" | grep -v '^flutter\.versionCode=' >"${tmp_props}" || true
    mv "${tmp_props}" "${local_props}"
    printf 'flutter.versionName=%s\n' "${version_name}" >>"${local_props}"
    printf 'flutter.versionCode=%s\n' "${version_code}" >>"${local_props}"
  fi
}

bump_release_version() {
  local version_name version_code max_tag_code base_code new_version_code new_version
  local version_output
  version_output="$(read_version)"
  version_name="${version_output%%$'\n'*}"
  version_code="${version_output#*$'\n'}"

  max_tag_code="$(git tag --list 'v*+*' | sed -n -E 's/^v[^+]*\+([0-9]+)$/\1/p' | sort -n | tail -n1 || true)"

  base_code="${version_code}"
  if [[ -n "${max_tag_code}" && "${max_tag_code}" =~ ^[0-9]+$ ]]; then
    if [[ "${max_tag_code}" -ge "${base_code}" ]]; then
      base_code="${max_tag_code}"
    fi
  fi

  new_version_code=$((base_code + 1))
  new_version="${version_name}+${new_version_code}"

  perl -i -pe "s/^version:\\s*.*/version: ${new_version}/" "${ROOT_DIR}/pubspec.yaml"
  perl -0pi -e "s/\"version\":\\s*\"[^\"]+\"/\"version\": \"${version_name}\"/" "${ROOT_DIR}/web/manifest.json"

  sync_store_metadata
  sync_local_properties "${version_name}" "${new_version_code}"

  printf '%s\n%s\n' "${version_name}" "${new_version_code}"
}

apply_version() {
  local version_name="${1:-}"
  local version_code="${2:-}"
  if [[ -z "${version_name}" || -z "${version_code}" ]]; then
    echo "Usage: $0 apply <version_name> <version_code>" >&2
    exit 1
  fi
  local new_version="${version_name}+${version_code}"

  perl -i -pe "s/^version:\\s*.*/version: ${new_version}/" "${ROOT_DIR}/pubspec.yaml"
  perl -0pi -e "s/\"version\":\\s*\"[^\"]+\"/\"version\": \"${version_name}\"/" "${ROOT_DIR}/web/manifest.json"

  sync_store_metadata
  sync_local_properties "${version_name}" "${version_code}"
}

case "${1:-}" in
  read)
    read_version
    ;;
  bump-release)
    bump_release_version
    ;;
  apply)
    apply_version "${2:-}" "${3:-}"
    ;;
  sync-metadata)
    sync_store_metadata
    ;;
  *)
    echo "Usage: $0 {read|bump-release|apply|sync-metadata}" >&2
    exit 1
    ;;
esac
