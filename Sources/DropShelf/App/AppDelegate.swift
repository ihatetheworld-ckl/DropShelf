import AppKit
import SwiftUI

private final class StatusBarDropOverlayView: NSView {
    var onDropPasteboard: ((NSPasteboard) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .png,
            .tiff,
            .string,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Allow normal status item button clicks to pass through while still receiving drag-and-drop
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return onDropPasteboard?(sender.draggingPasteboard) ?? false
    }
}

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let shakeDetector = ShakeDetector()
    private var settingsWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupShakeDetector()
        setupHotKeys()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        shakeDetector.stopMonitoring()
        HotKeyManager.shared.unregisterAll()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "tray.2.fill", accessibilityDescription: "DropShelf")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "DropShelf — 零延迟悬浮文件架（拖拽文件到此图标也可直接新建架子）"

            let overlay = StatusBarDropOverlayView(frame: button.bounds)
            overlay.autoresizingMask = [.width, .height]
            overlay.onDropPasteboard = { [weak self] pasteboard in
                let items = PasteboardExtractor.extractItems(from: pasteboard)
                guard !items.isEmpty else { return false }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let location = self.statusItemScreenAnchor()
                    _ = ShelfManager.shared.summonShelf(at: location, initialItems: items)
                }
                return true
            }
            button.addSubview(overlay)
        }

        let menu = NSMenu()

        let newShelfItem = NSMenuItem(
            title: "新建空白文件架",
            action: #selector(createNewEmptyShelf),
            keyEquivalent: "D"
        )
        newShelfItem.keyEquivalentModifierMask = [.command, .shift]
        newShelfItem.target = self
        menu.addItem(newShelfItem)

        let pasteboardShelfItem = NSMenuItem(
            title: "从剪贴板新建文件架",
            action: #selector(createShelfFromClipboard),
            keyEquivalent: "v"
        )
        pasteboardShelfItem.keyEquivalentModifierMask = [.command, .option]
        pasteboardShelfItem.target = self
        menu.addItem(pasteboardShelfItem)

        let toggleAllItem = NSMenuItem(
            title: "收起 / 展开所有文件架",
            action: #selector(toggleAllShelves),
            keyEquivalent: " "
        )
        toggleAllItem.keyEquivalentModifierMask = [.option, .shift]
        toggleAllItem.target = self
        menu.addItem(toggleAllItem)

        let closeAllItem = NSMenuItem(
            title: "关闭所有文件架",
            action: #selector(closeAllShelves),
            keyEquivalent: ""
        )
        closeAllItem.target = self
        menu.addItem(closeAllItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "偏好设置...",
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 DropShelf",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupShakeDetector() {
        shakeDetector.isInternalDragActive = {
            DragSourceMonitor.shared.isDraggingFromShelf
        }
        shakeDetector.onSummonRequested = { cursorLocation in
            _ = ShelfManager.shared.summonShelf(at: cursorLocation)
        }
        shakeDetector.startMonitoring()
    }

    private func setupHotKeys() {
        HotKeyManager.shared.onSummonShelfShortcut = {
            _ = ShelfManager.shared.summonShelf(at: NSEvent.mouseLocation)
        }
        HotKeyManager.shared.onToggleAllShelvesShortcut = {
            ShelfManager.shared.toggleAllCollapsed()
        }
        HotKeyManager.shared.registerDefaultShortcuts()
    }

    private func statusItemScreenAnchor() -> CGPoint {
        if let window = statusItem.button?.window {
            let frame = window.frame
            return CGPoint(x: frame.midX, y: frame.minY - 130)
        }
        return NSEvent.mouseLocation
    }

    @objc private func createNewEmptyShelf() {
        let anchor = statusItemScreenAnchor()
        _ = ShelfManager.shared.summonShelf(at: anchor)
    }

    @objc private func createShelfFromClipboard() {
        let items = PasteboardExtractor.extractItems(from: .general)
        let anchor = statusItemScreenAnchor()
        _ = ShelfManager.shared.summonShelf(at: anchor, initialItems: items)
    }

    @objc private func toggleAllShelves() {
        ShelfManager.shared.toggleAllCollapsed()
    }

    @objc private func closeAllShelves() {
        ShelfManager.shared.closeAllShelves()
    }

    @objc public func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "DropShelf 偏好设置"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        ShelfManager.shared.closeAllShelves()
        NSApp.terminate(nil)
    }
}
