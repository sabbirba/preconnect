#!/bin/bash
set -e

echo "=== Installing Flutter SDK ==="
FLUTTER_DIR="$HOME/flutter"
if [ ! -d "$FLUTTER_DIR" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

echo "=== Flutter Doctor ==="
flutter doctor

echo "=== Generating .env file from environment ==="
if [ ! -f ".env" ]; then
  touch .env
  for key in storeFile storePassword keyAlias keyPassword DEVELOPMENT_TEAM GITHUB_TOKEN; do
    val=$(eval echo \$$key)
    if [ -n "$val" ]; then
      echo "$key=$val" >> .env
    fi
  done
  env | grep -E '^(APP_|PRECONNECT_)' >> .env || true
fi

echo "=== Flutter Pub Get ==="
flutter pub get

echo "=== Building Flutter Web ==="
flutter build web --release --tree-shake-icons --csp --no-wasm-dry-run --no-web-resources-cdn --dart-define-from-file=.env

echo "=== Build Complete ==="
