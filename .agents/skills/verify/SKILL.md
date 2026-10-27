---
name: verify
description: Run the repository's required checks after a code change and report skipped validation. Use after editing Dart, web, native configuration, dependencies, or release scripts.
---

# Verify

Run after every code change:

```bash
dart format --output=none --set-exit-if-changed lib web test
flutter analyze
flutter test
```

- Run the affected platform build after changing native configuration, dependencies, manifests, entitlements, release scripts, or platform channels.
- Run `./tool/build_extension.sh` after changing `web`, conditional web implementations, Firebase web setup, CanvasKit loading, or extension manifests.
- Update tests when authentication, logout, refresh, storage, cache invalidation, FCM, schedules, or platform-channel behavior changes.
- Report every skipped check with the exact reason.
