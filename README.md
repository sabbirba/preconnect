<div align="center">

# PreConnect

Fast, Calm Academic Companion App.
An initiative run by [BRAC University](https://bracu.ac.bd) students.

![GitHub Release](https://img.shields.io/github/v/release/sabbirba/preconnect?label=latest%20version&&color=dark-green) ![License](https://img.shields.io/badge/license-GPL3.0-blue)

</div>

## Overview

A Flutter app for BRAC University students with SSO login and Connect API integration.

### Key features

- Simple, predictable navigation
- Class schedules and exam tracking
- Smart alarms and reminders
- QR-based friend sharing
- Offline-friendly, cache-first experience

## Screenshots
<div>
<img src="screenshots/Apple iPhone 16 Pro Max Screenshot 1.png" alt="Apple iPhone 16 Pro Max Screenshot 1" width="240" />
<img src="screenshots/Apple iPhone 16 Pro Max Screenshot 2.png" alt="Apple iPhone 16 Pro Max Screenshot 2" width="240" />
<img src="screenshots/Apple iPhone 16 Pro Max Screenshot 3.png" alt="Apple iPhone 16 Pro Max Screenshot 3" width="240" />
</div>

## Design System

### Colors

- Primary: `#1E6BE3`
- Accent: `#22B573`
- Light background: `#EAF4FF` to `#F3FFF4`
- Dark background: `#000000`

### Typography

- Titles: 16–18 px, semibold
- Body: 11–14 px, regular

### Layout

- Card-first UI
- Padding: 14–16 px
- Radius: 18–22 px

## Getting Started

### Prerequisites

#### Flutter SDK
```bash
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
flutter doctor
```

#### System Dependencies (Linux)
```bash
sudo apt-get update
sudo apt-get install curl git unzip xz-utils zip libglu1-mesa \
  clang cmake ninja-build pkg-config libgtk-3-dev
```

#### Android SDK
Install [Android Studio](https://developer.android.com/studio) or via snap:
```bash
sudo snap install android-studio --classic
```
Then install Android SDK (API 33+), SDK Command-line Tools, and Build-Tools. Accept licenses:
```bash
flutter doctor --android-licenses
```

### Install dependencies
```bash
flutter pub get
```

### Local Configuration
1. Copy `.env.example` to `.env` and fill values.
2. For Android release builds, copy `android/key.properties.example` to `android/key.properties`.

### Run the app
```bash
# Check connected devices
flutter devices

# Run on connected device or emulator
flutter run
```

While running:
- `r` — hot reload (keeps state)
- `R` — hot restart (resets state)
- `q` — quit

### Build (Android Release)
```bash
flutter build appbundle --release --dart-define-from-file=.env
```

### Quality Checks
```bash
flutter analyze
flutter test
```

### Troubleshooting

```bash
# Verbose doctor output
flutter doctor -v

# Clean rebuild
flutter clean && flutter pub get

# Clean Android build
cd android && ./gradlew clean && cd .. && flutter clean && flutter pub get

# Restart ADB if device not found
adb kill-server && adb start-server
```

## Project Structure

```
lib/
  main.dart          Entry point
  app.dart           App shell & routing
  api/               Auth & API client
  model/             Data models
  pages/             UI screens & sections
  tools/             Utilities (caching, helpers, etc.)
android/             Android configuration (Kotlin)
ios/                 iOS configuration (Swift)
macos/               macOS shell
windows/             Windows shell
linux/               Linux shell
web/                 Web shell
assets/              Icons & SVGs
scripts/             Build & CI helpers
```

## Documentation & Policies

- Code of Conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security: [SECURITY.md](SECURITY.md)
- Environment Example: [.env.example](.env.example)
- Android Signing Example: [android/key.properties.example](android/key.properties.example)
- Workflows: [.github/workflows/release.yml](.github/workflows/release.yml), [.github/workflows/bump-version.yml](.github/workflows/bump-version.yml)

## Developer Credit
- NaiveInvestigator — GitHub: [@NaiveInvestigator](https://github.com/NaiveInvestigator)
- Sabbir Bin Abbas — GitHub: [@sabbirba](https://github.com/sabbirba)

## Licenses
This project is licensed under GPL-3.0 (see [LICENSE](LICENSE)).

Third-party packages follow their own license (see package pages on [pub.dev](https://pub.dev)).
