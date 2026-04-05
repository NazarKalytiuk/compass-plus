#!/usr/bin/env bash
#
# Package the built .app as a zip archive using `ditto` (preserves resource
# forks, extended attributes, and the ad-hoc signature).
#
# Output: .dist/MongoCompass.zip

set -euo pipefail

TARGET="MongoCompass"
APP_NAME="${TARGET}.app"
DIST_DIR=".dist"
APP_PATH="${DIST_DIR}/${APP_NAME}"
ZIP_PATH="${DIST_DIR}/${TARGET}.zip"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "Error: ${APP_PATH} does not exist. Run Scripts/build-app.sh first." >&2
    exit 1
fi

echo "==> Creating zip: ${ZIP_PATH}"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo ""
echo "Packaged: ${ZIP_PATH}"
ls -lh "${ZIP_PATH}"
