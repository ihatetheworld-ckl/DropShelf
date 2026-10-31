#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="DropShelf"
VERSION="${1:-v1.0.0}"

cd "$PROJECT_DIR"
./scripts/build_app.sh

echo "==> Packaging macOS Release artifacts ($VERSION)..."
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}-macOS-Universal.zip"
DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}-macOS-Universal.dmg"
DMG_STAGING="$BUILD_DIR/dmg_staging"

rm -f "$ZIP_PATH" "$DMG_PATH"
rm -rf "$DMG_STAGING"

# 1. Create standard macOS .zip archive preserving permissions and bundle structure
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
echo "  -> Created ZIP: $ZIP_PATH"

# 2. Create standard macOS .dmg installer with /Applications symlink
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"
echo "  -> Created DMG: $DMG_PATH"
