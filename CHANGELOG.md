# Changelog

All notable changes to PreConnect are documented here.
Entries are written for students, not developers — plain language, no commit hashes.

## [Unreleased]

## [2.0.7] — 2026-08-20

- Student-WiFi: Instant one-tap sign-in with active keep-alive heartbeat, multi-AP roaming auto-reconnect, and real-time connection diagnostics.
- Campus Printer: Configured default A4 media sizing across PJL directives and optimized single-pass LPR spooling for exact copy counts.
- Home Screen Widget: Updated to a translucent glassmorphic look that seamlessly blends with your home screen wallpaper.
- Quick Settings Tile: Added a dedicated Android Quick Settings tile for direct one-tap campus Wi-Fi sign-in from your notification shade.

## [2.0.6] — 2026-08-14

- Student-WiFi & Connectivity: Enhanced Captive Wi-Fi login reliability with smart retry loops, automatic portal detection, and dedicated network fields.
- Direct Developer Access: Quick-access developer utilities now open smoothly and directly.

## [2.0.5] — 2026-08-02

- Optimize schedule handling and improve connectivity status management.
- All-Department Payments Sync: Integrated multi-portfolio query flags (`includeInactive=true`) so payment records, dues, and transaction histories across all active and past departments load in full.
- Semester Session Isolation: Fixed switching between past and current semesters to accurately preserve course schedules, exam rooms, seating details, and grade sheets.

## [2.0.4] — 2026-07-29

Universal Compatibility: Expanded hardware feature definitions and optimized responsive layouts for all device form factors.

## [2.0.3] — 2026-07-28

- Instant 0 ms Loading: Pages across the app (Dashboard, Class Schedule, Exam Schedule, DSpace, Calendar, Notifications, Seat Status, Free Labs) now render instantly from local cache without loading spinners.
- 120Hz Smooth Scrolling: Enabled high refresh rate hardware rendering and optimized scroll physics for stutter-free navigation.
- Real-Time Data Sync: Integrated background diff updates via Mercure SSE so your schedules and exam details update silently in the background.
- Semester Session Isolation: Fixed switching between past and current semesters to accurately preserve course data, exam rooms, and seating details.
- App-Wide UI Refresh: Compacted page paddings from 20px to 14px for cleaner, roomier card layouts.
- Campus Wi-Fi & PDF Reliability: Enhanced captive portal login stability, unescaped PDF downloads, and persistent offline exam map caching.

## [2.0.2] — 2026-07-23

- Performance Upgrades: Pipeline compilation optimized with parallel build jobs and dependency caching.

## [2.0.1] — 2026-07-18

- Apple Silicon Support: Built on modern Apple Silicon virtual machine environments for faster deployment.

## [2.0.0] — 2026-07-17

- Smoother Onboarding: Notification requests are now optional and won't interrupt your first startup.
- Reliable Wi-Fi: Improved campus Wi-Fi login reliability with smart retry loops and delays.
- Under the Hood: Cleaned up background notifications and fully optimized app stability.

## [1.6.9] — 2026-07-14

- Instant 0 ms startup loading: Optimized initial frame settling delay to 0 ms.
- Real-time silent UI updates: Connected Class Schedule, Exam Schedule, Bus, Alarms, and Degree Progress to background cache update listeners, refreshing the UI instantly without showing visual loading indicators or spinners.
- Background sync integration: Wired the FCM background handler to silently fetch and update the local database cache when the server broadcasts silent data sync updates.
- In-app routing for captive portal notifications: Push alerts for campus Wi-Fi redirects and external URLs now open directly inside the app's Captive Wi-Fi interface and in-app WebViews.
- Fixed UI layout blank spaces: Resolved vertical spacing bugs and added attendance record empty state placeholder cards in the Student Profile.

## [1.6.8] — 2026-06-27

- Added help instructions and an automated Connect/Disconnect button to Captive Wi-Fi
- Swapped the SSID display to a read-only input field matching the rest of the text fields
- Replaced the webview portal page header with a transparent overlay for back and refresh controls
- Setup real-time updates for push notifications and added Library and Course Leaks(Course Materials)

## [1.6.7] — 2026-06-17

- Completely rewrote the campus Wi-Fi login flow to be API based
- Network properties (gateway, MAC address, etc.) are now fetched dynamically from device APIs
- Captive portal banner redesigned to be minimal on the Home screen
- Fixed MAC address normalization and portal redirect URL parameter extraction

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
