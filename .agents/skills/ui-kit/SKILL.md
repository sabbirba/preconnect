---
name: ui-kit
description: Build or change PreConnect screens with the app's own widgets and design. Use for dialogs, bottom sheets, buttons, inputs, and list layouts.
---

# UI Kit

- Use the shared widgets in `lib/pages/ui_kit.dart` and `lib/pages/shared_widgets`: `AppPageScaffold`, `AppPalette`, `AppActionButton`, `AppRefreshList`, `appInputDecoration`, and `showAppBottomSheet`.
- Do not use stock Material dialogs or one-off styles when an app widget exists.
- Reuse existing helpers and constants before adding new ones, and keep new files to at most two snake_case words.
- Surface persistence and load failures through the existing patterns instead of swallowing them silently.
