# Contributing

Thanks for your interest in contributing. PreConnect is a student-run Flutter app, and beginner contributions are welcome.

## Start Here

Use this guide when you want to build, test, or contribute to the app. You do not need production secrets, release signing keys, or store credentials for normal contribution work.

## What You Need

- Git
- Flutter stable, using Dart from the Flutter SDK
- Android Studio with Android SDK 37.0
- An Android emulator or physical Android device
- Chrome for Chrome extension testing
- Xcode only if you plan to work on iOS or macOS

Linux and Windows contributors can work on Dart, tests, Android, web, documentation, APIs, models, and most shared application code. This repository does not ship Linux or Windows desktop applications. Windows contributors should use WSL or Git Bash for shell scripts such as the extension builder.

On macOS, the Android Studio JDK is recommended for Android builds:

```bash
/Applications/Android Studio.app/Contents/jbr/Contents/Home
```

## First-Time Setup

### Quick Start

```bash
git clone --recurse-submodules https://github.com/sabbirba/preconnect.git
cd preconnect
flutter pub get
cp .env.example .env
flutter run --dart-define-from-file=.env
```

Check your local Flutter setup:

```bash
flutter doctor -v
flutter devices
```

Fix the Flutter Doctor items for the platform you want to run. It is okay if iOS or macOS checks fail when you only plan to work on Android or a browser extension.

## Agent Tooling

Dart 3.9 and newer include the official Dart and Flutter MCP server. This repository enables it for Codex, Claude Code, and VS Code/Copilot through committed project configuration.

```bash
dart mcp-server --version
```

Trust the repository and approve the `dart` MCP server when the client asks, then restart the agent or editor. Repository conventions and the complete build matrix are in [AGENTS.md](AGENTS.md). Claude Code imports the same guide through [CLAUDE.md](CLAUDE.md). The shared contribution workflow is in `.agents/skills/contributor/SKILL.md`.

## Environment File

The extension build script can run without `.env`. Flutter run and build commands in this guide use `.env`, so create it from the committed example first.

Create a local `.env` only when you need overrides:

```bash
cp .env.example .env
```

Blank values are okay for most development:

- normal app development
- debug Android builds
- analyzer checks
- unit tests
- Chrome extension smoke builds

## Optional Environment Values

Only fill env values when you are testing the related feature:

| Key            | Needed for                                   |
| -------------- | -------------------------------------------- |
| `GITHUB_TOKEN` | Optional local contributor-data API requests |

Android release signing uses `android/key.properties`, based on `android/key.properties.example`. Apple signing is configured through Xcode certificates and provisioning profiles. Do not commit `.env`, signing files, tokens, or real credentials.

### Android Debug Fingerprint

If you are setting up local debug builds that interface with Firebase/Google Sign-In integrations, configure the following SHA-1 developer fingerprint in your portal:
`DE:59:46:D4:EF:D3:0B:76:E8:3B:10:B5:8A:B4:D0:CE:BA:EB:E4:B4`

## Repository Tour

- [lib/main.dart](lib/main.dart): mobile and desktop app entrypoint
- [web/extension_app.dart](web/extension_app.dart): Chrome extension entrypoint
- [lib/app.dart](lib/app.dart): app shell, routing, and bootstrap
- [lib/api](lib/api): API clients and service classes
- [lib/model](lib/model): data models and parsing helpers
- [lib/pages](lib/pages): screens and feature UI
- [lib/tools](lib/tools): storage, platform helpers, tokens, and utilities
- [test](test): automated tests
- [tool](tool): project scripts

## Pick a Task

Good first contributions include:

- fixing a typo or unclear text
- improving a small UI state
- adding a focused parsing or model test
- making setup docs clearer
- fixing a small bug with clear reproduction steps

Keep one PR about one topic. Smaller PRs are easier to review and merge.

## Contribution Paths

- Use the bug form for reproducible application, platform, or automation failures.
- Use the feature-idea form for student features, contributor improvements, and project proposals.
- Use the contributor-help form for setup, build, test, MCP, and first-contribution questions.
- Use GitHub Security Advisories for vulnerabilities, token exposure, account access, or private student data. Never file those publicly.

Ideas should define the problem, smallest useful experience, acceptance criteria, affected platforms, privacy impact, offline behavior, and contribution interest. Bug reports should include sanitized reproduction steps, expected and actual behavior, version, platform, and network state.

## Repository Rules

- Keep API, repository, cache, and storage code independent of pages.
- Keep navigation, dialogs, and route replacement in presentation code or configured presentation bridges.
- Store tokens, Wi-Fi credentials, and secrets through `FlutterSecureStorage`; use `AppStorage` only for non-sensitive settings and caches.
- Surface persistence and network failures explicitly.
- Reuse existing models, services, storage keys, widgets, and platform bridges before adding new abstractions.
- Preserve loading, empty, success, error, offline, logout, and mounted-widget behavior.
- Keep native channel names and payloads synchronized across Dart, Android, iOS, macOS, and tests.
- Keep browser-extension CanvasKit and Firebase resources local and compatible with extension CSP.
- Use meaningful snake_case filenames with no more than two words unless a platform requires a fixed name.
- Use Title Case for document headings, workflow display names, issue-form names, and short labels. Use sentence case for descriptions, messages, release notes, and full questions. Preserve official product casing.
- Avoid comments that restate code; retain only non-obvious security, protocol, and platform constraints.
- Do not edit or commit generated files, build output, dependency caches, signing files, or local IDE state.
- Do not manually update release versions in a contribution. Release automation owns version changes.
- Do not include real credentials, student IDs, schedules, QR codes, tokens, cookies, or private account screenshots.

