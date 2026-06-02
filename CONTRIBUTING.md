# Contributing

Thanks for your interest in contributing. PreConnect is a student-run Flutter app, and beginner contributions are welcome.

## Start Here

Use this guide when you want to build, test, or contribute to the app. You do not need production secrets, release signing keys, or store credentials for normal contribution work.

## What You Need

- Git
- Flutter stable, using Dart from the Flutter SDK
- Android Studio with Android SDK
- An Android emulator or physical Android device
- Chrome for Chrome extension testing
- Xcode only if you plan to work on iOS or macOS

On macOS, the Android Studio JDK is recommended for Android builds:

```bash
/Applications/Android Studio.app/Contents/jbr/Contents/Home
```

## First-Time Setup

Clone the repo and install packages:

```bash
git clone https://github.com/sabbirba/preconnect.git
cd preconnect
flutter pub get
```

### Automated Developer Setup (Recommended)

To reduce manual setup and avoid guesswork for contributors, the repo includes
an automated bootstrap script and convenient Makefile + wrapper. The script
handles installing Android command-line tools, a recommended NDK and CMake,
accepts SDK licenses, and prepares local environment helpers.

Quick Start (Short):

```bash
git clone https://github.com/sabbirba/preconnect.git
cd preconnect
make setup
make run
```

What the setup does:
- Installs Android cmdline-tools (if missing), NDK, and CMake using `sdkmanager`.
- Writes `android/local.properties` with `sdk.dir` and `ndk.dir` (a .bak is kept if it existed).
- Creates `.env.local.sh` that exports `ANDROID_SDK_ROOT` and `ANDROID_NDK_HOME` — the `dev` wrapper sources this automatically.
- Adds Rust Android targets (via `rustup`) if rustup is available.
- Runs `flutter pub get` to fetch Dart dependencies.

Important notes:
- `android/local.properties` is local machine configuration. Do NOT commit it.
- The script accepts SDK licenses automatically; ensure you are comfortable with that before running it on shared machines.
- The script downloads binaries from Google's official URLs; it requires network access and may take several minutes.

If you prefer not to use `make`, you can run the setup script directly:

```bash
./tool/dev_setup.sh
source .env.local.sh  # or use ./dev to run commands with the env loaded
./dev flutter run --dart-define-from-file=.env
```

Windows PowerShell Alternative:

```powershell
.\tool\dev_setup.ps1
.\dev.ps1 flutter run --dart-define-from-file=.env
```

If you encounter issues, open an issue describing your OS, the step that failed,
and the output printed by the script.


Check your local Flutter setup:

```bash
flutter doctor -v
flutter devices
```

Fix the Flutter Doctor items for the platform you want to run. It is okay if iOS or macOS checks fail when you only plan to work on Android or the Chrome extension.

## Environment File

The helper scripts can run without `.env`. When `.env` is missing, they create a temporary empty env file so optional dart defines stay blank and normal app builds can continue.

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

## Optional Env Values

Only fill env values when you are testing the related feature:

| Key                | Needed for              |
| ------------------ | ----------------------- |
| `DEVELOPMENT_TEAM` | iOS signing             |
| `storeFile`        | Android release signing |
| `storePassword`    | Android release signing |
| `keyAlias`         | Android release signing |
| `keyPassword`      | Android release signing |

Do not commit `.env`, `android/key.properties`, keystores, tokens, or real credentials.

## Repo Tour

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

The supported browser product is the Chrome extension. For quick UI checks on the web, use your IDE run target or the Flutter device picker, then build the extension separately with the script below.

## Chrome Extension Testing

Build the extension:

```bash
./tool/build_chrome_extension.sh
```

The extension build outputs:

```bash
build/chrome-extension/
build/chrome-extension.zip
```

Load the unpacked extension:

1. Open `chrome://extensions`.
2. Turn on Developer mode.
3. Click Load unpacked.
4. Select `build/chrome-extension`.

The script can run even when `.env` is missing; optional dart defines are treated as blank.

## Code Quality Checks

Run these before a PR:

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

Current tests live in [test/schedule_parsing_test.dart](test/schedule_parsing_test.dart). Add focused tests when you change parsing, models, service behavior, or shared helpers.

## Local Build Smoke Checks

These are useful before changes that touch platform config, release scripts, extension files, or native code.

Android APK:

```bash
flutter build apk --release --split-per-abi
```

Android APK with env values:

```bash
flutter build apk --release --split-per-abi --tree-shake-icons --obfuscate --split-debug-info=build/symbols/android --extra-gen-snapshot-options=--strip --dart-define-from-file=.env
```

Android app bundle:

```bash
flutter build appbundle --release --target-platform android-arm,android-arm64
```

Android app bundle with env values:

```bash
flutter build appbundle --release --target-platform android-arm,android-arm64 --tree-shake-icons --obfuscate --split-debug-info=build/symbols/android --dart-define-from-file=.env
```

The release AAB includes Android native debug metadata at `SYMBOL_TABLE` level for
Play Console crash/ANR symbolication without bundling full debug symbols.

iOS no-codesign build:

```bash
flutter build ipa --no-codesign
```

iOS no-codesign build with env values:

```bash
flutter build ipa --no-codesign --dart-define-from-file=.env
```

Chrome extension:

```bash
./tool/build_chrome_extension.sh
```

Debug builds do not need signing setup. Real Android release signing uses `.env`, Gradle properties, or `android/key.properties`; keep signing files out of git.

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

Use [GitHub issues](https://github.com/sabbirba/preconnect/issues) for app questions, contributor onboarding, project direction, bugs, and scoped feature requests until a public chat server invite is available.

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
