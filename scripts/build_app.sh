#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
APP_NAME="DropShelf"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE_DIR"

echo "==> [1/4] Compiling $APP_NAME (Release)..."
cd "$PROJECT_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

SWIFT_SOURCES=(
    Sources/DropShelf/Models/AppSettings.swift
    Sources/DropShelf/Models/ShelfItem.swift
    Sources/DropShelf/Core/ShakeDetector.swift
    Sources/DropShelf/Core/HotKeyManager.swift
    Sources/DropShelf/Core/ShelfViewModel.swift
    Sources/DropShelf/Core/ShelfManager.swift
    Sources/DropShelf/UI/DragOutContainerView.swift
    Sources/DropShelf/UI/ShelfContentView.swift
    Sources/DropShelf/UI/ShelfPanel.swift
    Sources/DropShelf/UI/SettingsView.swift
    Sources/DropShelf/App/AppDelegate.swift
    Sources/DropShelf/App/main.swift
)

swiftc -O \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -target arm64-apple-macosx13.0 \
    -framework AppKit \
    -framework SwiftUI \
    -framework QuickLookUI \
    -framework QuickLookThumbnailing \
    -framework UniformTypeIdentifiers \
    -framework Carbon \
    -framework Quartz \
    -framework ServiceManagement \
    "${SWIFT_SOURCES[@]}" \
    -o "$BUILD_DIR/${APP_NAME}-arm64"

swiftc -O \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -target x86_64-apple-macosx13.0 \
    -framework AppKit \
    -framework SwiftUI \
    -framework QuickLookUI \
    -framework QuickLookThumbnailing \
    -framework UniformTypeIdentifiers \
    -framework Carbon \
    -framework Quartz \
    -framework ServiceManagement \
    "${SWIFT_SOURCES[@]}" \
    -o "$BUILD_DIR/${APP_NAME}-x86_64"

lipo -create -output "$MACOS_DIR/$APP_NAME" "$BUILD_DIR/${APP_NAME}-arm64" "$BUILD_DIR/${APP_NAME}-x86_64"
rm -f "$BUILD_DIR/${APP_NAME}-arm64" "$BUILD_DIR/${APP_NAME}-x86_64"

echo "==> [2/4] Assembling $APP_NAME.app bundle..."
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "==> [3/4] Generating AppIcon.icns..."
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift -module-cache-path "$MODULE_CACHE_DIR" - "$ICONSET_DIR" << 'EOF'
import AppKit
import Foundation

let iconsetPath = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, filename) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
    let inset = CGFloat(px) * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(px) * 0.22

    let path = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.14, green: 0.52, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.72, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -60)

    // Draw inner shelf tray symbol
    let innerInset = CGFloat(px) * 0.24
    let trayRect = rect.insetBy(dx: innerInset, dy: innerInset)
    let trayRadius = CGFloat(px) * 0.10
    let trayPath = NSBezierPath(roundedRect: trayRect, xRadius: trayRadius, yRadius: trayRadius)
    trayPath.lineWidth = max(2.0, CGFloat(px) * 0.045)
    NSColor.white.withAlphaComponent(0.92).setStroke()
    trayPath.stroke()

    // Draw downward arrow inside tray
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let arrowPath = NSBezierPath()
    let arrowHalfW = CGFloat(px) * 0.11
    let arrowHalfH = CGFloat(px) * 0.11
    arrowPath.move(to: NSPoint(x: center.x, y: center.y + arrowHalfH))
    arrowPath.line(to: NSPoint(x: center.x, y: center.y - arrowHalfH * 0.7))
    arrowPath.move(to: NSPoint(x: center.x - arrowHalfW, y: center.y - arrowHalfH * 0.1))
    arrowPath.line(to: NSPoint(x: center.x, y: center.y - arrowHalfH * 0.85))
    arrowPath.line(to: NSPoint(x: center.x + arrowHalfW, y: center.y - arrowHalfH * 0.1))
    arrowPath.lineWidth = max(2.0, CGFloat(px) * 0.05)
    arrowPath.lineCapStyle = .round
    arrowPath.lineJoinStyle = .round
    NSColor.white.setStroke()
    arrowPath.stroke()

    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        let outURL = URL(fileURLWithPath: iconsetPath).appendingPathComponent(filename)
        try? pngData.write(to: outURL)
    }
}
EOF

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns" || true
rm -rf "$ICONSET_DIR"

echo "==> [4/4] Signing $APP_NAME.app (ad-hoc)..."
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Build complete: $APP_BUNDLE"

