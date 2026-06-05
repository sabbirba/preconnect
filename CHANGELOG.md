# Changelog

All notable changes to PreConnect are documented here.
Entries are written for students, not developers — plain language, no commit hashes.

## [Unreleased]

## [1.6.6] — 2026-06-06

- Improved app startup speed with smaller background work on launch
- Better stability for course schedules, seats, and dashboard loading
- Cleaner wording and small UI refinements across key screens

## [1.6.6] — 2026-06-01

- Improved captive Wi-Fi detection: now supports modern RFC 8908 JSON portal responses and handles more campus router redirect patterns
- Massive reduced download and install size by over 58% (saving ~14 MB of space) through optimized native library packaging and aggressive R8 code shrinking
- Optimized memory and launch footprint by implemented lazy-loading for the PDF module
- CI and build pipeline improvements (faster releases for you)


## [1.6.5] — 2026-05

- Restored Rate App and Share actions in the Quick Access panel
- Performance improvements to the home dashboard loading speed
- Minor UI polish and bug fixes

## [1.6.0] — 2026-04

- Major release: new Student Overview dashboard with semester and department info
- Added QR code schedule sharing with friends
- Class alarm system: set reminders per course, adjustable minutes before class
- Improved offline caching — seat status and schedules now load without internet
- Dark mode support across all screens

## [1.5.0] — 2026-03

- Seat status checker: real-time BRACU section seat availability during advising
- Exam schedule viewer with room and building details
- CGPA calculator and degree progress tracker
- Campus bus route guide

## [1.0.0] — 2026-01

- Initial release of PreConnect for BRAC University students
- Class schedule viewer, student profile, and campus utilities
