import AppKit
import Combine
import Foundation

public final class ShelfManager: ObservableObject {
    public static let shared = ShelfManager()

    @Published public private(set) var activePanels: [ShelfPanel] = []
    private var nextShelfNumber: Int = 1

    private init() {}

    @discardableResult
    public func summonShelf(at point: CGPoint? = nil, initialItems: [ShelfItem] = []) -> ShelfPanel {
        let cursor = point ?? NSEvent.mouseLocation

        // If an empty shelf is already very close to cursor, reuse and bring it forward
        if initialItems.isEmpty,
           let existingEmpty = activePanels.first(where: { $0.viewModel.items.isEmpty }) {
            let center = CGPoint(x: cursor.x, y: cursor.y)
            let size = existingEmpty.frame.size
            let newOrigin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
            existingEmpty.setFrameOrigin(newOrigin)
            existingEmpty.orderFrontRegardless()
            existingEmpty.viewModel.scheduleEmptyShelfTimeout()
            return existingEmpty
        }

        // Offset slightly if another shelf is at the exact same location
        var targetCenter = cursor
        let overlapCount = activePanels.filter {
            hypot($0.frame.midX - cursor.x, $0.frame.midY - cursor.y) < 40
        }.count
        if overlapCount > 0 {
            targetCenter.x += CGFloat(overlapCount * 26)
            targetCenter.y -= CGFloat(overlapCount * 26)
        }

        let vm = ShelfViewModel(indexNumber: nextShelfNumber, initialItems: initialItems)
        nextShelfNumber += 1

        let panel = ShelfPanel(viewModel: vm, initialCenter: targetCenter)
        panel.onCloseShelf = { [weak self] shelfID in
            self?.removeShelf(id: shelfID)
        }

        activePanels.append(panel)
        panel.presentShelfAnimated()

        if AppSettings.shared.soundEffectsEnabled {
            NSSound(named: NSSound.Name("Tink"))?.play()
        }

        return panel
    }

    @discardableResult
    public func summonShelfFromPasteboard(_ pasteboard: NSPasteboard = .general) -> ShelfPanel? {
        let items = PasteboardExtractor.extractItems(from: pasteboard)
        return summonShelf(at: NSEvent.mouseLocation, initialItems: items)
    }

    public func closeAllShelves() {
        let current = activePanels
        for panel in current {
            panel.closeShelfAnimated()
        }
    }

    public func toggleAllCollapsed() {
        guard !activePanels.isEmpty else {
            _ = summonShelf(at: NSEvent.mouseLocation)
            return
        }
        let anyExpanded = activePanels.contains { !$0.viewModel.isCollapsed }
        for panel in activePanels {
            if panel.viewModel.isCollapsed == anyExpanded {
                panel.viewModel.toggleCollapsed()
            }
            panel.orderFrontRegardless()
        }
    }

    private func removeShelf(id: UUID) {
        activePanels.removeAll { $0.viewModel.id == id }
        if activePanels.isEmpty {
            nextShelfNumber = 1
        }
    }
}
