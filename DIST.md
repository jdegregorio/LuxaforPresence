# Shipping LuxaforPresence

Release artifacts must be Developer ID-signed, hardened, notarized, stapled, and verified. Do not publish the unsigned output from `package-dmg.sh`.

## Local trusted release

Prerequisites:

- Full Xcode with `codesign`, `notarytool`, and `stapler`.
- A `Developer ID Application` certificate in the active keychain.
- A notarytool profile created once with:

```bash
xcrun notarytool store-credentials LuxaforPresenceNotary \
  --apple-id "appleid@example.com" \
  --team-id TEAMID \
  --password "app-specific-password"
```

Create the release with:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: YOUR NAME (TEAMID)" \
NOTARY_PROFILE="LuxaforPresenceNotary" \
./scripts/release-dmg.sh -c release -n LuxaforPresence
```

The script performs the steps in the required order:

1. Build and assemble the app once.
2. Sign the app with hardened runtime and the required media entitlements.
3. Verify and notarize the app, then staple its ticket.
4. Create and sign the DMG from the stapled app.
5. Notarize and staple the DMG.
6. Validate both artifacts with `codesign`, `stapler`, and `spctl`.

Do not rerun `package-dmg.sh` after signing; it reconstructs the app and intentionally produces an unsigned development artifact.

## GitHub Actions secrets

Tag builds run tests first and then require these repository secrets:

- `BUILD_CERTIFICATE_BASE64`: base64-encoded Developer ID `.p12`.
- `BUILD_CERTIFICATE_PASSWORD`: password protecting the `.p12`.
- `KEYCHAIN_PASSWORD`: strong temporary CI keychain password.
- `DEVELOPER_ID_APPLICATION`: full certificate identity, including team ID.
- `NOTARY_APPLE_ID`: Apple ID used for notarization.
- `NOTARY_TEAM_ID`: Apple Developer team ID.
- `NOTARY_APP_PASSWORD`: app-specific password for notarization.

If any signing or notarization input is absent, the release job fails instead of uploading an untrusted artifact.
