# Changelog

All notable changes to LuxaforPresence will be documented here.

## Unreleased

- Turn off the previously configured output only when its destination changes, avoiding both a stuck old Luxafor and a stale Off race on ordinary saves.
- Preserve an older custom Recent Signal duration while normalizing saved settings to the current schema.
- Package the settings review fixes as version `1.9.1`.

## [1.9.0] – 2026-07-18

- Add an in-app Settings window for behavior, presence colors, connection, and advanced signal/output controls.
- Make Available, Zoom Quiet, Recent Signal, and Cooldown colors independently configurable.
- Expose both Recent Signal and Cooldown durations with an explanation of the transition timeline and one-click defaults restoration.
- Replace the ambiguous timer reset menu item with **Clear Recent Signal & Cooldown**.
- Remove the obsolete animated-output implementation, timer, tests, and requirements document; normalized configurations no longer retain animation-era keys.
- Normalize saved settings to the supported schema and apply them immediately without restarting.

## [1.8.1] – 2026-07-17

- Detect microphone input activity for any application through Core Audio's per-process input state, with an AVFoundation compatibility fallback.
- Treat sustained non-silent input energy as activity without classifying speech or inspecting audio content, using a lower `0.001` default RMS threshold.
- Show microphone authorization explicitly in menu diagnostics and structured logs.
- Use solid red for recent signal, solid orange for cooldown, and solid yellow for a quiet Zoom session.

## [1.8.0] – 2026-07-14

- Replace distracting recent-voice flashing and the red cooldown with a steady purple light.
- Eliminate delayed light updates by keeping one persistent health-check connection, sending only semantic color changes, and disabling periodic output heartbeats by default.
- Work around the Luxafor desktop listener retaining disconnected sockets by isolating and invalidating each low-frequency output session while avoiding per-phase traffic.
- Reduce purple and yellow output brightness to 70% by default, configurable with `outputBrightness`.
- Display only the semantic app version in the menu and package both bundle version fields as `1.8.0`.

## [1.7.0] – 2026-07-13

- Add the family-office state timeline: quiet Zoom calls are yellow, recent voice flashes red, cooldown is solid red, and ended sessions turn off immediately.
- Harden local, capture-time-gated voice activity with a 250 ms debounce, immediate state reevaluation, privacy-minimal permissions, and sleep-safe lifecycle handling.
- Open microphone capture only while macOS reports external microphone use, and stop capture during quiet, manual-override, and sleep periods.
- Distinguish external microphone ownership, voice sampling, and detected input energy in menu diagnostics.
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
