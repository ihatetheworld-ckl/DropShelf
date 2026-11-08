import AppKit
import XCTest
@testable import DropShelf

@MainActor final class ShelfHapticTests: XCTestCase {
    private var previousHaptics = false
    private var previousSound = false

    override func setUpWithError() throws {
        _ = NSApplication.shared
        previousHaptics = AppSettings.shared.hapticFeedbackEnabled
        previousSound = AppSettings.shared.soundEffectsEnabled
        AppSettings.shared.hapticFeedbackEnabled = true
        AppSettings.shared.soundEffectsEnabled = false
    }

    override func tearDownWithError() throws {
        AppSettings.shared.hapticFeedbackEnabled = previousHaptics
        AppSettings.shared.soundEffectsEnabled = previousSound
    }

    private func close(_ manager: ShelfManager) async throws {
        manager.closeAllShelves()
        let deadline = Date().addingTimeInterval(3)
        while !manager.activePanels.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(manager.activePanels.isEmpty)
    }

    func testNewAndReusedShelfRequestOneHapticEachEvenWithSoundOff() async throws {
        var requests = 0
        let manager = ShelfManager(hapticFeedback: { requests += 1 })
        let first = manager.summonShelf(at: CGPoint(x: 300, y: 300))
        XCTAssertEqual(requests, 1)
        let reused = manager.summonShelf(at: CGPoint(x: 400, y: 300))
        XCTAssertTrue(first === reused)
        XCTAssertEqual(requests, 2)
        try await close(manager)
        XCTAssertEqual(requests, 2) // Closing never requests a summon haptic.
    }

    func testHapticSettingIsIndependentAndCanBeDisabled() async throws {
        var requests = 0
        let manager = ShelfManager(hapticFeedback: { requests += 1 })
        AppSettings.shared.hapticFeedbackEnabled = false
        let first = manager.summonShelf()
        _ = manager.summonShelf()
        XCTAssertEqual(requests, 0)
        AppSettings.shared.hapticFeedbackEnabled = true
        _ = manager.summonShelf()
        XCTAssertEqual(requests, 1)
        first.viewModel.toggleCollapsed()
        manager.toggleAllCollapsed()
        XCTAssertEqual(requests, 1) // Resize/fold is not another summon.
        try await close(manager)
    }

    func testPinnedEmptyShelfGetsSeparateSummonFeedback() async throws {
        var requests = 0
        let manager = ShelfManager(hapticFeedback: { requests += 1 })
        let pinned = manager.summonShelf()
        pinned.viewModel.isPinned = true
        let second = manager.summonShelf()
        XCTAssertFalse(pinned === second)
        XCTAssertEqual(manager.activePanels.count, 2)
        XCTAssertEqual(requests, 2)
        try await close(manager)
    }
}
