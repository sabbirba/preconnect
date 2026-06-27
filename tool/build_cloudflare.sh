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

echo "=== Flutter Pub Get ==="
flutter pub get

echo "=== Building Flutter Web ==="
flutter build web --release

echo "=== Build Complete ==="
