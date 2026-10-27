---
name: printer
description: Work on the Wi-Fi printer, on-device N-in-1, booklet, fit, page range, and preview layout. Use for printing bugs, PJL options, PDF or image handling, and print tests.
---

# Printer

- Layout math lives in `lib/tools/print_layout.dart`; composing, scanning, and preview pages live in `lib/tools/print_compose.dart`; the page is `lib/pages/wifi_printer.dart`.
- Output is always A4 portrait. Copies and collate stay with the printer and are not part of the app layout.
- Blank-page skipping is always on. The printer's own NUP and ZOOM are turned off when the layout is baked (`pjlPrefix(layoutBaked: true)`), and 2-in-1 and booklet use SHORTEDGE binding.
- Pass-through applies when the job is 1-in-1, every page is portrait, and there is no range or blank drop.
- Cover layout changes in `test/print_test.dart` and `test/wifi_test.dart`, and test with mixed-orientation PDFs, image files, and page ranges.
