#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Scanning repository for prohibited database packages..."
DB_PATTERNS="cloud_firestore|firebase_database|sqflite|package:drift|package:isar|package:realm|package:objectbox|postgres|mysql"
DB_MATCHES="$(grep -r -I -i -E "${DB_PATTERNS}" "${ROOT_DIR}/pubspec.yaml" "${ROOT_DIR}/lib" "${ROOT_DIR}/web" || true)"
if [[ -n "${DB_MATCHES}" ]]; then
  echo "Prohibited database package or import detected:" >&2
  echo "${DB_MATCHES}" >&2
  exit 1
fi

echo "Scanning repository for prohibited analytics/tracking SDKs..."
TRACKING_PATTERNS="firebase_analytics|mixpanel|amplitude|package:segment|google_analytics|facebook_app_id|user_tracking"
TRACKING_MATCHES="$(grep -r -I -i -E "${TRACKING_PATTERNS}" "${ROOT_DIR}/pubspec.yaml" "${ROOT_DIR}/lib" "${ROOT_DIR}/web" || true)"
if [[ -n "${TRACKING_MATCHES}" ]]; then
  echo "Prohibited tracking/analytics SDK or import detected:" >&2
  echo "${TRACKING_MATCHES}" >&2
  exit 1
fi

echo "Scanning repository for committed secret patterns..."
SECRET_PATTERNS="-----BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY-----|AIzaSy[A-Za-z0-9_\\-]{35}|ghp_[A-Za-z0-9]{36}"
SECRET_MATCHES="$(grep -r -I -E -e "${SECRET_PATTERNS}" "${ROOT_DIR}/lib" "${ROOT_DIR}/web" "${ROOT_DIR}/tool" || true)"
if [[ -n "${SECRET_MATCHES}" ]]; then
  echo "Committed secret key detected:" >&2
  echo "${SECRET_MATCHES}" >&2
  exit 1
fi

echo "Scanning repository for insecure cleartext HTTP endpoints..."
HTTP_MATCHES="$(grep -r -I -i -E "http://[a-zA-Z0-9]" "${ROOT_DIR}/lib" "${ROOT_DIR}/web" | grep -v -E "localhost|127\.0\.0\.1|generate_204|http://pr/" || true)"
if [[ -n "${HTTP_MATCHES}" ]]; then
  echo "Insecure HTTP non-localhost URL detected:" >&2
  echo "${HTTP_MATCHES}" >&2
  exit 1
fi

echo "Repository compliance scan passed cleanly (0 databases, 0 trackers, 0 secrets, 0 insecure HTTP)."
