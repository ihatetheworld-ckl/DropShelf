import AppKit
import XCTest
@testable import DropShelf

@MainActor final class ShelfHapticFeedbackTests: XCTestCase {
    private var previousEnabled = false
    private var previousStyle = SummonHapticStyle.singleTap

    override func setUpWithError() throws {
        _ = NSApplication.shared
        previousEnabled = AppSettings.shared.hapticFeedbackEnabled
        previousStyle = AppSettings.shared.summonHapticStyle
        AppSettings.shared.hapticFeedbackEnabled = true
        AppSettings.shared.summonHapticStyle = .doubleTap
    }

    override func tearDownWithError() throws {
        AppSettings.shared.hapticFeedbackEnabled = previousEnabled
        AppSettings.shared.summonHapticStyle = previousStyle
    }

    func testDoubleTapRequestsOneImmediateAndOneDelayedCue() {
        var requests = 0
        var scheduled: [(TimeInterval, () -> Void)] = []
        let feedback = ShelfHapticFeedback(perform: { requests += 1 }, schedule: { scheduled.append(($0, $1)) })
        feedback.play()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].0, 0.12, accuracy: 0.001)
        scheduled[0].1()
        XCTAssertEqual(requests, 2)
        withExtendedLifetime(feedback) {}
    }

    func testSingleTapPreferencePersistsAndHasNoDelayedCue() {
        AppSettings.shared.summonHapticStyle = .singleTap
        XCTAssertEqual(UserDefaults.standard.string(forKey: "summonHapticStyle"), "singleTap")
        var requests = 0
        let feedback = ShelfHapticFeedback(perform: { requests += 1 }, schedule: { _, _ in XCTFail("Single cue must not schedule another") })
        feedback.play()
        XCTAssertEqual(requests, 1)
    }

    func testDisabledFeedbackNeitherPerformsNorSchedules() {
        AppSettings.shared.hapticFeedbackEnabled = false
        let feedback = ShelfHapticFeedback(perform: { XCTFail("Disabled feedback") }, schedule: { _, _ in XCTFail("Disabled feedback") })
        feedback.play()
    }

    func testDisableThenReenableCancelsOldSecondTap() {
        var requests = 0
        var pending: (() -> Void)?
        let feedback = ShelfHapticFeedback(perform: { requests += 1 }, schedule: { _, action in pending = action })
        feedback.play()
        AppSettings.shared.hapticFeedbackEnabled = false
        AppSettings.shared.hapticFeedbackEnabled = true
        pending?()
        XCTAssertEqual(requests, 1)
        withExtendedLifetime(feedback) {}
    }

    func testChangingStyleAwayAndBackCancelsOldSecondTap() {
        var requests = 0
        var pending: (() -> Void)?
        let feedback = ShelfHapticFeedback(perform: { requests += 1 }, schedule: { _, action in pending = action })
        feedback.play()
        AppSettings.shared.summonHapticStyle = .singleTap
        AppSettings.shared.summonHapticStyle = .doubleTap
        pending?()
        XCTAssertEqual(requests, 1)
        withExtendedLifetime(feedback) {}
    }

    func testNewSummonOrPreviewCancelsPreviousDelayedCue() {
        var requests = 0
        var pending: [() -> Void] = []
        let feedback = ShelfHapticFeedback(perform: { requests += 1 }, schedule: { _, action in pending.append(action) })
        feedback.play()
        feedback.play()
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(pending.count, 2)
        pending[0]()
        XCTAssertEqual(requests, 2)
        pending[1]()
        XCTAssertEqual(requests, 3)
        withExtendedLifetime(feedback) {}
    }

    func testCancelAndDeallocationPreventOrphanedFeedback() {
        var requests = 0
        var pending: [() -> Void] = []
        var feedback: ShelfHapticFeedback? = ShelfHapticFeedback(perform: { requests += 1 }, schedule: { _, action in pending.append(action) })
        feedback?.play()
        feedback?.cancelPendingFeedback()
        pending[0]()
        XCTAssertEqual(requests, 1)
        feedback?.play()
        feedback = nil
        pending[1]()
        XCTAssertEqual(requests, 2)
    }

    func testRealSchedulerRunsBothCuesOnMainWithoutBlockingCaller() async {
        var requests = 0
        let completed = expectation(description: "Both cue requests")
        completed.expectedFulfillmentCount = 2
        completed.assertForOverFulfill = true
        let feedback = ShelfHapticFeedback(perform: {
            XCTAssertTrue(Thread.isMainThread)
            requests += 1
            completed.fulfill()
        })
        feedback.play()
        XCTAssertEqual(requests, 1) // No synchronous sleep while waiting for tap two.
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(requests, 2)
        withExtendedLifetime(feedback) {}
    }
}
