SHELL := /bin/bash
.PHONY: setup analyze run build build-aab test

setup:
	flutter pub get

analyze:
	flutter analyze

run:
	flutter run --dart-define-from-file=.env

build:
	flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 \
		--tree-shake-icons --obfuscate \
		--split-debug-info=build/symbols/android --extra-gen-snapshot-options=--strip \
		--dart-define-from-file=.env

build-aab:
	./tool/build_aab.sh

test:
	flutter test
