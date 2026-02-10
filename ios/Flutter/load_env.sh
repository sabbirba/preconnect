#!/bin/sh
set -e

ENV_FILE="${SRCROOT}/../.env"
OUT_FILE="${SRCROOT}/Flutter/Env.xcconfig"

# Always write a file so xcconfig include is satisfied.
echo "// Generated from .env; do not edit." > "$OUT_FILE"

if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line; do
    trimmed="$(echo "$line" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -z "$trimmed" ] || [ "${trimmed#\#}" != "$trimmed" ]; then
      continue
    fi
    case "$trimmed" in
      *"="*)
        key="${trimmed%%=*}"
        val="${trimmed#*=}"
        key="$(echo "$key" | tr -d ' ')"
        if [ -n "$key" ]; then
          echo "$key = $val" >> "$OUT_FILE"
        fi
        ;;
      *)
        ;;
    esac
  done < "$ENV_FILE"
fi
