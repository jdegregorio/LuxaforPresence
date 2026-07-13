# Changelog

All notable changes to LuxaforPresence will be documented here.

## Unreleased

- Add the family-office state timeline: quiet Zoom calls are yellow, recent voice flashes red, cooldown is solid red, and ended sessions turn off immediately.
- Harden local, capture-time-gated voice activity with a 250 ms debounce, immediate state reevaluation, privacy-minimal permissions, and sleep-safe lifecycle handling.
- Add complete menu diagnostics and overrides, default-on launch at login, and bounded local-output recovery for Luxafor desktop and device restarts.

## [1.6.0] – 2026-07-12

- Treat microphone use by recording and dictation apps as presence evidence, while voice activity selects red or yellow.
- Keep webhook delivery ordered and convergent with latest-state coalescing and retry recovery.
- Validate runtime configuration, webhook endpoints, numeric settings, and remote user IDs before use.
- Move signal polling off the main thread and bound Accessibility traversal work.
- Recover automatically from transient VAD audio-engine startup failures.
- Add an actionable configuration-file menu item with private file permissions and restart guidance.
- Correct SwiftPM resource packaging and verify that packaged apps can be code signed strictly.
- Require Developer ID signing, hardened runtime, notarization, stapling, and Gatekeeper verification for release DMGs.
- Harden CoreAudio, CoreMediaIO, and Accessibility value bridging against malformed system data.

## [1.5.0] – 2026-02-25

- Version `1.5.0` "Beta", the app actually works for Teams and Slack, needs more testing
- Accessibliy Framework to detect Teams and Slack meetings
- Voice Activity Detection (VAD) support
- 3 states: in a meeting (muted) , in a meeting, Off
- Support Local Luxafor Webhook
- BUGFIX:  Forced ON/OFF state would stick, requiring app restart to clear
- build on MacOS 26

## [v0.01] – First Upstream Tagged Version

- First tagged version in the upstream repository was `v0.01`.
- Initial menu bar app that infers “in meeting” state using mic/camera activity plus a foreground-app allowlist and updates the Luxafor flag accordingly.
- Manual overrides (Force On/Off) exposed via the status menu.
- Packaging script (`scripts/package-dmg.sh`) to build a distributable `.dmg`.
- Roadmap for additional signals, logging, and override UX tracked in `PLAN.md`.
