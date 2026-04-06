#!/usr/bin/env bash
#
# Build a universal (arm64 + x86_64) release binary and wrap it in a macOS .app
# bundle. Ad-hoc signs the bundle so Gatekeeper recognizes it as a valid app
# (users will still need to right-click -> Open on first launch because the
# signature isn't from a Developer ID certificate).
#
# Output: .dist/MongoCompass.app

set -euo pipefail

TARGET="MongoCompass"
APP_NAME="${TARGET}.app"
DIST_DIR=".dist"
APP_DIR="${DIST_DIR}/${APP_NAME}"
INFO_PLIST="Resources/Info.plist"

# Optional version override passed by CI (e.g. "0.2.0" from a v0.2.0 tag).
VERSION="${VERSION:-}"

echo "==> Cleaning dist directory"
rm -rf "${DIST_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

echo "==> Building release binary"
swift build -c release

BIN_DIR=$(swift build -c release --show-bin-path)
BIN_PATH="${BIN_DIR}/${TARGET}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "Error: binary not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "==> Copying binary into app bundle"
cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${TARGET}"
chmod +x "${APP_DIR}/Contents/MacOS/${TARGET}"

echo "==> Binary architecture:"
file "${APP_DIR}/Contents/MacOS/${TARGET}"

echo "==> Writing Info.plist"
cp "${INFO_PLIST}" "${APP_DIR}/Contents/Info.plist"
if [[ -n "${VERSION}" ]]; then
    echo "    Stamping version = ${VERSION}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${APP_DIR}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_DIR}/Contents/Info.plist"
fi

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "${APP_DIR}"

echo "==> Verifying signature"
codesign --verify --verbose "${APP_DIR}"

echo ""
echo "Built: ${APP_DIR}"
