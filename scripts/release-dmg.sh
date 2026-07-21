#!/usr/bin/env bash

set -euo pipefail

CONFIGURATION=release
DMG_NAME=LuxaforPresence

usage() {
    cat <<'EOF'
Usage: release-dmg.sh [-c debug|release] [-n VolumeName]

Builds, Developer ID-signs, notarizes, staples, and verifies the app and DMG.
Requires DEVELOPER_ID_APPLICATION and NOTARY_PROFILE in the environment.
SIGNING_KEYCHAIN and NOTARY_KEYCHAIN may identify explicit CI keychains.
EOF
    exit 1
}

while getopts ":c:n:h" opt; do
    case "${opt}" in
        c) CONFIGURATION="${OPTARG}" ;;
        n) DMG_NAME="${OPTARG}" ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

if [[ $# -ne 0 ]]; then
    usage
fi

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

for command in codesign ditto hdiutil spctl xcrun; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "${command} command not found; cannot create a trusted release." >&2
        exit 1
    fi
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${REPO_ROOT}/dist/LuxaforPresence.app"
DMG_PATH="${REPO_ROOT}/dist/${DMG_NAME}.dmg"
ENTITLEMENTS_PATH="${REPO_ROOT}/LuxaforPresence/LuxaforPresence.entitlements"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/LuxaforPresence-release.XXXXXX")"
ZIP_PATH="${TEMP_DIR}/LuxaforPresence.zip"
trap 'rm -rf "${TEMP_DIR}"' EXIT

if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
    if [[ ! -f "${SIGNING_KEYCHAIN}" ]]; then
        echo "Signing keychain not found: ${SIGNING_KEYCHAIN}" >&2
        exit 1
    fi
fi

if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
    if [[ ! -f "${NOTARY_KEYCHAIN}" ]]; then
        echo "Notary keychain not found: ${NOTARY_KEYCHAIN}" >&2
        exit 1
    fi
fi

codesign_with_keychain() {
    if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
        codesign --keychain "${SIGNING_KEYCHAIN}" "$@"
    else
        codesign "$@"
    fi
}

submit_for_notarization() {
    local artifact_path="$1"
    if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
        xcrun notarytool submit \
            "${artifact_path}" \
            --keychain-profile "${NOTARY_PROFILE}" \
            --keychain "${NOTARY_KEYCHAIN}" \
            --wait
    else
        xcrun notarytool submit \
            "${artifact_path}" \
            --keychain-profile "${NOTARY_PROFILE}" \
            --wait
    fi
}

"${REPO_ROOT}/scripts/package-dmg.sh" -c "${CONFIGURATION}" -n "${DMG_NAME}"

echo "Signing ${APP_PATH}…"
codesign_with_keychain \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "${ENTITLEMENTS_PATH}" \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
APP_SIGNING_DETAILS="$(codesign --display --verbose=4 "${APP_PATH}" 2>&1)"
if ! grep -q '^Authority=Developer ID Application:' <<<"${APP_SIGNING_DETAILS}"; then
    echo "App was not signed with a Developer ID Application certificate." >&2
    exit 1
fi
if ! grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"${APP_SIGNING_DETAILS}"; then
    echo "App signature does not enable the hardened runtime." >&2
    exit 1
fi

echo "Notarizing ${APP_PATH}…"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"
submit_for_notarization "${ZIP_PATH}"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
spctl --assess --type execute --verbose=2 "${APP_PATH}"

echo "Creating signed DMG at ${DMG_PATH}…"
"${REPO_ROOT}/scripts/create-dmg.sh" "${APP_PATH}" "${DMG_PATH}" "${DMG_NAME}"
codesign_with_keychain \
    --force \
    --timestamp \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"
if ! codesign --display --verbose=4 "${DMG_PATH}" 2>&1 | grep -q '^Authority=Developer ID Application:'; then
    echo "DMG was not signed with a Developer ID Application certificate." >&2
    exit 1
fi
hdiutil verify "${DMG_PATH}"

echo "Notarizing ${DMG_PATH}…"
submit_for_notarization "${DMG_PATH}"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"
hdiutil verify "${DMG_PATH}"
spctl --assess \
    --type open \
    --context context:primary-signature \
    --verbose=2 \
    "${DMG_PATH}"

echo "Trusted release ready at ${DMG_PATH}."
