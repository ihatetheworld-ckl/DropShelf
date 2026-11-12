#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/DropShelf-HapticLab.XXXXXX")"
PROBE_READY=false
trap 'if [[ "$PROBE_READY" != true ]]; then rm -rf "$PROBE_DIR"; fi' EXIT
APP="$PROBE_DIR/DropShelf Haptic Lab.app"
mkdir -p "$APP/Contents/MacOS" "$PROBE_DIR/ModuleCache"
swiftc -O -target "$(uname -m)-apple-macosx13.0" -framework AppKit \
    -module-cache-path "$PROBE_DIR/ModuleCache" \
    "$PROJECT_DIR/scripts/haptic_feedback_probe.swift" -o "$APP/Contents/MacOS/HapticLab"
python3 - "$APP" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
info = {
    'CFBundleIdentifier': 'com.local.dropshelf.haptic-lab',
    'CFBundleName': 'DropShelf Haptic Lab',
    'CFBundleExecutable': 'HapticLab',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.1',
    'CFBundleVersion': '1',
    'LSMinimumSystemVersion': '13.0',
    'NSHighResolutionCapable': True,
}
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
PROBE_READY=true
echo "Probe app: $APP"
echo "Request log: $PROBE_DIR/haptic-probe-requests.jsonl"
open -n "$APP"
