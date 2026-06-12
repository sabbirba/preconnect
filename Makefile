SHELL := /bin/bash
.PHONY: setup analyze run build build-aab test

setup:
	flutter pub get

analyze:
	flutter analyze

run:
	flutter run --dart-define-from-file=.env

build:
	flutter build apk --release --split-per-abi --tree-shake-icons --obfuscate \
		--split-debug-info=build/symbols/android --extra-gen-snapshot-options=--strip \
		--dart-define-from-file=.env

build-aab:
	flutter build appbundle --release --target-platform android-arm,android-arm64 \
		--tree-shake-icons --obfuscate --split-debug-info=build/symbols/android \
		--dart-define-from-file=.env

test:
	flutter test
