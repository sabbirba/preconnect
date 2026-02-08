# PreConnect

Flutter app for BRACU students (SSO login + Connect API).

**Project Portfolio**
- Overview: fast, calm academic companion with schedules, exams, alarms, and QR sharing.
- Core screens: Dashboard, Profile, Schedule, Exams, Friends (QR), Alarms.
- Experience goals: cache-first, offline-friendly, instant feel, predictable navigation.

**Links**
- Code of Conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security: [SECURITY.md](SECURITY.md)
- License: [LICENSE](LICENSE)
- Environment Example: [.env.example](.env.example)
- Android Signing Example: [android/key.properties.example](android/key.properties.example)
- Workflows: [.github/workflows/release.yml](.github/workflows/release.yml), [.github/workflows/bump-version.yml](.github/workflows/bump-version.yml)
- Screenshots: [screenshots/](screenshots/)

**Screenshots**
<div>
<img src="screenshots/Apple iPhone 16 Pro Max Screenshot 1.png" alt="Apple iPhone 16 Pro Max Screenshot 1" width="240" />
<img src="screenshots/Apple iPhone 16 Pro Max Screenshot 2.png" alt="Apple iPhone 16 Pro Max Screenshot 2" width="240" />
<img src="screenshots/Apple iPhone 16 Pro Max Screenshot 3.png" alt="Apple iPhone 16 Pro Max Screenshot 3" width="240" />
</div>

**Highlights**
- Clear hierarchy and card-first layout for scanability.
- Bright primary/accent colors with soft gradients.
- Cache-first loading with background refresh.
- Offline-friendly behavior with safe fallbacks.

**UI System**
- Primary: `#1E6BE3`
- Accent: `#22B573`
- Light background: `#EAF4FF` to `#F3FFF4`
- Dark background: `#000000`
- Titles: 16–18px, semi-bold
- Body: 11–14px, regular
- Cards: padding 14–16px, radius 18–22px

**Quick Start**
```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

**Local Config**
1. Copy `.env.example` to `.env` and fill values.
2. For Android release builds, copy `android/key.properties.example` to `android/key.properties`.

**Build (Android Production)**
```bash
flutter build appbundle --release --dart-define-from-file=.env
```

**Quality Checks**
```bash
flutter analyze
flutter test
```

**Project Structure**
- `lib/` Flutter source code
- `android/` Android build config
- `ios/` iOS build config
- `macos/`, `windows/`, `linux/`, `web/` platform shells

**Developer Credit**
- NaiveInvestigator — GitHub: [@NaiveInvestigator](https://github.com/NaiveInvestigator)
- Sabbir Bin Abbas — GitHub: [@sabbirba](https://github.com/sabbirba)

**Licenses**
- Project license: GPL-3.0 (see [LICENSE](LICENSE)).
- Third-party licenses: each package is distributed under its own license (see the package page on [pub.dev](https://pub.dev)).
