import AppKit
import SwiftUI

public final class DragSourceMonitor {
    public static let shared = DragSourceMonitor()
    public var activeDragCount: Int = 0
    public var isDraggingFromShelf: Bool { activeDragCount > 0 }
    private init() {}
}

/// An AppKit NSView that accepts incoming file/image/URL/text drops for the entire shelf
public final class ShelfDropDestinationView: NSView {
    public weak var viewModel: ShelfViewModel?

    public override var mouseDownCanMoveWindow: Bool {
        return true
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupDropTypes()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDropTypes()
    }

    private func setupDropTypes() {
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .png,
            .tiff,
            .string,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ])
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if DragSourceMonitor.shared.isDraggingFromShelf && (sender.draggingSource as? NSView)?.window == self.window {
            return []
        }
        guard let vm = viewModel, !vm.isClosed else { return [] }
        vm.isDropTargeted = true
        vm.cancelEmptyShelfTimeout()
        return .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if (sender.draggingSource as? NSView)?.window == window { return [] }
        return viewModel?.isClosed == false ? .copy : []
    }

    public override func draggingExited(_ sender: NSDraggingInfo?) { resetDropState() }
    public override func concludeDragOperation(_ sender: NSDraggingInfo?) { resetDropState() }
    private func resetDropState() {
        viewModel?.isDropTargeted = false
        viewModel?.scheduleEmptyShelfTimeout()
    }
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let vm = viewModel, !vm.isClosed,
              (sender.draggingSource as? NSView)?.window != window else { return false }
        vm.isDropTargeted = false
        let accepted = vm.addFromPasteboard(sender.draggingPasteboard)
        if accepted && vm.isCollapsed { vm.toggleCollapsed() }
        if !accepted { vm.scheduleEmptyShelfTimeout() }
        return accepted
    }
}

/// An AppKit NSView that initiates multi-file NSDraggingSession when dragged, while forwarding clicks and double-clicks
public final class MultiFileDragSourceNSView: NSView, NSDraggingSource {
    public var itemsProvider: (() -> [ShelfItem])?
    public var onSingleClick: ((NSEvent) -> Void)?
    public var onDoubleClick: (() -> Void)?
    public var onRightClickMenu: (() -> NSMenu?)?
    public var onDragCompleted: ((Set<UUID>, NSDragOperation) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var draggedItems: [ShelfItem] = []
    private var draggedItemIDs: Set<UUID> = []

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        self.mouseDownEvent = event
    }

    public override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard mouseDownEvent != nil else { return }

        if event.clickCount == 2 {
            onDoubleClick?()
        } else if event.clickCount == 1 {
            onSingleClick?(event)
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let menu = onRightClickMenu?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let startEvent = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - startEvent.locationInWindow.x
        let dy = event.locationInWindow.y - startEvent.locationInWindow.y
        let distance = hypot(dx, dy)
        guard distance >= 4.0 else { return }

        self.mouseDownEvent = nil
        guard let items = itemsProvider?(), !items.isEmpty else { return }

        guard items.allSatisfy({ $0.preserveForExternalUse() }) else { NSSound.beep(); return }
        draggedItems = items
        draggedItemIDs = Set(items.map { $0.id })

        var draggingItems: [NSDraggingItem] = []
        for (idx, shelfItem) in items.enumerated() {
            let dragItem = NSDraggingItem(pasteboardWriter: shelfItem.fileURL as NSURL)
            let iconSize = NSSize(width: 68, height: 68)
            let offset = CGFloat(min(idx, 4)) * 4.0
            let dragFrame = NSRect(
                x: bounds.midX - iconSize.width / 2 + offset,
                y: bounds.midY - iconSize.height / 2 - offset,
                width: iconSize.width,
                height: iconSize.height
            )

            let dragImage = Self.renderedDragImage(for: shelfItem.thumbnail, size: iconSize, totalCount: idx == 0 ? items.count : 1)
            dragItem.setDraggingFrame(dragFrame, contents: dragImage)
            draggingItems.append(dragItem)
        }

        DragSourceMonitor.shared.activeDragCount += 1
        let session = beginDraggingSession(with: draggingItems, event: startEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return [.copy, .link, .generic]
        case .withinApplication:
            return [.copy]
        @unknown default:
            return [.copy]
        }
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DragSourceMonitor.shared.activeDragCount = max(0, DragSourceMonitor.shared.activeDragCount - 1)
        let ids = draggedItemIDs
        draggedItemIDs.removeAll()
        defer { draggedItems.removeAll() }
        if operation != [] {
            onDragCompleted?(ids, operation)
        }
    }

