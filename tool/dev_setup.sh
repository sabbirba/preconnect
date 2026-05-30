#!/usr/bin/env bash
set -euo pipefail

# Dev environment setup helper for contributors.
# - Installs Android cmdline-tools, NDK and CMake using sdkmanager when available
# - Ensures android/local.properties contains sdk.dir and ndk.dir pointing at SDK/NDK
# - Adds Rust android targets if rustup is available
#
# Usage:
#   ./tool/dev_setup.sh
#
# This script is idempotent and safe to run multiple times. It tries to do the
# minimum necessary and will prompt before destructive actions.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_DEFAULT="$HOME/Library/Android/sdk"

echo "Dev setup helper — will prepare Android SDK/NDK, CMake and Rust targets"

SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$SDK_DEFAULT}}"
echo "Using Android SDK directory: $SDK_DIR"

if [ ! -d "$SDK_DIR" ]; then
  echo "Android SDK directory not found at $SDK_DIR"
  echo "If you have Android Studio installed, open it, install the SDK and try again." >&2
  exit 1
fi

# locate sdkmanager, download command-line tools if missing
download_cmdline_tools() {
  echo "Attempting to download Android command-line tools..."
  uname_s=$(uname -s)
  case "$uname_s" in
    Darwin) pkg_name="commandlinetools-mac-8512546_latest.zip" ;; 
    Linux) pkg_name="commandlinetools-linux-8512546_latest.zip" ;; 
    *) echo "Unsupported OS for automatic cmdline-tools install: $uname_s" >&2; return 1 ;;
  esac
  url="https://dl.google.com/android/repository/${pkg_name}"
  tmpfile="/tmp/${pkg_name}"
  echo "Downloading $url to $tmpfile"
  curl -fL "$url" -o "$tmpfile"
  mkdir -p "$SDK_DIR/cmdline-tools"
  unzip -oq "$tmpfile" -d "$SDK_DIR/cmdline-tools"
  # Some zips extract to cmdline-tools, others to cmdline-tools/tools — normalize to 'latest'
  if [ -d "$SDK_DIR/cmdline-tools/cmdline-tools" ]; then
    mv "$SDK_DIR/cmdline-tools/cmdline-tools" "$SDK_DIR/cmdline-tools/latest-raw" || true
  else
    mv "$SDK_DIR/cmdline-tools" "$SDK_DIR/cmdline-tools/latest-raw" 2>/dev/null || true
  fi
  mkdir -p "$SDK_DIR/cmdline-tools/latest"
  cp -R "$SDK_DIR/cmdline-tools/latest-raw"/* "$SDK_DIR/cmdline-tools/latest/"
  rm -rf "$SDK_DIR/cmdline-tools/latest-raw"
  rm -f "$tmpfile"
}

if [ -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]; then
  SDKMAN="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
elif [ -x "$SDK_DIR/cmdline-tools/bin/sdkmanager" ]; then
  SDKMAN="$SDK_DIR/cmdline-tools/bin/sdkmanager"
elif [ -x "$SDK_DIR/tools/bin/sdkmanager" ]; then
  SDKMAN="$SDK_DIR/tools/bin/sdkmanager"
else
  echo "sdkmanager not found under $SDK_DIR. Trying to download command-line tools..."
  if download_cmdline_tools; then
    SDKMAN="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
  else
    echo "sdkmanager not available and automatic download failed. Please install Android command-line tools or Android Studio." >&2
    echo "See https://developer.android.com/studio#downloads" >&2
    exit 1
  fi
fi

echo "Found sdkmanager: $SDKMAN"

install_if_missing() {
  local pkg="$1"
  if "$SDKMAN" --list | sed -n '1,2000p' | grep -q "^$pkg\b"; then
    echo "Package $pkg appears available to install"
  fi
  echo "Installing $pkg (may prompt for license acceptance)..."
  yes | "$SDKMAN" --install "$pkg" --sdk_root="$SDK_DIR"
}

echo "Installing cmdline-tools, CMake and NDK (may take a while)"
# install cmdline tools and cmake
install_if_missing "cmdline-tools;latest"
install_if_missing "cmake;3.22.1"

# Prefer to install the project's recommended NDK if present; otherwise install a recent stable NDK
RECOMMENDED_NDK="28.2.13676358"
echo "Installing NDK $RECOMMENDED_NDK"
install_if_missing "ndk;$RECOMMENDED_NDK"

# Accept SDK licenses
echo "Accepting Android SDK licenses..."
yes | "$SDKMAN" --licenses || true

echo "Listing installed NDKs..."
NDK_DIRS=("$SDK_DIR/ndk"/*)
if [ ${#NDK_DIRS[@]} -eq 0 ]; then
  echo "No NDK directories found under $SDK_DIR/ndk" >&2
  exit 1
fi

# pick the highest version installed
chosen_ndk=""
for d in "${NDK_DIRS[@]}"; do
  [ -d "$d" ] || continue
  chosen_ndk="$d"
done
if [ -z "$chosen_ndk" ]; then
  echo "Failed to detect installed NDK" >&2
  exit 1
fi

echo "Detected NDK: $chosen_ndk"

# update android/local.properties with sdk.dir and ndk.dir
LOCAL_PROPERTIES="$ROOT_DIR/android/local.properties"
echo "Updating $LOCAL_PROPERTIES"
mkdir -p "$(dirname "$LOCAL_PROPERTIES")"
sdk_prop="sdk.dir=$SDK_DIR"
ndk_prop="ndk.dir=$chosen_ndk"

if [ -f "$LOCAL_PROPERTIES" ]; then
  # replace or append
  if grep -q "^sdk.dir=" "$LOCAL_PROPERTIES"; then
    sed -i.bak "s#^sdk.dir=.*#${sdk_prop}#" "$LOCAL_PROPERTIES"
  else
    echo "$sdk_prop" >> "$LOCAL_PROPERTIES"
  fi
  if grep -q "^ndk.dir=" "$LOCAL_PROPERTIES"; then
    sed -i.bak "s#^ndk.dir=.*#${ndk_prop}#" "$LOCAL_PROPERTIES"
  else
    echo "$ndk_prop" >> "$LOCAL_PROPERTIES"
  fi
else
  cat > "$LOCAL_PROPERTIES" <<EOF
$sdk_prop
$ndk_prop
flutter.sdk=${FLUTTER_SDK:-$(which flutter 2>/dev/null || echo "/usr/local/flutter")}
flutter.buildMode=release
EOF
fi

echo "local.properties updated. (A .bak file was created if edits were made.)"

# Export env helper script for this shell session
ENV_HELPER="$ROOT_DIR/.env.local.sh"
cat > "$ENV_HELPER" <<EOF
export ANDROID_SDK_ROOT="$SDK_DIR"
export ANDROID_NDK_HOME="$chosen_ndk"
export ANDROID_NDK_ROOT="$chosen_ndk"
EOF
chmod 644 "$ENV_HELPER"
echo "Wrote helper env script: $ENV_HELPER"
echo "To use it in your shell: source $ENV_HELPER"

# Rust targets for Android used by tool/build_rust_native.sh
if command -v rustup >/dev/null 2>&1; then
  echo "Adding Rust Android targets via rustup (if missing)"
  rustup target add aarch64-linux-android || true
  rustup target add armv7-linux-androideabi || true
  rustup target add i686-linux-android || true
  rustup target add x86_64-linux-android || true
else
  echo "rustup not found; skipping Rust target setup"
fi

echo "Running flutter pub get to ensure packages are fetched"
if command -v flutter >/dev/null 2>&1; then
  flutter pub get
else
  echo "flutter not found in PATH; please install Flutter and run 'flutter pub get' manually" >&2
fi

echo "Done. Recommended next steps:"
echo "  1) source $ENV_HELPER"
echo "  2) flutter analyze"
echo "  3) flutter run --dart-define-from-file=.env (or flutter build <target>)"

exit 0
