#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: create-dmg.sh APP_DIR DMG_PATH VOLUME_NAME" >&2
    exit 1
fi

APP_DIR=$1
DMG_PATH=$2
VOLUME_NAME=$3

if [[ ! -d "${APP_DIR}" ]]; then
    echo "App bundle not found at ${APP_DIR}" >&2
    exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
    echo "hdiutil command not found; cannot create dmg." >&2
    exit 1
fi

DIST_DIR="$(dirname "${DMG_PATH}")"
DMG_STAGING="${DIST_DIR}/dmg-src"

rm -rf "${DMG_STAGING}" "${DMG_PATH}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_DIR}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

rm -rf "${DMG_STAGING}"
