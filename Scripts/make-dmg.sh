#!/usr/bin/env bash
#
# Package the built .app as a drag-to-Applications DMG using the built-in
# `hdiutil` (no external dependencies required).
#
# Output: .dist/MongoCompass.dmg

set -euo pipefail

TARGET="MongoCompass"
APP_NAME="${TARGET}.app"
DIST_DIR=".dist"
APP_PATH="${DIST_DIR}/${APP_NAME}"
DMG_PATH="${DIST_DIR}/${TARGET}.dmg"
STAGING="${DIST_DIR}/dmg-staging"
VOL_NAME="Compass+"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "Error: ${APP_PATH} does not exist. Run Scripts/build-app.sh first." >&2
    exit 1
fi

echo "==> Preparing staging directory"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
cp -R "${APP_PATH}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

echo "==> Creating DMG: ${DMG_PATH}"
rm -f "${DMG_PATH}"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

echo "==> Cleaning up staging"
rm -rf "${STAGING}"

echo ""
echo "Packaged: ${DMG_PATH}"
ls -lh "${DMG_PATH}"
