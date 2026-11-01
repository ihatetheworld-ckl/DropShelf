#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/build"
TASK_DIR="$(mktemp -d "$PROJECT_DIR/build/.volume-test.XXXXXX")"
MOUNT_PATH="$TASK_DIR/volume"
cleanup() {
    if mount | /usr/bin/grep -Fq " on $MOUNT_PATH "; then
        hdiutil detach "$MOUNT_PATH" || return
    fi
    rm -rf "$TASK_DIR"
}
trap cleanup EXIT
mkdir -p "$MOUNT_PATH"
hdiutil create -size 64m -fs APFS -volname DropShelfValidation "$TASK_DIR/test.dmg" >/dev/null
hdiutil attach "$TASK_DIR/test.dmg" -mountpoint "$MOUNT_PATH" -nobrowse >/dev/null
cd "$PROJECT_DIR"
DROPSHELF_TEST_VOLUME="$MOUNT_PATH" swift test "$@"
