import XCTest
import AppKit
import Quartz
@testable import DropShelf

@MainActor final class ShelfStateTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DropShelfStateTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func item(_ name: String) throws -> ShelfItem {
        let url = root.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return ShelfItem(fileURL: url)
    }
    func waitForOperation(_ shelf: ShelfViewModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while shelf.isBusy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(shelf.isBusy)
    }
    func testBatchCollapseExpandedCollapsedAndMixed() {
        let a = ShelfViewModel(indexNumber: 1), b = ShelfViewModel(indexNumber: 2)
        ShelfViewModel.toggleAllCollapsed([a,b])
        XCTAssertTrue(a.isCollapsed && b.isCollapsed)
        ShelfViewModel.toggleAllCollapsed([a,b])
        XCTAssertFalse(a.isCollapsed || b.isCollapsed)
        a.isCollapsed = true
        ShelfViewModel.toggleAllCollapsed([a,b])
        XCTAssertTrue(a.isCollapsed && b.isCollapsed)
    }
    func testDuplicatesWithinOneDropAreIgnoredAndStaleSelectionDoesNotHideItems() throws {
        let a = try item("a.txt")
        let shelf = ShelfViewModel(indexNumber: 1)
        shelf.addItems([a,a,ShelfItem(fileURL: a.fileURL)])
        XCTAssertEqual(shelf.items.count, 1)
        shelf.selectedItemIDs = [UUID()]
        XCTAssertEqual(shelf.effectiveDragItems.map { $0.id }, [a.id])
    }
    func testZipPreservesUnselectedAndNewItemsAndRejectsDoubleStart() async throws {
        let a = try item("a.txt"), b = try item("b.txt"), added = try item("new.txt")
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [a,b])
        shelf.selectedItemIDs = [a.id]
        let store = TemporaryFileStore(root: root.appendingPathComponent("cache"))
        let gate = DispatchSemaphore(value: 0)
        shelf.archiveOperation = { inputs in
            XCTAssertFalse(Thread.isMainThread)
            _ = gate.wait(timeout: .now() + 5)
            return try FileOperationService.createArchive(inputs, store: store)
        }
        shelf.createZipArchive()
        shelf.createZipArchive()
        XCTAssertTrue(shelf.isBusy)
        shelf.addItems([added])
        shelf.clearAll() // protected while the file task is in progress
        XCTAssertFalse(shelf.beginClosing())
        gate.signal()
        try await waitForOperation(shelf)
        XCTAssertEqual(shelf.items.count, 3)
        XCTAssertTrue(shelf.items.contains { $0.id == b.id })
        XCTAssertTrue(shelf.items.contains { $0.id == added.id })
        let zip = try XCTUnwrap(shelf.items.first { $0.fileURL.pathExtension == "zip" })
        XCTAssertTrue(zip.isTemporaryFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.fileURL.path))
    }
    func testZipFailureRetainsItemsAndReportsError() async throws {
        let a = try item("original.txt")
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [a])
        shelf.archiveOperation = { _ in throw CocoaError(.fileReadNoPermission) }
        shelf.createZipArchive()
        try await waitForOperation(shelf)
        XCTAssertEqual(shelf.items.map { $0.id }, [a.id])
        XCTAssertTrue(shelf.lastOperationReport?.contains("失败") == true)
    }
    func testPartialMoveRetainsConflictAndFailureAndAcceptsNewItems() async throws {
        let a = try item("a.txt"), b = try item("b.txt"), added = try item("new.txt")
        let destination = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data("existing".utf8).write(to: destination.appendingPathComponent("b.txt"))
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [a,b])
        shelf.moveItems([a,b], to: destination)
        shelf.addItems([added])
        try await waitForOperation(shelf)
        XCTAssertEqual(Set(shelf.items.map { $0.id }), [b.id,added.id])
        XCTAssertTrue(shelf.lastOperationReport?.contains("移动 1") == true)
        XCTAssertTrue(shelf.lastOperationReport?.contains("同名跳过 1") == true)
        XCTAssertEqual(try String(contentsOf: b.fileURL), "b.txt")
    }
    func testPinClearAndRepeatedClose() throws {
        let a = try item("original.txt")
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [a])
        var closeRequests = 0
        shelf.onRequestClose = { closeRequests += 1 }
        shelf.isPinned = true
        shelf.clearAll()
        XCTAssertEqual(closeRequests, 0)
        XCTAssertTrue(shelf.beginClosing())
        XCTAssertFalse(shelf.beginClosing())
        shelf.addItems([a])
        XCTAssertTrue(shelf.items.isEmpty)
        XCTAssertEqual(try String(contentsOf: a.fileURL), "original.txt")
    }
    func testRealPanelCloseIsIdempotentAndClampedToScreen() async throws {
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [try item("panel.txt")])
        let panel = ShelfPanel(viewModel: shelf, initialCenter: CGPoint(x: -10000, y: -10000))
        var closes = 0
        let closed = expectation(description: "close completes once")
        panel.onCloseShelf = { _ in closes += 1; closed.fulfill() }
        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) })
        panel.presentShelfAnimated()
        panel.closeShelfAnimated()
        panel.closeShelfAnimated()
        await fulfillment(of: [closed], timeout: 3)
        XCTAssertEqual(closes, 1)
        XCTAssertFalse(panel.isVisible)
    }
    func testEmptyShelfTimeoutCollapsesAndPinPreventsIt() async throws {
        let settings = AppSettings.shared
        let previous = settings.autoCollapseEmptyShelfSeconds
        defer { settings.autoCollapseEmptyShelfSeconds = previous }
        settings.autoCollapseEmptyShelfSeconds = 0.05
        let empty = ShelfViewModel(indexNumber: 1)
        let pinned = ShelfViewModel(indexNumber: 2)
        pinned.isPinned = true
        let collapsed = expectation(description: "empty shelf collapses after timeout")
        empty.onRequestResize = { value in
            XCTAssertTrue(value)
            collapsed.fulfill()
        }
        let pinnedResized = expectation(description: "pinned shelf must not collapse")
        pinnedResized.isInverted = true
        pinned.onRequestResize = { _ in pinnedResized.fulfill() }
        var closeCount = 0
        empty.onRequestClose = { closeCount += 1 }
        // Wait for the Timer's actual callback, rather than racing its run-loop
        // scheduling against a fixed Task.sleep on a loaded CI runner.
        await fulfillment(of: [collapsed], timeout: 5)
        await fulfillment(of: [pinnedResized], timeout: 0.2)
        XCTAssertTrue(empty.isCollapsed)
        XCTAssertFalse(pinned.isCollapsed)
        XCTAssertEqual(closeCount, 0)
    }
    func testAsyncImportSnapshotsPasteboardBeforeItChangesAndIgnoresClosedShelf() async throws {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.setString("snapshot text", forType: .string)
        let shelf = ShelfViewModel(indexNumber: 1)
        XCTAssertTrue(shelf.addFromPasteboard(pb))
        pb.clearContents()
        pb.setString("changed", forType: .string)
        for _ in 0..<200 where shelf.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(shelf.items.first?.fileURL)), "snapshot text")
        let closed = ShelfViewModel(indexNumber: 2)
        XCTAssertTrue(closed.addFromPasteboard(pb))
        XCTAssertTrue(closed.beginClosing())
        for _ in 0..<200 where closed.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(closed.items.isEmpty)
    }
    func testPanelRendersGridStackAndCollapsedLayouts() async throws {
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [try item("first.txt"), try item("second.txt")])
        shelf.isPinned = true
        let panel = ShelfPanel(viewModel: shelf, initialCenter: NSEvent.mouseLocation)
        panel.presentShelfAnimated()
        defer { panel.closeShelfAnimated() }
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for mode in ["stack", "grid", "collapsed"] {
            shelf.isGridView = mode == "grid"
            if mode == "collapsed" { shelf.toggleCollapsed() }
            try await Task.sleep(nanoseconds: 300_000_000)
            let view = try XCTUnwrap(panel.contentView)
            view.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent("ui-" + mode + ".png"))
            // AppKit can align the initial content rectangle to backing pixels.
            let expected = mode == "collapsed" ? ShelfPanel.collapsedSize : ShelfPanel.expandedSize
            XCTAssertEqual(panel.frame.width, expected.width, accuracy: 1)
            XCTAssertEqual(panel.frame.height, expected.height, accuracy: 1)
        }
    }

    func testQuickLookKeepsStableSnapshotAndDisconnectsWhenShelfCloses() async throws {
        let a = try item("preview-a.txt"), b = try item("preview-b.txt")
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [a,b])
        shelf.isPinned = true
        shelf.selectedItemIDs = [a.id]
        let panel = ShelfPanel(viewModel: shelf, initialCenter: NSEvent.mouseLocation)
        panel.presentShelfAnimated()
        panel.toggleQuickLookPreview()
        let preview = try XCTUnwrap(QLPreviewPanel.shared())
        XCTAssertTrue(preview.isVisible)
        shelf.selectedItemIDs = [b.id]
        shelf.clearAll()
        XCTAssertEqual(panel.numberOfPreviewItems(in: preview), 1)
        XCTAssertEqual(panel.previewPanel(preview, previewItemAt: 0) as? NSURL, a.fileURL as NSURL)
        panel.closeShelfAnimated()
        for _ in 0..<300 where preview.isVisible { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(preview.isVisible)
        XCTAssertNil(preview.dataSource)
        XCTAssertEqual(try String(contentsOf: a.fileURL), "preview-a.txt")
    }

    func testQuitDefersWhileFileOperationIsRunning() async throws {
        let panel = ShelfManager.shared.summonShelf(initialItems: [try item("quit-test.txt")])
        let shelf = panel.viewModel
        let store = TemporaryFileStore(root: root.appendingPathComponent("quit-cache"))
        let gate = DispatchSemaphore(value: 0)
        shelf.archiveOperation = { inputs in
            _ = gate.wait(timeout: .now() + 5)
            return try FileOperationService.createArchive(inputs, store: store)
        }
        shelf.createZipArchive()
        let delegate = AppDelegate()
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateCancel)
        gate.signal()
        try await waitForOperation(shelf)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
        panel.closeShelfAnimated()
    }

}
