SHELL := /bin/bash
.PHONY: setup analyze run build test

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

test:
	./dev flutter test