## License and Brand

Contributions are accepted under GPL-3.0. Preserve license and attribution notices, and verify that new dependencies are compatible with GPL-3.0. Distributions and forks must comply with the license and make corresponding source available where required.

The software license does not grant unrestricted use of the PreConnect name, logo, app icon, screenshots, or release identity. Follow [TRADEMARKS.md](TRADEMARKS.md), rebrand forks that could appear official, and do not imply endorsement or affiliation with BRAC University.

## Create a Branch

Create a branch with a short, descriptive name:

```bash
git checkout -b fix/short-description
```

Examples:

- `fix/schedule-empty-state`
- `docs/fixing-bugs`
- `test/seat-status-parser`

## Run the App

Use `flutter run` and pick the target when Flutter prompts you, or use your IDE's run target selector.

```bash
flutter run
```

With env values:

```bash
flutter run --dart-define-from-file=.env
```

The supported browser products are the Chrome and Firefox extensions. For quick UI checks on the web, use your IDE run target or the Flutter device picker, then build the extensions separately with the script below.

## Chrome Extension Testing

Build the extension:

```bash
./tool/build_extension.sh
```

The extension build outputs:

```bash
build/chrome-extension/
build/chrome-extension.zip
build/firefox-extension/
build/firefox-extension.zip
```

Load the unpacked extension:

1. Open `chrome://extensions`.
2. Turn on Developer mode.
3. Click Load unpacked.
4. Select `build/chrome-extension`.

Load the temporary Firefox extension:

1. Open `about:debugging#/runtime/this-firefox`.
2. Click Load Temporary Add-on.
3. Select `build/firefox-extension/manifest.json`.

The script can run even when `.env` is missing; optional dart defines are treated as blank.

## Code Quality Checks

Run these before a PR:

```bash
dart format --output=none --set-exit-if-changed lib web test
flutter analyze
flutter test
```

The test suite covers schedules, authentication, token persistence, logout, cache invalidation, notifications, and platform channels. Add focused tests when you change parsing, models, service behavior, or shared helpers.

## Local Build Smoke Checks

These are useful before changes that touch platform config, release scripts, extension files, or native code.

Android APK:

```bash
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --tree-shake-icons --obfuscate --split-debug-info=build/symbols/android --extra-gen-snapshot-options=--strip --dart-define-from-file=.env
```

If you prefer the Makefile wrapper, `make build` uses the same Android APK release flags.

Android app bundle:

```bash
./tool/build_aab.sh
```

The release AAB includes Android native debug metadata at `SYMBOL_TABLE` level for
Play Console crash/ANR symbolication without bundling full debug symbols.

iOS no-codesign build:

```bash
flutter build ios --release --no-codesign --tree-shake-icons --obfuscate --split-debug-info=build/symbols/ios --extra-gen-snapshot-options=--strip --dart-define-from-file=.env
```

macOS release build:

```bash
flutter build macos --release --tree-shake-icons --obfuscate --split-debug-info=build/symbols/macos --dart-define-from-file=.env
```

Flutter web build:

```bash
flutter build web --release --tree-shake-icons --csp --no-wasm-dry-run --no-web-resources-cdn --dart-define-from-file=.env
```

Chrome extension:

```bash
./tool/build_extension.sh
```

Debug builds do not need signing setup. Real Android release signing uses Gradle properties or `android/key.properties`; keep signing files out of git.

## Manual App Test

Use this quick pass before opening a PR:

1. Launch the app from a clean build.
2. Confirm the app opens without a crash.
3. Visit the screen or flow you changed.
4. Try the empty, loading, success, and error states when they apply.
5. Rotate or resize the screen if the UI is responsive.
6. Check that text is readable on a small device.
7. Check that buttons are tappable on a small device.
8. Run `flutter test` after the manual pass.

For login-dependent screens, note whether you tested with a real BRACU account, cached/offline data, or a non-login fallback path.

## PR Checklist

Before opening a PR, confirm:

- the change is focused
- formatting passes
- analyzer passes
- tests pass
- manual app test is done when UI or behavior changed
- screenshots or screen recordings are attached for visible UI changes
- skipped checks are mentioned with a reason

## PR Description

Include:

- what changed
- why it changed
- how you tested it
- device or emulator used
- linked issue, when one exists

## Community Help

Use [GitHub issues](https://github.com/sabbirba/preconnect/issues) for trackable app questions, contributor onboarding, project direction, bugs, and scoped feature requests. Use the community Discord linked from [README.md](README.md) for informal discussion.

For bugs, include:

- platform
- app version or commit
- steps to reproduce
- expected behavior
- actual behavior
- screenshot or screen recording when useful

## Security and Privacy

- Do not commit secrets, tokens, private student data, or real credentials.
- Avoid logging access tokens or personal data.
- Keep `.env`, `android/key.properties`, and keystores out of git.
- Report security-sensitive issues privately using [SECURITY.md](SECURITY.md).
