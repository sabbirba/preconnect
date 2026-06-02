#!/usr/bin/env bash

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <path-to-release.aab|path-to-release.apk>" >&2
  exit 1
fi

artifact_path="$1"
if [ ! -f "$artifact_path" ]; then
  echo "Artifact not found: $artifact_path" >&2
  exit 1
fi

artifact_name="$(basename "$artifact_path")"
artifact_ext="${artifact_name##*.}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
key_properties_path="$repo_root/android/key.properties"
debug_keystore_path="$HOME/.android/debug.keystore"
android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
keystore_path=""
store_password=""
key_alias=""
key_password=""

latest_glob_match() {
  local pattern="$1"
  local -a matches=()
  shopt -s nullglob
  matches=( $pattern )
  shopt -u nullglob
  if [ ${#matches[@]} -eq 0 ]; then
    return 1
  fi
  printf '%s\n' "${matches[@]}" | sort | tail -n1
}

find_llvm_strip() {
  local llvm_strip
  llvm_strip="$(latest_glob_match "${android_sdk_root}/ndk"/*/toolchains/llvm/prebuilt/*/bin/llvm-strip || true)"
  if [ -z "$llvm_strip" ]; then
    echo "Could not find llvm-strip under ${android_sdk_root}/ndk" >&2
    exit 1
  fi
  printf '%s\n' "$llvm_strip"
}

resolve_keystore() {
  local store_file=""

  if [ -f "$key_properties_path" ]; then
    store_file="$(grep '^storeFile=' "$key_properties_path" | head -n1 | cut -d= -f2- || true)"
    store_password="$(grep '^storePassword=' "$key_properties_path" | head -n1 | cut -d= -f2- || true)"
    key_alias="$(grep '^keyAlias=' "$key_properties_path" | head -n1 | cut -d= -f2- || true)"
    key_password="$(grep '^keyPassword=' "$key_properties_path" | head -n1 | cut -d= -f2- || true)"

    if [ -n "$store_file" ]; then
      if [[ "$store_file" = /* ]]; then
        keystore_path="$store_file"
      else
        keystore_path="$(cd "$(dirname "$key_properties_path")" && pwd)/$store_file"
      fi
    fi
  fi
  if [ -z "$keystore_path" ] || [ -z "$store_password" ] || [ -z "$key_alias" ] || [ -z "$key_password" ]; then
    if [ -f "$debug_keystore_path" ]; then
      keystore_path="$debug_keystore_path"
      store_password="android"
      key_alias="androiddebugkey"
      key_password="android"
    else
      echo "Signing config not found. Expected android/key.properties or ~/.android/debug.keystore." >&2
      exit 1
    fi
  fi
}

strip_aab() {
  local bundle_path="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local bundle_dir="$tmp_dir/bundle"
  local unsigned_bundle="$tmp_dir/$(basename "$bundle_path").unsigned"
  local signed_bundle="$tmp_dir/$(basename "$bundle_path").signed"
  mkdir -p "$bundle_dir"
  unzip -oq "$bundle_path" -d "$bundle_dir"

  rm -rf \
    "$bundle_dir/BUNDLE-METADATA/com.android.tools.build.debugsymbols" \
    "$bundle_dir/META-INF"

  local llvm_strip
  llvm_strip="$(find_llvm_strip)"
  while IFS= read -r -d '' so_file; do
    local stripped_so="$so_file.stripped"
    "$llvm_strip" --strip-unneeded -o "$stripped_so" "$so_file"
    mv "$stripped_so" "$so_file"
  done < <(find "$bundle_dir/base/lib" -type f -name '*.so' -print0)

  (
    cd "$bundle_dir"
    find . -type f -print | sed 's#^\./##' | zip -q -@ "$unsigned_bundle"
  )

  resolve_keystore

  jarsigner \
    -keystore "$keystore_path" \
    -storepass "$store_password" \
    -keypass "$key_password" \
    -sigalg SHA256withRSA \
    -digestalg SHA-256 \
    -signedjar "$signed_bundle" \
    "$unsigned_bundle" \
    "$key_alias" \
    >/dev/null

  mv "$signed_bundle" "$bundle_path"

  if zipinfo -1 "$bundle_path" | grep -q '^BUNDLE-METADATA/com.android.tools.build.debugsymbols/'; then
    echo "Failed to strip native debug symbols from $bundle_path" >&2
    exit 1
  fi
}

strip_apk() {
  local apk_path="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local apk_dir="$tmp_dir/apk"
  local unsigned_apk="$tmp_dir/unsigned.apk"
  local aligned_apk="$tmp_dir/aligned.apk"
  mkdir -p "$apk_dir"
  unzip -oq "$apk_path" -d "$apk_dir"

  local llvm_strip
  llvm_strip="$(find_llvm_strip)"

  while IFS= read -r -d '' so_file; do
    local stripped_so="$so_file.stripped"
    "$llvm_strip" --strip-unneeded -o "$stripped_so" "$so_file"
    mv "$stripped_so" "$so_file"
  done < <(find "$apk_dir/lib" -type f -name '*.so' -print0)

  (
    cd "$apk_dir"
    find . -type f -not -path './META-INF/*' -print | sed 's#^\./##' | zip -q -@ "$unsigned_apk"
  )

  local apksigner_path
  apksigner_path="$(latest_glob_match "${android_sdk_root}/build-tools"/*/apksigner || true)"
  if [ -z "$apksigner_path" ]; then
    echo "Could not find apksigner under ${android_sdk_root}/build-tools" >&2
    exit 1
  fi
  local zipalign_path
  zipalign_path="$(cd "$(dirname "$apksigner_path")" && pwd)/zipalign"
  if [ ! -x "$zipalign_path" ]; then
    echo "Could not find zipalign next to apksigner at $zipalign_path" >&2
    exit 1
  fi

  resolve_keystore

  "$zipalign_path" -f -p 4 "$unsigned_apk" "$aligned_apk"
  "$apksigner_path" sign \
    --ks "$keystore_path" \
    --ks-pass "pass:$store_password" \
    --ks-key-alias "$key_alias" \
    --key-pass "pass:$key_password" \
    --out "$apk_path" \
    "$aligned_apk"

  "$apksigner_path" verify --verbose "$apk_path" >/dev/null
}

case "$artifact_ext" in
  aab)
    if [ "${ALLOW_ANDROID_AAB_SYMBOL_STRIP:-}" != "1" ]; then
      cat >&2 <<'EOF'
Refusing to strip native debug metadata from an Android App Bundle.

Play Console uses the AAB's BUNDLE-METADATA/com.android.tools.build.debugsymbols
entries for native crash and ANR symbolication. Stripping them can reintroduce
the "native code without debug symbols" warning.

If this is not a Play Store artifact and you intentionally want to remove that
metadata, rerun with ALLOW_ANDROID_AAB_SYMBOL_STRIP=1.
EOF
      exit 1
    fi
    strip_aab "$artifact_path"
    ;;
  apk)
    strip_apk "$artifact_path"
    ;;
  *)
    echo "Unsupported artifact type: $artifact_path" >&2
    exit 1
    ;;
esac

echo "Stripped native debug symbols from $artifact_path"
