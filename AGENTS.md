# Repository Guidelines

## Project Structure & Module Organization
Source for the macOS menu bar app lives under `LuxaforPresence/`. Key folders: `Model/` (state & value types like `PresenceState`), `Signals/` (mic/camera, calendar, and foreground app detectors), `Transport/` (Luxafor USB/API client), `UI/` (status item and icon glue), and `Resources/` (config template and app assets). Tests reside in `LuxaforPresence/Tests/`, mirroring the modules they exercise. Keep new assets or plist files inside `Resources/` so SwiftPM bundles them via the existing `Package.swift` directives.

## Build, Test, and Development Commands
- `CLANG_MODULE_CACHE_PATH=$PWD/.cache swift build --disable-sandbox` – preferred way to compile inside containers where `$HOME` caches are read-only; still validates the linker flags that embed `Info.plist`.
- `swift build` – standard local build when you have normal write access to the user caches.
- `swift run` – launches the debug build; use during iterative development to see menu bar changes instantly.
- `swift run -c release` – produces an optimized binary for field testing with the real Luxafor hardware.
- `swift test` – executes `LuxaforPresenceTests`, including Luxafor client fakes and `PresenceEngine` scenarios.
- `./scripts/package-dmg.sh` – builds (release by default), creates `LuxaforPresence.app`, and emits `dist/LuxaforPresence.dmg` for distribution; accepts `-c debug|release` and `-n VolumeName`.

## Development SDLC

### Start from current remote main

Every change starts from a clean worktree at the latest remote `main`, never from a stale local branch:

```bash
git status --short --branch
git fetch origin main --prune
git switch main
git merge --ff-only origin/main
git rev-parse HEAD
git rev-parse origin/main
git switch -c feature/<descriptive-name>
```

The two revisions must match before the feature branch is created. Do not develop or commit directly on `main`, discard an existing dirty worktree, or overwrite unrelated user changes. Keep each branch and PR focused on one coherent change. If a merged change needs a follow-up fix, start a new feature branch and PR from the newly updated `origin/main` instead of rewriting shared history.

### Implement and version intentionally

- Translate the request or PRD into observable behavior and identify affected state transitions, signals, transport calls, permissions, configuration, documentation, and packaging before editing.
- Prefer the smallest clean implementation that preserves module boundaries. Add deterministic unit tests for every non-trivial branch or regression and use fakes for audio, Luxafor, calendar, and process behavior.
- Keep `README.md`, the sample config, menu copy, and `DIST.md` synchronized whenever setup, permissions, configuration, or distribution behavior changes.
- Use semantic versions only: patch for a backward-compatible fix, minor for a backward-compatible feature, and major for a breaking change. Keep `CFBundleShortVersionString` and `CFBundleVersion` aligned to the same `MAJOR.MINOR.PATCH` value; do not add informal “build N” suffixes. Documentation- or workflow-only changes do not require an app version bump.
- Never hardcode or commit local tokens, user IDs, signing credentials, personal paths, or captured private data.

### Local verification ladder

Run checks in increasing scope and fix failures on the feature branch:

```bash
git diff --check
CLANG_MODULE_CACHE_PATH=$PWD/.cache swift build --disable-sandbox
CLANG_MODULE_CACHE_PATH=$PWD/.cache swift build -c release --disable-sandbox
CLANG_MODULE_CACHE_PATH=$PWD/.cache swift test --disable-sandbox
./scripts/package-dmg.sh -c release -n LuxaforPresence
codesign --verify --deep --strict --verbose=2 dist/LuxaforPresence.app
hdiutil verify dist/LuxaforPresence.dmg
shasum -a 256 dist/LuxaforPresence.dmg
```

Full-Xcode GitHub CI is the authoritative test environment. Some local Command Line Tools installations cannot import XCTest; if that occurs, record the limitation and still let the `build_and_test` CI job run the full suite. A parser-only check such as `xcrun swiftc -frontend -parse LuxaforPresence/Tests/*.swift` is a useful syntax fallback, but it never replaces `swift test`.

For behavior involving the actual microphone or Luxafor device:

- Exercise the packaged copy launched from `/Applications`, not only `swift run`. macOS TCC may attribute an unpackaged executable's microphone access to its parent terminal, and ad-hoc rebuilds can require microphone approval again because their code identity changes.
- Confirm Luxafor's official app is running with Incoming Local Webhooks enabled and that the configured port/token match. Do not require a Luxafor cloud `userId` for local webhook transport.
- Test automatic signal changes and manual menu overrides. Verify the latest requested state wins, transitions are prompt, cooldown behavior is correct, and returning to Available turns the device off.
- Inspect process, socket, and privacy-safe unified-log evidence when diagnosing timing or signal issues. Do not log raw calendar titles, meeting URLs, tokens, or captured audio.
- Restore any temporary config, manual mode, brightness, process, and device state after testing. Never reset macOS privacy permissions or change unrelated system/app settings without explicit user approval.
- When the user is unavailable, complete all independently automatable checks and leave only the exact physical or visual validation that requires a person; do not stop other SDLC progress.

