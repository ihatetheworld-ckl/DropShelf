#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
VERSION="${1:-v$APP_VERSION}"
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || "$VERSION" != "v$APP_VERSION" ]]; then
    echo "Version must match Info.plist: v$APP_VERSION" >&2
    exit 1
fi

cd "$PROJECT_DIR"
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    echo "Commit source changes before packaging a release." >&2
    exit 1
fi
SOURCE_COMMIT="$(git rev-parse HEAD)"
RELEASE_PARENT="${DROPSHELF_RELEASE_DIR:-$PROJECT_DIR/build/releases}"
mkdir -p "$RELEASE_PARENT"
RELEASE_PARENT="$(cd "$RELEASE_PARENT" && pwd)"
RELEASE_DIR="$RELEASE_PARENT/$VERSION"
if [[ -e "$RELEASE_DIR" ]]; then
    echo "Refusing to replace existing release output: $RELEASE_DIR" >&2
    exit 1
fi

# Keep signing, DMG staging and verification outside File Provider directories.
TASK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/DropShelf-release.XXXXXX")"
trap 'rm -rf "$TASK_DIR"' EXIT
DROPSHELF_BUILD_DIR="$TASK_DIR/build" ./scripts/build_app.sh
APP_BUNDLE="$TASK_DIR/build/DropShelf.app"
OUTPUT_DIR="$TASK_DIR/output"
DMG_ROOT="$TASK_DIR/dmg-root"
mkdir -p "$OUTPUT_DIR" "$DMG_ROOT"
ZIP_NAME="DropShelf-${VERSION}-macOS-Universal.zip"
DMG_NAME="DropShelf-${VERSION}-macOS-Universal.dmg"

ditto --norsrc -c -k --keepParent "$APP_BUNDLE" "$OUTPUT_DIR/$ZIP_NAME"
ditto --norsrc "$APP_BUNDLE" "$DMG_ROOT/DropShelf.app"
ln -s /Applications "$DMG_ROOT/Applications"
codesign --verify --deep --strict "$DMG_ROOT/DropShelf.app"
hdiutil create -volname "DropShelf $APP_VERSION" -srcfolder "$DMG_ROOT" \
    -format UDZO "$OUTPUT_DIR/$DMG_NAME"

python3 - "$OUTPUT_DIR" "$APP_BUNDLE" "$SOURCE_COMMIT" <<'PY'
import hashlib
import json
import pathlib
import plistlib
import sys

output, app = map(pathlib.Path, sys.argv[1:3])
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
sha256 = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
manifest = {
    "version": info["CFBundleShortVersionString"],
    "build": info["CFBundleVersion"],
    "source_commit": sys.argv[3],
    "minimum_macos": info["LSMinimumSystemVersion"],
    "architectures": ["arm64", "x86_64"],
    "signing": "ad-hoc; not notarized",
    "executable_sha256": sha256(app / "Contents/MacOS/DropShelf"),
    "files": {path.name: {"sha256": sha256(path), "size": path.stat().st_size}
              for path in sorted(output.iterdir())},
}
(output / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
(output / "SHA256SUMS.txt").write_text("".join(
    f"{sha256(path)}  {path.name}\n" for path in sorted(output.iterdir())
    if path.name != "SHA256SUMS.txt"))
PY

python3 ./scripts/verify_release.py "$OUTPUT_DIR" --version "$APP_VERSION"
# Publishing local output is the last step; the old output is never removed.
mkdir "$RELEASE_DIR"
ditto --norsrc "$OUTPUT_DIR" "$RELEASE_DIR"
(cd "$RELEASE_DIR" && shasum -a 256 -c SHA256SUMS.txt)
echo "Release artifacts verified: $RELEASE_DIR"
