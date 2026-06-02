SHELL := /bin/bash
.PHONY: setup analyze run build build-aab test

setup:
	@echo "Running project setup (may require network and some minutes)..."
	./tool/dev_setup.sh

analyze:
	./dev flutter analyze

run:
	./dev flutter run --dart-define-from-file=.env

build:
	./dev flutter build apk --release --split-per-abi --tree-shake-icons --obfuscate \
		--split-debug-info=build/symbols/android --extra-gen-snapshot-options=--strip \
		--dart-define-from-file=.env

build-aab:
	./dev flutter build appbundle --release --target-platform android-arm,android-arm64 \
		--tree-shake-icons --obfuscate --split-debug-info=build/symbols/android \
		--dart-define-from-file=.env

test:
	./dev flutter test