    private static func renderedDragImage(for image: NSImage, size: NSSize, totalCount: Int) -> NSImage {
        let output = NSImage(size: size)
        output.lockFocus()

        let iconRect = NSRect(x: 4, y: 4, width: size.width - 8, height: size.height - 8)
        image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.95)

        if totalCount > 1 {
            let badgeText = "\(totalCount)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.white
            ]
            let textSize = badgeText.size(withAttributes: attrs)
            let badgeWidth = max(20, textSize.width + 10)
            let badgeHeight: CGFloat = 20
            let badgeRect = NSRect(
                x: size.width - badgeWidth - 2,
                y: size.height - badgeHeight - 2,
                width: badgeWidth,
                height: badgeHeight
            )

            let path = NSBezierPath(roundedRect: badgeRect, xRadius: 10, yRadius: 10)
            NSColor.systemBlue.setFill()
            path.fill()

            let textPoint = NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            )
            badgeText.draw(at: textPoint, withAttributes: attrs)
        }

        output.unlockFocus()
        return output
    }
}

public struct DragSourceOverlay: NSViewRepresentable {
    public let itemsProvider: () -> [ShelfItem]
    public var onSingleClick: ((NSEvent) -> Void)? = nil
    public var onDoubleClick: (() -> Void)? = nil
    public var onRightClickMenu: (() -> NSMenu?)? = nil
    public var onDragCompleted: ((Set<UUID>, NSDragOperation) -> Void)? = nil

    public init(
        itemsProvider: @escaping () -> [ShelfItem],
        onSingleClick: ((NSEvent) -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onRightClickMenu: (() -> NSMenu?)? = nil,
        onDragCompleted: ((Set<UUID>, NSDragOperation) -> Void)? = nil
    ) {
        self.itemsProvider = itemsProvider
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
        self.onRightClickMenu = onRightClickMenu
        self.onDragCompleted = onDragCompleted
    }

    public func makeNSView(context: Context) -> MultiFileDragSourceNSView {
        let view = MultiFileDragSourceNSView()
        updateNSView(view, context: context)
        return view
    }

    public func updateNSView(_ nsView: MultiFileDragSourceNSView, context: Context) {
        nsView.itemsProvider = itemsProvider
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onRightClickMenu = onRightClickMenu
        nsView.onDragCompleted = onDragCompleted
    }
}

public final class WindowMoveHandleNSView: NSView {
    public var onDoubleClick: (() -> Void)?

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    public override var mouseDownCanMoveWindow: Bool {
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        DragSourceMonitor.shared.activeDragCount += 1
        self.window?.performDrag(with: event)
        DragSourceMonitor.shared.activeDragCount = max(0, DragSourceMonitor.shared.activeDragCount - 1)
    }
}

public struct WindowDragHandleOverlay: NSViewRepresentable {
    public var onDoubleClick: (() -> Void)? = nil

    public init(onDoubleClick: (() -> Void)? = nil) {
        self.onDoubleClick = onDoubleClick
    }

    public func makeNSView(context: Context) -> WindowMoveHandleNSView {
        let view = WindowMoveHandleNSView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    public func updateNSView(_ nsView: WindowMoveHandleNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}
