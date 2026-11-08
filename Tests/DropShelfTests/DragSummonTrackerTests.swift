import AppKit
import XCTest
@testable import DropShelf

final class DragSummonTrackerTests: XCTestCase {
    private let wave: [CGFloat] = [100, 140, 90, 140, 90]

    private func shake(_ tracker: inout DragSummonTracker, revision: Int,
                       supported: Bool = true, start: TimeInterval = 10,
                       internalDrag: Bool = false, interval: TimeInterval = 0.06) -> Int {
        wave.enumerated().filter { index, x in
            tracker.shouldSummon(at: CGPoint(x: x, y: 200), time: start + Double(index) * interval,
                                 pasteboardChangeCount: revision, containsSupportedContent: supported,
                                 isInternalDrag: internalDrag)
        }.count
    }

    func testThreeFingerMotionWithStaleFilePasteboardNeverSummons() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 42)
        XCTAssertEqual(shake(&tracker, revision: 42), 0)
        XCTAssertEqual(shake(&tracker, revision: 42, start: 20), 0)
    }

    @MainActor func testRealPasteboardTypesCanRemainAfterGestureAndNeedNewGeneration() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("DropShelf-DragInput-\(UUID()).txt")
        try Data("test input".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(pasteboard.writeObjects([file as NSURL]))
        XCTAssertTrue(ShakeDetector.containsSupportedContent(types: pasteboard.types))
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: pasteboard.changeCount)
        XCTAssertEqual(shake(&tracker, revision: pasteboard.changeCount), 0)
        // A source declaring a new drag advances ownership/changeCount.
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([file as NSURL]))
        XCTAssertEqual(shake(&tracker, revision: pasteboard.changeCount, start: 20), 1)
        tracker.endGesture()
        XCTAssertTrue(ShakeDetector.containsSupportedContent(types: pasteboard.types))
        tracker.beginGesture(pasteboardChangeCount: pasteboard.changeCount)
        XCTAssertEqual(shake(&tracker, revision: pasteboard.changeCount, start: 30), 0)
    }

    func testFreshFileDragShakeSummonsExactlyOnce() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 42)
        XCTAssertEqual(shake(&tracker, revision: 43), 1)
        XCTAssertEqual(shake(&tracker, revision: 43, start: 20), 0)
    }

    func testCompletedOrCancelledDragCannotArmNextEmptyGesture() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 42)
        XCTAssertEqual(shake(&tracker, revision: 43), 1)
        tracker.endGesture()
        tracker.beginGesture(pasteboardChangeCount: 43)
        XCTAssertEqual(shake(&tracker, revision: 43, start: 20), 0)
        // A new real drag is still allowed after the cancelled/empty gesture.
        tracker.endGesture()
        tracker.beginGesture(pasteboardChangeCount: 43)
        XCTAssertEqual(shake(&tracker, revision: 44, start: 30), 1)
    }

    func testNoMouseDownOrMouseUpRejectsEvenFreshContent() {
        var tracker = DragSummonTracker()
        XCTAssertEqual(shake(&tracker, revision: 1), 0)
        tracker.beginGesture(pasteboardChangeCount: 1)
        tracker.endGesture()
        XCTAssertEqual(shake(&tracker, revision: 2), 0)
    }

    func testMouseDownResetsEvenIfPreviousMouseUpWasMissed() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 1)
        XCTAssertEqual(shake(&tracker, revision: 2), 1)
        tracker.beginGesture(pasteboardChangeCount: 2)
        XCTAssertEqual(shake(&tracker, revision: 2, start: 20), 0)
    }

    func testInternalDragCannotSummonAnotherShelf() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 1)
        XCTAssertEqual(shake(&tracker, revision: 2, internalDrag: true), 0)
        XCTAssertFalse(tracker.shouldSummon(at: .zero, time: 20, pasteboardChangeCount: 2,
                                         containsSupportedContent: true, optionHeld: true, isInternalDrag: true))
    }

    func testEmptyOrUnsupportedContentIsRejected() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 1)
        XCTAssertEqual(shake(&tracker, revision: 2, supported: false), 0)
        XCTAssertFalse(ShakeDetector.containsSupportedContent(types: nil))
        XCTAssertFalse(ShakeDetector.containsSupportedContent(types: []))
        XCTAssertFalse(ShakeDetector.containsSupportedContent(types: [.color]))
        for type in [NSPasteboard.PasteboardType.fileURL, .URL, .png, .tiff, .string,
                     NSPasteboard.PasteboardType("NSFilenamesPboardType")] {
            XCTAssertTrue(ShakeDetector.containsSupportedContent(types: [type]))
        }
    }

    func testOptionAlsoRequiresFreshActualContent() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 42)
        XCTAssertFalse(tracker.shouldSummon(at: .zero, time: 10, pasteboardChangeCount: 42,
                                         containsSupportedContent: true, optionHeld: true))
        XCTAssertFalse(tracker.shouldSummon(at: .zero, time: 10, pasteboardChangeCount: 43,
                                         containsSupportedContent: false, optionHeld: true))
        XCTAssertTrue(tracker.shouldSummon(at: .zero, time: 10, pasteboardChangeCount: 43,
                                        containsSupportedContent: true, optionHeld: true))
    }

    func testPasteboardUpdatesDoNotResummonWithinOneGesture() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 1)
        XCTAssertEqual(shake(&tracker, revision: 2), 1)
        XCTAssertEqual(shake(&tracker, revision: 3, start: 20), 0)
        XCTAssertFalse(tracker.shouldSummon(at: .zero, time: 30, pasteboardChangeCount: 4,
                                         containsSupportedContent: true, optionHeld: true))
    }

    func testMovementBeforeRealContentDoesNotCountTowardShake() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 1)
        XCTAssertEqual(shake(&tracker, revision: 1), 0)
        XCTAssertFalse(tracker.shouldSummon(at: CGPoint(x: 100, y: 200), time: 10.25,
                                         pasteboardChangeCount: 2, containsSupportedContent: true))
        XCTAssertEqual(shake(&tracker, revision: 2, start: 10.3), 1)
    }

    func testNewContentGenerationDiscardsPreviousMotion() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 1)
        for (index, x) in wave.prefix(4).enumerated() {
            XCTAssertFalse(tracker.shouldSummon(at: CGPoint(x: x, y: 200), time: 10 + Double(index) * 0.06,
                                             pasteboardChangeCount: 2, containsSupportedContent: true))
        }
        XCTAssertFalse(tracker.shouldSummon(at: CGPoint(x: 90, y: 200), time: 10.24,
                                         pasteboardChangeCount: 3, containsSupportedContent: true))
    }

    func testSlowMotionDoesNotTrigger() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 1)
        XCTAssertEqual(shake(&tracker, revision: 2, interval: 0.3), 0)
    }

    func testSettingsDisableBothTriggerPaths() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 1)
        for (index, x) in wave.enumerated() {
            XCTAssertFalse(tracker.shouldSummon(at: CGPoint(x: x, y: 200), time: 10 + Double(index) * 0.06,
                                             pasteboardChangeCount: 2, containsSupportedContent: true,
                                             optionHeld: true, shakeEnabled: false, optionEnabled: false))
        }
        XCTAssertTrue(tracker.shouldSummon(at: .zero, time: 20, pasteboardChangeCount: 2,
                                        containsSupportedContent: true, optionHeld: true, shakeEnabled: false))
    }

    func testCooldownAppliesBetweenRealGestures() {
        var tracker = DragSummonTracker()
        tracker.beginGesture(pasteboardChangeCount: 1)
        XCTAssertTrue(tracker.shouldSummon(at: .zero, time: 10, pasteboardChangeCount: 2,
                                        containsSupportedContent: true, optionHeld: true))
        tracker.endGesture()
        tracker.beginGesture(pasteboardChangeCount: 2)
        XCTAssertFalse(tracker.shouldSummon(at: .zero, time: 10.5, pasteboardChangeCount: 3,
                                         containsSupportedContent: true, optionHeld: true))
        XCTAssertTrue(tracker.shouldSummon(at: .zero, time: 11, pasteboardChangeCount: 3,
                                        containsSupportedContent: true, optionHeld: true))
    }
}
