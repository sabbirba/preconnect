#!/bin/bash
set -e
FLUTTER_DIR="$HOME/flutter"
if [ ! -d "$FLUTTER_DIR" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"
flutter doctor
if [ ! -f ".env" ]; then
  touch .env
  for key in storeFile storePassword keyAlias keyPassword DEVELOPMENT_TEAM GITHUB_TOKEN GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REDIRECT_URI GOOGLE_SCOPES; do
    val=$(eval echo \$$key)
    if [ -n "$val" ]; then
      echo "$key=$val" >> .env
    fi
  done
  env | grep -E '^(APP_|PRECONNECT_)' >> .env || true
fi

flutter pub get
flutter build web --release --tree-shake-icons --csp --no-wasm-dry-run --no-web-resources-cdn --dart-define-from-file=.env
