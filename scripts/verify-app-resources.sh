#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: verify-app-resources.sh /path/to/LuxaforPresence.app" >&2
    exit 2
fi

APP_DIR="$1"
RESOURCE_BUNDLE="${APP_DIR}/LuxaforPresence_LuxaforPresence.bundle"

if [[ ! -d "${APP_DIR}" ]]; then
    echo "error: app bundle not found at ${APP_DIR}" >&2
    exit 1
fi

if [[ ! -d "${RESOURCE_BUNDLE}" ]]; then
    echo "error: SwiftPM resource bundle is not beside the app's main bundle URL" >&2
    exit 1
fi

required_resources=(
    "config.plist"
    "Assets.xcassets/StatusIconOn.imageset/circle.circle.fill.png"
    "Assets.xcassets/StatusIconOff.imageset/circle.png"
    "Assets.xcassets/StatusIconIdle.imageset/questionmark.circle.png"
)

for resource in "${required_resources[@]}"; do
    if [[ ! -f "${RESOURCE_BUNDLE}/${resource}" ]]; then
        echo "error: packaged resource is missing: ${resource}" >&2
        exit 1
    fi
done

if command -v plutil >/dev/null 2>&1; then
    /usr/bin/plutil -lint "${RESOURCE_BUNDLE}/config.plist" >/dev/null
fi

echo "Verified packaged SwiftPM resources at ${RESOURCE_BUNDLE}."
