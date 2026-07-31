---
name: preconnect-contributor
description: Investigate, implement, validate, or review contributions to the PreConnect Flutter repository. Use for bug fixes, feature ideas, issue triage, pull-request reviews, contributor onboarding, documentation, dependencies, authentication, storage, schedules, notifications, platform channels, browser extensions, native configuration, and release automation.
---

# PreConnect Contributor

## Establish Scope

1. Read `AGENTS.md` and inspect the current worktree.
2. Read `CONTRIBUTING.md` for contributor and validation requirements.
3. Classify the request before editing:
   - Security or private student data: read `SECURITY.md`; keep details out of public issues and logs.
   - Branding, forks, screenshots, names, icons, or distribution: read `TRADEMARKS.md`.
   - Licensing or redistribution: read `LICENSE` and preserve GPL-3.0 obligations.
   - Community moderation: read `CODE_OF_CONDUCT.md`.
   - Release or store work: inspect the relevant workflow and Fastlane configuration.
4. Search for existing implementations, issues represented in code, tests, and reusable components.
5. Preserve unrelated user changes and avoid expanding the task without evidence.

## Handle Ideas

1. State the student or contributor problem.
2. Identify affected platforms and existing related features.
3. Check authentication, privacy, offline behavior, caching, permissions, accessibility, and failure states.
4. Define a small first release with observable acceptance criteria.
5. Prefer extending an existing service or screen over adding a parallel system.
6. Record open product decisions instead of inventing policy or upstream API behavior.

## Fix Bugs

1. Reproduce the failure or establish it from code and logs.
2. Identify the owning layer and root cause.
3. Add or update a regression test when the behavior is testable.
4. Make the smallest complete fix.
5. Exercise loading, empty, success, error, offline, logout, and mounted-widget behavior when relevant.
6. Verify every affected platform contract.

## Implement Changes

- Keep secrets in `FlutterSecureStorage`; keep only non-sensitive settings and caches in `AppStorage`.
- Preserve explicit persistence and network failures.
- Keep API, repository, and storage layers independent of presentation.
- Route navigation and dialogs through presentation bridges.
- Reuse existing models, storage keys, widgets, cache helpers, and platform bridges.
- Keep conditional imports valid for native, web, and browser-extension builds.
- Preserve extension CSP and local CanvasKit and Firebase resources.
- Preserve platform-channel names and payloads unless all implementations and tests change together.
- Avoid real credentials, student records, session material, and production screenshots in fixtures.
- Keep new filenames meaningful, snake_case where applicable, and no more than two words unless a tool requires a fixed filename.
- Do not modify generated output or bump release versions in contributor changes.

For unfamiliar packages, use the Dart MCP package tools before relying on memory. For runtime UI issues, use Dart MCP diagnostics and widget inspection when an app is connected.

## Validate

Always run:

```bash
dart format --output=none --set-exit-if-changed lib web test
flutter analyze
flutter test
```

Then run the narrowest affected build:

- Android or Gradle: APK and AAB.
- iOS or shared Apple configuration: unsigned iOS build; signed IPA only when credentials are available and requested.
- macOS or shared Apple configuration: macOS release build.
- Web application: web release build.
- Extension, web conditional code, CanvasKit, Firebase web, or manifest: `./tool/build_extension.sh`.
- Cross-platform dependency, storage, authentication, or shared bootstrap: complete supported build matrix.

Use Linux and Windows hosts for analysis, tests, Android, and web work. Use a POSIX environment for repository shell scripts. Use macOS with Xcode for iOS and macOS builds.

## Review

Check for:

- Behavior regressions and missing tests
- Security, privacy, token, and logging leaks
- GPL-incompatible dependencies or removed notices
- Trademark or endorsement confusion
- Duplicate services, screens, models, and navigation
- Silent catches and hidden persistence failures
- Broken offline, cache invalidation, refresh, and logout behavior
- Platform divergence and extension CSP regressions
- Unnecessary generated files, credentials, or build artifacts

Report findings by severity with file and line evidence. State completed and skipped validation precisely.
