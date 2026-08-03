# PreConnect Agent Guide

## Product

PreConnect is a Flutter academic companion for BRAC University students. Supported outputs are Android APK/AAB, iOS, macOS, Flutter web, Chrome extension, and Firefox extension. Linux and Windows users are welcome contributors and can run shared Dart checks, tests, Android, and web work. The repository does not produce Linux or Windows desktop applications.

## Requirements

- Flutter stable; the app requires Dart 3.8.1 or newer and MCP requires Dart 3.9 or newer
- Git
- Android Studio, Android SDK 37.0, and a compatible JDK for Android
- Xcode on macOS for iOS and macOS
- Chrome for extension testing
- Ruby and Bundler only for Fastlane release or store tasks
- Node.js only for Firefox publishing automation

Windows contributors should use WSL or Git Bash for repository shell scripts. iOS and macOS builds require macOS and Xcode.

## Setup

```bash
flutter doctor -v
flutter pub get
cp .env.example .env
flutter devices
```

The app runs without production credentials. `GITHUB_TOKEN` is optional for local contributor-data requests. Never commit `.env`, signing files, tokens, provisioning profiles, private student data, or generated credentials.

## Entry Points

- `lib/main.dart`: Android, iOS, and macOS
- `web/extension_app.dart`: Chrome and Firefox extension UI
- `web/background.dart`: extension background worker
- `lib/app.dart`: bootstrap, routing, platform bridges, and application lifecycle
- `lib/api`: remote services and repositories
- `lib/model`: shared domain models
- `lib/pages`: presentation
- `lib/tools`: storage, HTTP, native bridges, and shared utilities
- `test`: automated tests
- `tool`: release and extension scripts

The app is 100% databaseless — it uses 0 database engines (no Cloud Firestore, Realtime Database, or remote database). Keep API and storage layers independent of pages. Keep navigation and dialogs in presentation bridges. Store authentication tokens, Wi-Fi credentials, and other secrets through `FlutterSecureStorage`; use `AppStorage` only for non-sensitive settings and caches. Surface persistence failures instead of swallowing them.

## Run

```bash
flutter run --dart-define-from-file=.env
flutter run -d chrome --dart-define-from-file=.env
```

Use the packaged extension build for extension-specific behavior:

```bash
./tool/build_extension.sh
```

Load `build/chrome-extension` from `chrome://extensions`. Firefox output is `build/firefox-extension`.

## Build

Android APK:

```bash
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --tree-shake-icons --obfuscate --split-debug-info=build/symbols/android --extra-gen-snapshot-options=--strip --dart-define-from-file=.env
```

Android AAB:

```bash
./tool/build_aab.sh
```

iOS unsigned contributor build:

```bash
flutter build ios --release --no-codesign --tree-shake-icons --obfuscate --split-debug-info=build/symbols/ios --extra-gen-snapshot-options=--strip --dart-define-from-file=.env
```

iOS signed maintainer build:

```bash
flutter build ipa --release --tree-shake-icons --obfuscate --split-debug-info=build/symbols/ios --extra-gen-snapshot-options=--strip --dart-define-from-file=.env --export-options-plist=ios/ExportOptions.plist
```

macOS:

```bash
flutter build macos --release --tree-shake-icons --obfuscate --split-debug-info=build/symbols/macos --dart-define-from-file=.env
```

Web:

```bash
flutter build web --release --tree-shake-icons --csp --no-wasm-dry-run --no-web-resources-cdn --dart-define-from-file=.env
```

Chrome and Firefox extensions:

```bash
./tool/build_extension.sh
```

Android release signing uses `android/key.properties`, based on `android/key.properties.example`. Apple signed builds require matching certificates and provisioning profiles. Contributor verification should use unsigned iOS output when signing material is unavailable.

## Verification

Run after every code change:

```bash
dart format --output=none --set-exit-if-changed lib web test
flutter analyze
flutter test
```

Run the affected platform build after changing native configuration, dependencies, manifests, entitlements, release scripts, or platform channels. Run `./tool/build_extension.sh` after changing `web`, conditional web implementations, Firebase web setup, CanvasKit loading, or extension manifests.

## Repository Rules

- Preserve existing user changes and inspect the worktree before editing.
- Keep changes focused and avoid unrelated refactors.
- Keep one pull request focused on one bug, feature, or maintenance concern.
- Do not manually bump versions; release automation owns version changes.
- Use meaningful snake_case filenames with no more than two words.
- Use Title Case for document headings, workflow display names, issue-form names, and short labels. Use sentence case for descriptions, messages, release notes, and full questions. Preserve official product casing.
- Reuse existing services, widgets, models, and constants before adding another abstraction.
- Do not add fallback pages, duplicate navigation paths, silent exception handling, committed secrets, or generated build files.
- Do not edit generated Flutter, CocoaPods, Swift Package Manager, Gradle, or build output files.
- Do not use real student credentials, IDs, schedules, tokens, or account screenshots in tests, issues, logs, or fixtures.
- Keep browser-extension CanvasKit and Firebase resources local and compatible with extension CSP.
- Update tests when authentication, logout, refresh, storage, cache invalidation, FCM, schedules, or platform-channel behavior changes.
- Preserve GPL-3.0 notices and use license-compatible dependencies.
- Treat the PreConnect name, logo, icon, screenshots, and release branding under `TRADEMARKS.md`; forks must not imply official status.
- Describe PreConnect as a student-run project and do not imply BRAC University endorsement.
- Send vulnerabilities and sensitive reports through `SECURITY.md`, never a public issue.
- Follow `CODE_OF_CONDUCT.md` in issues, reviews, discussions, and project spaces.
- Report skipped validation and the exact reason.

## Agent Workflow

Use the repository skill at `.agents/skills/contributor/SKILL.md` for feature ideas, bug fixes, issue triage, reviews, documentation, platform work, and releases. Agents that do not discover repository skills automatically must read that file before performing those workflows.

## MCP

The repository uses the official Dart and Flutter MCP server provided by the installed Dart SDK. Project adapters are committed for Codex, Claude Code, and VS Code/Copilot. Restart the agent or editor after cloning, trust the repository when requested, and verify the `dart` server with the client's MCP status command.
