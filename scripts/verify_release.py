#!/usr/bin/env python3
"""Verify release checksums and the applications inside ZIP and read-only DMG."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, args))}\n{result.stderr}{result.stdout}")
    return result.stdout


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha256(path):
    with path.open("rb") as handle:
        digest = hashlib.sha256()
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
        return digest.hexdigest()


def verify_app(app, manifest):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info["CFBundleIdentifier"] == "com.local.dropshelf", "Bundle identifier mismatch")
    require(info["CFBundleShortVersionString"] == manifest["version"], "App version mismatch")
    require(info["CFBundleVersion"] == manifest["build"], "App build number mismatch")
    require(info["LSMinimumSystemVersion"] == "13.0", "Minimum macOS must be 13.0")
    require((app / "Contents/Resources/AppIcon.icns").is_file(), "Missing app icon")
    executable = app / "Contents/MacOS/DropShelf"
    require(os.access(executable, os.X_OK), "App executable is not executable")
    require(sha256(executable) == manifest["executable_sha256"], "Executable does not match manifest")
    require(set(run("lipo", "-archs", str(executable)).split()) == {"arm64", "x86_64"}, "Not Universal 2")
    build_info = run("xcrun", "vtool", "-show-build", str(executable))
    require(re.findall(r"\bminos\s+([\d.]+)", build_info) == ["13.0", "13.0"], "Mach-O deployment targets differ")
    run("codesign", "--verify", "--deep", "--strict", str(app))
    return {str(path.relative_to(app)): sha256(path)
            for path in app.rglob("*") if path.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    require(re.fullmatch(r"\d+\.\d+\.\d+", args.version), "Invalid version")
    directory = args.directory.resolve()
    names = {f"DropShelf-v{args.version}-macOS-Universal.{ext}" for ext in ("zip", "dmg")}
    expected = names | {"release-manifest.json"}
    checksums = {}
    for line in (directory / "SHA256SUMS.txt").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([^/]+)", line)
        require(match is not None, "Invalid checksum entry")
        digest, name = match.groups()
        require(name in expected and name not in checksums, "Unexpected or duplicate checksum file")
        checksums[name] = digest
    require(set(checksums) == expected, "Incomplete checksum list")
    for name, digest in checksums.items():
        require(sha256(directory / name) == digest, f"Checksum mismatch: {name}")
    manifest = json.loads((directory / "release-manifest.json").read_text())
    require(manifest["version"] == args.version, "Manifest version mismatch")
    require(re.fullmatch(r"[0-9a-f]{40}", manifest["source_commit"]), "Invalid source commit")
    require(manifest["minimum_macos"] == "13.0", "Manifest deployment target mismatch")
    require(set(manifest["architectures"]) == {"arm64", "x86_64"}, "Manifest architecture mismatch")
    require(set(manifest["files"]) == names, "Manifest file list mismatch")
    for name, entry in manifest["files"].items():
        require(entry["sha256"] == checksums[name], f"Manifest digest mismatch: {name}")
        require(entry["size"] == (directory / name).stat().st_size, f"Manifest size mismatch: {name}")

    workspace = Path(tempfile.mkdtemp(prefix="DropShelf-release-verify-"))
    mount = workspace / "mount"
    mount.mkdir()
    try:
        unpacked = workspace / "zip"
        run("ditto", "-x", "-k", str(directory / f"DropShelf-v{args.version}-macOS-Universal.zip"), str(unpacked))
        zip_files = verify_app(unpacked / "DropShelf.app", manifest)
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount),
            str(directory / f"DropShelf-v{args.version}-macOS-Universal.dmg"))
        require((mount / "Applications").is_symlink(), "DMG missing Applications link")
        require(os.readlink(mount / "Applications") == "/Applications", "Invalid Applications link")
        require(verify_app(mount / "DropShelf.app", manifest) == zip_files, "ZIP and DMG apps differ")
    finally:
        if os.path.ismount(mount):
            run("diskutil", "eject", str(mount))
        shutil.rmtree(workspace)
    print(f"PASS: v{args.version} checksums, ZIP/DMG contents, signatures, architectures and macOS targets")


if __name__ == "__main__":
    main()
