# Shipping LuxaforPresence

GitHub Releases must contain only Developer ID-signed, hardened, notarized, stapled, and Gatekeeper-verified DMGs. `scripts/package-dmg.sh` remains an ad-hoc local-development path and must never be published.

## What this solves

Apple's standard **Allow applications from: App Store & Known Developers** policy accepts software distributed outside the Mac App Store when it has an Apple-issued Developer ID signature and an Apple notarization ticket. The release workflow implements that path; notarization is an automated malware and code-signing check, not Mac App Store review.

An employer can apply stricter MDM, endpoint-security, application-allowlist, Privacy Preferences Policy Control, or network rules. In that case, a valid Developer ID and notarization ticket are necessary but may not be sufficient. Give IT the following values and ask whether they must explicitly approve them:

- Bundle identifier: `com.jdegregorio.LuxaforPresence`
- Developer Team ID: the value stored as `NOTARY_TEAM_ID`
- Signing identity: `Developer ID Application: <member or organization name> (<TEAM_ID>)`
- Required privacy access: Microphone; the user must also be allowed to run the official Luxafor app and connect to its loopback webhook

Apple documents the [Gatekeeper checks](https://support.apple.com/guide/security/sec5599b66df/web) and the [Developer ID plus notarization requirement](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## One-time Apple setup

### 1. Enroll

Join the [Apple Developer Program](https://developer.apple.com/programs/enroll/) as an individual or organization. A free Apple developer account cannot issue the required distribution certificate. Apple currently requires the Account Holder to create a Developer ID certificate.

### 2. Create the signing certificate

1. On a trusted Mac, open **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority**.
2. Enter the Apple Account email and a descriptive common name, leave the CA email blank, select **Saved to disk**, and save the `.certSigningRequest`. Apple provides the same steps in [Create a certificate signing request](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request).
3. Open [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list), add a certificate, select **Developer ID → Developer ID Application**, upload the CSR, and download the `.cer`. Do not choose **Mac App Distribution**, **Apple Distribution**, or **Developer ID Installer**. See Apple's [Developer ID certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
4. Double-click the `.cer` to add it to the same keychain that contains the CSR private key.
5. In **Keychain Access → My Certificates**, expand the new `Developer ID Application: ...` entry and confirm a private key appears below it.
6. Export that identity as a password-protected `.p12`. The export must include both the certificate and private key. Keep the `.p12` and its password outside the repository.
7. Confirm the identity is valid:

   ```bash
   security find-identity -v -p codesigning
   ```

### 3. Create notarization credentials

1. Record the 10-character Team ID shown in Apple Developer membership details.
2. Ensure the Apple Account used for notarization belongs to that developer team and has two-factor authentication enabled.
3. At [account.apple.com](https://account.apple.com/), open **Sign-In & Security → App-Specific Passwords** and create one named `LuxaforPresence GitHub Actions`. Apple documents this in [Sign in using app-specific passwords](https://support.apple.com/102654).

Changing the main Apple Account password revokes its app-specific passwords, so `NOTARY_APP_PASSWORD` must be replaced afterward.

## Configure GitHub

Open the repository's [environment settings](https://github.com/jdegregorio/LuxaforPresence/settings/environments). The `release` environment is already created and limited to the `main` branch. Add these **environment secrets**:

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Base64 text for the exported Developer ID `.p12` |
| `BUILD_CERTIFICATE_PASSWORD` | Password chosen while exporting the `.p12` |
| `NOTARY_APPLE_ID` | Apple Account email used for notarization |
| `NOTARY_TEAM_ID` | 10-character Apple Developer Team ID |
| `NOTARY_APP_PASSWORD` | App-specific password created for CI |

On macOS, copy the certificate value without writing another plaintext file:

```bash
base64 -i /secure/path/DeveloperIDApplication.p12 | tr -d '\n' | pbcopy
```

Paste the clipboard into `BUILD_CERTIFICATE_BASE64`. Do not add the `.p12`, its decoded contents, or any password to Git, an Actions variable, workflow output, issue, or pull request. The workflow generates a random temporary keychain password, derives the signing identity from the imported certificate, and deletes the temporary certificate and keychain before publication.

A required reviewer is also recommended; when enabled, an authorized reviewer must approve each new or replacement release before the signing secrets become available. GitHub explains environment-scoped secrets and protection rules in [Managing environments for deployment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).

## Publish or migrate a release

After every successful `main` build, GitHub Actions reads the semantic version from `LuxaforPresence/Info.plist`. If `vMAJOR.MINOR.PATCH` does not contain both `LuxaforPresence.dmg` and its checksum, the protected `release` job builds and publishes them. Missing credentials fail the trusted-release job; the workflow never falls back to an ad-hoc artifact.

Existing releases created before this workflow remain ad-hoc until replaced. To migrate the current release after the five secrets are configured:

1. Open **Actions → Build & Package → Run workflow**.
2. Select the `main` branch.
3. Enable **Replace existing current-version assets with a trusted build**.
4. Run the workflow and approve the `release` environment if it has a reviewer gate.
5. Require `build_and_test`, `release_state`, and `publish_release` to succeed before downloading the replacement DMG.

For a new application release, update `CFBundleShortVersionString` and `CFBundleVersion` to the same `MAJOR.MINOR.PATCH` value and merge normally. A missing current-version release publishes automatically after tests pass.

The workflow:

1. Imports the `.p12` into an ephemeral keychain and confirms it contains exactly one valid Developer ID Application identity.
2. Stores and validates the notary credentials in that keychain.
3. Signs the app with the audio-input entitlement, hardened runtime, and secure timestamp.
4. Notarizes and staples the app.
5. Creates and Developer ID-signs the DMG, then notarizes and staples it.
6. Validates signatures, hardened runtime, Team ID, entitlements, notarization tickets, Gatekeeper assessments, DMG integrity, and version metadata.
7. Generates `LuxaforPresence.dmg.sha256`, deletes temporary credentials, and only then creates or updates the GitHub Release.

The latest artifact URL remains:

```text
https://github.com/jdegregorio/LuxaforPresence/releases/latest/download/LuxaforPresence.dmg
```

## Local trusted release

With the Developer ID identity installed in the active keychain, store the notarization password using an interactive prompt:

```bash
xcrun notarytool store-credentials LuxaforPresenceNotary \
  --apple-id "appleid@example.com" \
  --team-id TEAMID
```

Then build the release:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: YOUR NAME (TEAMID)" \
NOTARY_PROFILE="LuxaforPresenceNotary" \
./scripts/release-dmg.sh -c release -n LuxaforPresence
```

Do not rerun `package-dmg.sh` afterward; it reconstructs the app with an ad-hoc signature.

## Verify before installing

Keep the DMG and checksum in the same directory, then run:

```bash
shasum -a 256 -c LuxaforPresence.dmg.sha256
codesign --verify --verbose=2 LuxaforPresence.dmg
xcrun stapler validate LuxaforPresence.dmg
spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose=2 \
  LuxaforPresence.dmg
```

Copy the app to `/Applications`, eject the DMG, and launch the installed copy. Do not bypass Gatekeeper. If the signed and notarized app is still blocked on the work Mac, capture the `spctl` result and ask IT to approve the Team ID and bundle identifier above; that is an organization policy issue rather than a signing workaround.
