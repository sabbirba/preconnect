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

### Install dependencies
```bash
flutter pub get
```

### Run the app
```bash
flutter run
```

### Local Configuration
1. Copy `.env.example` to `.env` and fill values.
2. For Android release builds, copy `android/key.properties.example` to `android/key.properties`.

### Build (Android Release)
```bash
flutter build appbundle --release --dart-define-from-file=.env
```

### Quality Checks
```bash
flutter analyze
flutter test
```

## Project Structure

```
lib/        Flutter source code 
android/    Android configuration
ios/        iOS configuration
macos/      macOS shell
windows/    Windows shell
linux/      Linux shell
web/        Web shell
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
