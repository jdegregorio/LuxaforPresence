# Shipping LuxaforPresence

## Current personal releases

LuxaforPresence currently publishes ad-hoc-signed, non-notarized DMGs for personal use. After every successful `main` build, GitHub Actions reads the semantic version from `LuxaforPresence/Info.plist` and checks for a matching `vMAJOR.MINOR.PATCH` GitHub Release. If that release does not already contain `LuxaforPresence.dmg`, the workflow:

1. Builds the exact `main` revision in release mode.
2. Creates an ad-hoc-signed app with the audio-input entitlement.
3. Packages and verifies `LuxaforPresence.dmg`.
4. Generates `LuxaforPresence.dmg.sha256`.
5. Creates the version tag and GitHub Release, or repairs a release whose assets are missing.

The latest published DMG is always available at:

```text
https://github.com/jdegregorio/LuxaforPresence/releases/latest/download/LuxaforPresence.dmg
```

To publish a new application version, update both `CFBundleShortVersionString` and `CFBundleVersion` to the same `MAJOR.MINOR.PATCH` value. Merging that change to `main` authorizes publication after the normal build and test job succeeds. Documentation- and workflow-only changes do not require a version bump; if the current version already has a complete release, the publication job exits without rebuilding it.

For recovery or to republish a missing current-version asset, run the **Build & Package** workflow on `main` with **Publish the current main version if its DMG is missing** enabled.

## Ad-hoc distribution limitations

These GitHub Releases are not Developer ID-signed or notarized by Apple. Treat them like local development builds:

- macOS may block the first launch. For a DMG built from this repository that you trust, Control-click the app and choose **Open**, or use **System Settings → Privacy & Security → Open Anyway** after the blocked launch.
- Gatekeeper cannot verify an identified developer or an Apple notarization ticket.
- A rebuilt app has a different ad-hoc code identity, so macOS may request Microphone permission again after an upgrade.
- Automatic launch-at-login registration may be unavailable. Add `/Applications/LuxaforPresence.app` manually under **System Settings → General → Login Items** when necessary.
- The release is suitable for the repository owner's personal use, not frictionless public distribution. Do not instruct other users to bypass Gatekeeper for artifacts they do not independently trust.

The DMG includes an Applications shortcut. Copy the app to `/Applications` or `~/Applications` before testing launch at login; do not test it from the mounted image or an App Translocation path.

## Future trusted distribution

If LuxaforPresence is distributed more broadly, replace the ad-hoc publication step with the existing `scripts/release-dmg.sh` trusted-release path. An official release requires all of the following:

1. Active Apple Developer Program membership.
2. A `Developer ID Application` certificate and private key exported as a password-protected `.p12`.
3. Apple notarization credentials, currently an Apple ID, team ID, and app-specific password usable by `notarytool`.
4. GitHub Actions secrets stored in a release environment:
   - `BUILD_CERTIFICATE_BASE64`
   - `BUILD_CERTIFICATE_PASSWORD`
   - `KEYCHAIN_PASSWORD`
   - `DEVELOPER_ID_APPLICATION`
   - `NOTARY_APPLE_ID`
   - `NOTARY_TEAM_ID`
   - `NOTARY_APP_PASSWORD`
5. A workflow that imports the certificate into a temporary keychain, creates the `notarytool` profile, and calls:

   ```bash
   DEVELOPER_ID_APPLICATION="Developer ID Application: YOUR NAME (TEAMID)" \
   NOTARY_PROFILE="LuxaforPresence-CI" \
   ./scripts/release-dmg.sh -c release -n LuxaforPresence
   ```

6. Successful verification of the app and DMG with `codesign`, `stapler`, and `spctl` before the GitHub Release is published.

That script signs with hardened runtime and the microphone entitlement, notarizes and staples both the app and DMG, and performs the Gatekeeper assessments. When trusted distribution is enabled, update this document, the README warning, the workflow release notes, and `AGENTS.md` together; never silently present an ad-hoc artifact as an identified-developer release.
