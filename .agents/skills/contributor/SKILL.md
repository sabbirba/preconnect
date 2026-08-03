---
name: contributor
description: Investigate, implement, validate, or review contributions to the repository. Use for bug fixes, feature ideas, issue triage, pull-request reviews, contributor onboarding, documentation, dependencies, authentication, storage, schedules, notifications, platform channels, browser extensions, native configuration, wifi printer, bus tracking, student profile, CGPA visibility, and release automation.
---

# Contributor

## Architecture & Module Structure

- **Entry Points**:
  - `lib/main.dart`: Android, iOS, macOS application entry.
  - `web/extension_app.dart`: Chrome and Firefox extension UI entry.
  - `web/background.dart`: Extension background Service Worker (pure Dart runtime).
  - `lib/app.dart`: Bootstrap, declarative routing, platform bridges, and app lifecycle.
- **Domain & API (`lib/api`, `lib/model`)**:
  - Keep domain models in `lib/model/` pure and independent of `package:flutter/material.dart` or `dart:ui`.
  - Maintain API services (`ApiConfig`, `ScheduleService`, `ProfileService`, `PaymentService`, `FundingService`, `FcmService`) decoupled from presentation.
- **Presentation (`lib/pages`)**:
  - `home_sections/`, `student_profile_sections/`, `custom_schedules_sections/`, `notifications_sections/`, `bus/`.
  - Shared UI system in `lib/pages/ui_kit.dart` (`BracuPageScaffold`, `BracuPalette`, `BracuActionButton`, `BracuRefreshList`).
  - Virtual ID card rendering in `lib/pages/card_section.dart`.
  - Contributor layout and adaptive grids in `lib/pages/devs.dart`.
  - Wi-Fi Printer tool in `lib/pages/wifi_printer.dart`.
- **Storage & Infrastructure (`lib/tools`)**:
  - Use `FlutterSecureStorage` for tokens, Wi-Fi credentials, and secrets.
  - Use `AppStorage` for non-sensitive settings, preferences, and local caches.
  - Use `CdnJsonCache` for CDN-backed JSON assets.

## Core Features & Subsystems

1. **Schedules & Academic Companion**:
   - Class schedules, exam schedules, custom schedule editor, friend schedule sharing, schedule scanning, seat status tracking, lab sections, advising phases.
2. **Student Profile & Financials**:
   - Virtual Student ID card preloading and display.
   - Academic summary with togglable CGPA visibility (blank when obscured, eye icon toggle).
   - Payslip details and student fee payment portfolio integration.
3. **Campus Tools**:
   - Wi-Fi Printer (Campus Printer) file upload and print configuration.
   - Bus schedule tracker and route lookup.
   - DSpace digital library repository browser.
4. **Browser Extension**:
   - Chrome Manifest V3 and Firefox Manifest V2/V3 compatibility.
   - Service worker background script (`web/background.dart`) compiled with `dart compile js`. Must never depend on `dart:ui` or Flutter UI packages.
   - Build using `./tool/build_extension.sh`.

## Implementation Rules

- **Clean Code & No Comments**: Do not add inline comments, JSDoc, or docstrings to code files. Keep code clean and readable.
- **Layout & Responsiveness**:
  - Use fluid, unconstrained adaptive layouts (`Wrap`, `LayoutBuilder`, `Flexible`, `Expanded`).
  - Avoid arbitrary clamps or hardcoded column limits on grid views.
  - Ensure uniform font sizing and wrapping for long text labels without premature truncation.
- **No Leftover Fallbacks**:
  - Avoid rendering fallback text cards or empty prompt containers when profile or card data is preloading.
  - Render clean, non-intrusive widgets (`SizedBox.shrink()`) when optional data is absent.
- **Error Handling & State**:
  - Surface persistence and network failures explicitly.
  - Handle loading, error, empty, offline, and unmounted widget states safely.
- **Platform Separation**:
  - Keep conditional imports valid for native, web, and extension environments.

## Validation Workflow

Always run verification after every code change:

```bash
dart format --output=none --set-exit-if-changed lib web test
flutter analyze
flutter test
```

For extension, web, or background worker changes, also run:

```bash
./tool/build_extension.sh --no-pub
```

For native platform changes, build the target platform:

- Android: `flutter build apk --release`
- iOS / macOS: `flutter build ios --release --no-codesign` / `flutter build macos --release`
- Web: `flutter build web --release`
