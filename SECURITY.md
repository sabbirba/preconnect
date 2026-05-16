# Security Policy

PreConnect handles student-facing data, login sessions, cached schedule data, and local device state. Security issues are treated seriously because they can affect privacy, account access, or app integrity.

## Supported Versions

Only the latest release on the `main` branch is supported with security updates.

If you are testing an older release or an unpublished branch, please upgrade before filing a security report unless the issue also affects the current release line.

## Reporting a Vulnerability

Please do not open public issues for security reports.

Use GitHub Security Advisories for private disclosure.

When possible, include:

- A short description of the issue
- The affected platform or build target
- Reproduction steps
- Whether the issue affects login, stored tokens, cached data, network requests, or release assets
- Any screenshots or logs that help explain the problem without exposing secrets

## What To Avoid Sharing Publicly

Until a fix is available, please do not post:

- Access tokens, refresh tokens, cookies, session URLs, or QR codes tied to a live session
- Private student data, IDs, or seat-status exports
- Proof-of-concept details that would make abuse easy to automate

## Response Expectations

We aim to acknowledge valid private reports promptly and work toward a fix or mitigation before public disclosure.

The exact timeline depends on severity and complexity, but the goal is to keep reporters informed and minimize risk to users.

## Scope

Security concerns in scope include:

- Authentication and token storage
- Network requests to PreConnect services and cached upstream data
- Seat-status, notification, and schedule data handling
- Permission handling on mobile platforms
- Release artifacts and update flows
- Any code that could expose private app state or user data

## Hardening Notes

The app is designed to keep sensitive tokens in local app storage or extension storage rather than plain shared preferences. If you notice a path that weakens that guarantee, please report it privately.
