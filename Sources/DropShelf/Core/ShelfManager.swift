import AppKit
import Combine
import Foundation

public final class ShelfManager: ObservableObject {
    public static let shared = ShelfManager()

    @Published public private(set) var activePanels: [ShelfPanel] = []
    private var nextShelfNumber: Int = 1
    private let hapticFeedback: () -> Void

    init(hapticFeedback: @escaping () -> Void = {
        // Re-fetch the performer for each user action: input devices/settings can
        // change. The system silently suppresses unsupported/unavailable feedback.
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }) {
        self.hapticFeedback = hapticFeedback
    }

    private func provideSummonFeedback() {
        if AppSettings.shared.hapticFeedbackEnabled { hapticFeedback() }
    }

    @discardableResult
    public func summonShelf(at point: CGPoint? = nil, initialItems: [ShelfItem] = []) -> ShelfPanel {
        let cursor = point ?? NSEvent.mouseLocation

        // Reuse an idle, unpinned empty shelf; never relocate a pinned or busy one.
        if initialItems.isEmpty,
           let existingEmpty = activePanels.first(where: { $0.viewModel.items.isEmpty && !$0.viewModel.isPinned && !$0.viewModel.isClosed && !$0.viewModel.isBusy && !$0.viewModel.isImporting }) {
            let center = CGPoint(x: cursor.x, y: cursor.y)
            let size = ShelfPanel.expandedSize
            existingEmpty.viewModel.isCollapsed = false
            existingEmpty.setFrame(NSRect(origin: ShelfPanel.clampedOrigin(forCenter: center, size: size), size: size), display: true)
            existingEmpty.orderFrontRegardless()
            existingEmpty.viewModel.scheduleEmptyShelfTimeout()
            provideSummonFeedback()
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
        provideSummonFeedback()

        if AppSettings.shared.soundEffectsEnabled {
            NSSound(named: NSSound.Name("Tink"))?.play()
        }

        return panel
    }

    @discardableResult
    public func summonShelfFromPasteboard(_ pasteboard: NSPasteboard = .general) -> ShelfPanel? {
        let panel = summonShelf(at: NSEvent.mouseLocation)
        _ = panel.viewModel.addFromPasteboard(pasteboard)
        return panel
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
        ShelfViewModel.toggleAllCollapsed(activePanels.map { $0.viewModel })
        for panel in activePanels where !panel.viewModel.isClosed { panel.orderFrontRegardless() }
    }

    private func removeShelf(id: UUID) {
        activePanels.removeAll { $0.viewModel.id == id }
        if activePanels.isEmpty {
            nextShelfNumber = 1
        }
    }
}
