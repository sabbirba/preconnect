#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="${ROOT_DIR}/native/preconnect_native"
MANIFEST="${CRATE_DIR}/Cargo.toml"

usage() {
  cat >&2 <<'EOF'
Usage: tool/build_rust_native.sh android
       tool/build_rust_native.sh apple <macosx|iphoneos|iphonesimulator>
EOF
  exit 1
}

ensure_target() {
  local target="$1"
  if ! rustup target list --installed | grep -qx "$target"; then
    rustup target add "$target"
  fi
}

android_ndk_root() {
  if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}" ]]; then
    printf '%s\n' "${ANDROID_NDK_HOME}"
    return 0
  fi
  if [[ -n "${ANDROID_NDK_ROOT:-}" && -d "${ANDROID_NDK_ROOT}" ]]; then
    printf '%s\n' "${ANDROID_NDK_ROOT}"
    return 0
  fi

  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -n "$sdk_root" && -d "${sdk_root}/ndk" ]]; then
    find "${sdk_root}/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1
    return 0
  fi

  return 1
}

ndk_host_tag() {
  case "$(uname -s)" in
    Linux)
      printf 'linux-x86_64\n'
      ;;
    Darwin)
      printf 'darwin-x86_64\n'
      ;;
    *)
      echo "Unsupported Android NDK host OS: $(uname -s)" >&2
      return 1
      ;;
  esac
}

build_android() {
  local ndk_root
  if ! ndk_root="$(android_ndk_root)" || [[ -z "$ndk_root" || ! -d "$ndk_root" ]]; then
    echo "Unable to locate the Android NDK." >&2
    exit 1
  fi

  local ndk_bin
  ndk_bin="${ndk_root}/toolchains/llvm/prebuilt/$(ndk_host_tag)/bin"
  if [[ ! -d "$ndk_bin" ]]; then
    echo "Unable to locate the Android NDK LLVM toolchain: ${ndk_bin}" >&2
    exit 1
  fi
  local api=24

  local triples=(
    "aarch64-linux-android:arm64-v8a:aarch64-linux-android${api}-clang"
    "armv7-linux-androideabi:armeabi-v7a:armv7a-linux-androideabi${api}-clang"
    "i686-linux-android:x86:i686-linux-android${api}-clang"
    "x86_64-linux-android:x86_64:x86_64-linux-android${api}-clang"
  )

  for entry in "${triples[@]}"; do
    IFS=':' read -r triple abi linker <<<"$entry"
    local env_name
    env_name="$(printf '%s' "$triple" | tr '[:lower:]-' '[:upper:]_')"
    local out_dir="${CRATE_DIR}/target/android/${abi}/release"
    mkdir -p "$out_dir"
    ensure_target "$triple"
    env "CARGO_TARGET_${env_name}_LINKER=${ndk_bin}/${linker}" \
      "RUSTFLAGS=-C link-arg=-Wl,-z,max-page-size=16384" \
      cargo build \
        --manifest-path "$MANIFEST" \
        --release \
        --target "$triple"
    local built_so="${CRATE_DIR}/target/${triple}/release/libpreconnect_native.so"
    cp "$built_so" "${out_dir}/libpreconnect_native.so"
    local jni_dir="${ROOT_DIR}/android/app/src/main/jniLibs/${abi}"
    mkdir -p "$jni_dir"
    cp "$built_so" "${jni_dir}/libpreconnect_native.so"
  done
}

build_apple() {
  local platform_name="$1"
  local target_triple
  case "$platform_name" in
    macosx)
      target_triple="aarch64-apple-darwin"
      ;;
    iphoneos)
      target_triple="aarch64-apple-ios"
      ;;
    iphonesimulator)
      if [[ "$(uname -m)" == "x86_64" ]]; then
        target_triple="x86_64-apple-ios-sim"
      else
        target_triple="aarch64-apple-ios-sim"
      fi
      ;;
    *)
      echo "Unsupported Apple platform: ${platform_name}" >&2
      exit 1
      ;;
  esac

  ensure_target "$target_triple"

  local out_dir="${CRATE_DIR}/target/apple/${platform_name}/release"
  mkdir -p "$out_dir"

  cargo build \
    --manifest-path "$MANIFEST" \
    --release \
    --target "$target_triple"

  cp "${CRATE_DIR}/target/${target_triple}/release/libpreconnect_native.a" \
    "${out_dir}/libpreconnect_native.a"
}

if [[ $# -lt 1 ]]; then
  usage
fi

case "$1" in
  android)
    build_android
    ;;
  apple)
    [[ $# -eq 2 ]] || usage
    build_apple "$2"
    ;;
  *)
    usage
    ;;
esac