### Commit, PR, and merge gate

1. Review `git status`, the complete diff, and `git diff --check`; stage only intentional files.
2. Commit with an imperative subject of at most 72 characters, optionally scoped (for example, `presence: detect signal from active microphones`).
3. Push the `feature/...` branch and open a ready PR targeting `main` (use a draft only while required work remains). In Codex sessions, use authenticated `gh-axi` GitHub tooling when available.
4. In the PR, summarize the root cause or motivation, user-visible behavior, permission/configuration impact, tests run, and any artifact or hardware evidence. Add a screenshot when menu-bar UI changes materially.
5. Wait for the `Build & Package / build_and_test` check to pass. Never merge with required checks failed or pending; diagnose and push fixes to the same branch.
6. Merge with a merge commit unless the repository or user directs otherwise, then delete the remote feature branch.
7. Fetch and fast-forward local `main` to the exact merge commit and wait for the post-merge `main` workflow to pass. End with `git status` clean and local `HEAD` equal to `origin/main`.

For a set of related changes, use separate child feature branches/PRs when they are independently reviewable. Merge them in dependency order, rebasing or refreshing each from current `main` as needed, and require a green CI gate after every merge so a regression is attributable and reversible.

### Package, install, and release

Always rebuild distribution output from the exact merged `main` commit; do not reuse a pre-merge DMG. `dist/` is generated output and must remain uncommitted. Quit the prior app before replacing `/Applications/LuxaforPresence.app`, launch that installed copy, and verify the displayed version, bundle metadata, signature, executable checksum, and expected process before field testing. Launch-at-login must be tested from `/Applications` or `~/Applications`, not from a mounted DMG or App Translocation path.

`scripts/package-dmg.sh` creates an ad-hoc-signed development artifact suitable for local testing only. A public release must follow `DIST.md`: Developer ID signing with hardened runtime and the audio-input entitlement, Apple notarization, ticket stapling, and Gatekeeper verification. Do not publish or tag an ad-hoc DMG, and do not trigger the tag release workflow unless all required signing/notarization secrets are present. When those prerequisites are unavailable, land the tested code and documentation, produce a clearly labeled local development artifact if useful, and report the trusted-release blocker explicitly.

### Completion record

The handoff for each change should state the merged PR and commit, local and CI checks, version (if changed), artifact path and SHA-256 (if built), install/running status (if requested), and any remaining human-only hardware check. A change is complete only when the PR is merged, post-merge CI is green, and the worktree is clean and synchronized with `origin/main`; publication is a separate completion gate when a trusted release was requested.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: UpperCamelCase for types (`PresenceEngine`), lowerCamelCase for methods/properties (`updateState()`), and enums for state machines. Prefer 4-space indentation, trailing commas in multiline collections, and mark protocol conformances in dedicated `extension` blocks. When adding files, keep filenames aligned with the primary type (e.g., `FooSignal.swift`). Run Xcode's built-in formatter before committing; extra tooling (SwiftFormat/SwiftLint) is currently out of scope.

## Testing Guidelines
Add a peer test in `LuxaforPresence/Tests/` for every non-trivial feature; organize fixtures by feature (`LuxaforClientTests`, `PresenceEngineTests`). Name tests using the `test_<Scenario>_<Expectation>` pattern so failures read clearly. Mock external systems (calendar, audio) rather than touching real services. Aim to cover new branches introduced in `PresenceEngine` and any heuristics inside `Signals/`.

## Commit & Pull Request Guidelines
History currently uses concise, descriptive summaries (e.g., “1st vibe-coded version - runs, but does not display icons”). Keep future commit subjects imperative, ≤72 characters, and include scope when useful (`presence: add idle debounce`). For pull requests, link the motivating issue, describe user-visible changes, call out configuration impacts, and attach screenshots when UI changes affect the menu bar icon. Ensure CI (or at least `swift test`) passes locally before requesting review.

## Configuration & Security Tips
Do not hardcode Luxafor `userId`s; prefer the per-user config at `~/.config/LuxaforPresence/config.plist` and keep sample placeholders in `Resources/config.plist`. Uploaded asset catalogs must be template images (`StatusIconOn/Off/Idle`) so menu bar tinting works. Avoid logging raw calendar titles or meeting URLs; redact sensitive strings before writing to stdout or diagnostics.
