#!/bin/sh
set -e

ENV_FILE="${SRCROOT}/../.env"
OUT_FILE="${SRCROOT}/Flutter/Env.xcconfig"

: > "$OUT_FILE"

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

[ -n "$DEVELOPMENT_TEAM" ] && echo "DEVELOPMENT_TEAM = $DEVELOPMENT_TEAM" >> "$OUT_FILE"
[ -n "$ADS_APP_ID_IOS" ] && echo "ADS_APP_ID_IOS = $ADS_APP_ID_IOS" >> "$OUT_FILE"
[ -n "$REWARDED_AD_UNIT_ID" ] && echo "REWARDED_AD_UNIT_ID = $REWARDED_AD_UNIT_ID" >> "$OUT_FILE"
