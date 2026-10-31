import AppKit
import Quartz
import SwiftUI

public final class ShelfPanel: NSPanel, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public let viewModel: ShelfViewModel
    public var onCloseShelf: ((UUID) -> Void)?

    public static let expandedSize = NSSize(width: 254, height: 238)
    public static let collapsedSize = NSSize(width: 176, height: 50)

    public init(viewModel: ShelfViewModel, initialCenter: CGPoint) {
        self.viewModel = viewModel
        let size = Self.expandedSize
        let origin = Self.clampedOrigin(forCenter: initialCenter, size: size)
        let contentRect = NSRect(origin: origin, size: size)

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true

        let dropContainer = ShelfDropDestinationView(frame: NSRect(origin: .zero, size: size))
        dropContainer.autoresizingMask = [.width, .height]
        dropContainer.viewModel = viewModel

        let hostingView = NSHostingView(rootView: ShelfContentView(viewModel: viewModel))
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        hostingView.frame = dropContainer.bounds
        hostingView.autoresizingMask = [.width, .height]
        dropContainer.addSubview(hostingView)

        self.contentView = dropContainer

        setupViewModelBindings()
    }

    private func setupViewModelBindings() {
        viewModel.onRequestClose = { [weak self] in
            guard let self = self else { return }
            self.closeShelfAnimated()
        }

        viewModel.onRequestResize = { [weak self] isCollapsed in
            guard let self = self else { return }
            self.resizePanel(collapsed: isCollapsed)
        }

        viewModel.onRequestQuickLook = { [weak self] in
            self?.toggleQuickLookPreview()
        }
    }

    public override var canBecomeKey: Bool {
        return true
    }

    public override var canBecomeMain: Bool {
        return false
    }

    public override func keyDown(with event: NSEvent) {
        // Space key (49) -> QuickLook
        if event.keyCode == 49 {
            toggleQuickLookPreview()
            return
        }
        // Escape key (53) -> Close if empty or deselect
        if event.keyCode == 53 {
            if !viewModel.selectedItemIDs.isEmpty {
                viewModel.selectedItemIDs.removeAll()
            } else if viewModel.items.isEmpty {
                closeShelfAnimated()
            }
            return
        }
        // Delete / Backspace (51) -> Remove selected items
        if event.keyCode == 51 {
            if !viewModel.selectedItemIDs.isEmpty {
                viewModel.removeItems(withIDs: viewModel.selectedItemIDs)
            }
            return
        }
        // Command + C (8), Command + V (9), Command + A (0)
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                viewModel.copyItemsToClipboard()
                return
            case "v":
                _ = viewModel.addFromPasteboard(.general)
                return
            case "a":
                viewModel.selectAll()
                return
            case "w":
                closeShelfAnimated()
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    public func presentShelfAnimated() {
        self.alphaValue = 0.0
        self.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }

    public func closeShelfAnimated() {
        viewModel.cancelEmptyShelfTimeout()
        let itemsToCleanup = viewModel.items
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            for item in itemsToCleanup {
                item.cleanupIfNeeded()
            }
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.orderOut(nil)
            self.onCloseShelf?(self.viewModel.id)
        })
    }

    private func resizePanel(collapsed: Bool) {
        let targetSize = collapsed ? Self.collapsedSize : Self.expandedSize
        let currentFrame = self.frame
        let newOrigin = NSPoint(
            x: currentFrame.midX - targetSize.width / 2,
            y: currentFrame.maxY - targetSize.height
        )
        let clamped = Self.clampedOrigin(
            forCenter: NSPoint(x: newOrigin.x + targetSize.width / 2, y: newOrigin.y + targetSize.height / 2),
            size: targetSize
        )
        let targetFrame = NSRect(origin: clamped, size: targetSize)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(targetFrame, display: true)
        }
    }

    // MARK: - QuickLook Support
    public func toggleQuickLookPreview() {
        guard !viewModel.items.isEmpty else { return }
        self.makeKeyAndOrderFront(nil)
        if let panel = QLPreviewPanel.shared() {
            if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
                panel.orderOut(nil)
            } else {
                panel.dataSource = self
                panel.delegate = self
                panel.reloadData()
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    public override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }

    public override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    public override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return viewModel.effectiveDragItems.count
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let items = viewModel.effectiveDragItems
        guard index >= 0 && index < items.count else { return nil }
        return items[index].fileURL as NSURL
    }

    // MARK: - Helpers
    private static func clampedOrigin(forCenter center: CGPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = center.x - size.width / 2
        var y = center.y - size.height / 2

        let margin: CGFloat = 12
        x = max(visibleFrame.minX + margin, min(x, visibleFrame.maxX - size.width - margin))
        y = max(visibleFrame.minY + margin, min(y, visibleFrame.maxY - size.height - margin))

        return NSPoint(x: x, y: y)
    }
}
