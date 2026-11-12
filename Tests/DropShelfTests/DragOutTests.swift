import AppKit
import XCTest
@testable import DropShelf

/// Exercises the real source callbacks and URL payloads without synthesizing a Finder drop.
@MainActor final class DragOutTests: XCTestCase {
    private var root: URL!
    private var previousCopy = false
    private var previousRemove = false
    private var previousSound = false
    private var initialDragCount = 0
    private let session = NSDraggingSession()

    override func setUpWithError() throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DropShelfDragTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        previousCopy = AppSettings.shared.alwaysCopyOnDragOut
        previousRemove = AppSettings.shared.removeItemsAfterDragOut
        previousSound = AppSettings.shared.soundEffectsEnabled
        AppSettings.shared.alwaysCopyOnDragOut = false
        AppSettings.shared.removeItemsAfterDragOut = true
        AppSettings.shared.soundEffectsEnabled = false
        initialDragCount = DragSourceMonitor.shared.activeDragCount
    }

    override func tearDownWithError() throws {
        AppSettings.shared.alwaysCopyOnDragOut = previousCopy
        AppSettings.shared.removeItemsAfterDragOut = previousRemove
        AppSettings.shared.soundEffectsEnabled = previousSound
        XCTAssertEqual(DragSourceMonitor.shared.activeDragCount, initialDragCount)
        try FileManager.default.removeItem(at: root)
    }

    private func item(_ name: String, folder: Bool = false) throws -> ShelfItem {
        let url = root.appendingPathComponent(name, isDirectory: folder)
        if folder {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try Data("folder contents".utf8).write(to: url.appendingPathComponent("inside.txt"))
        } else {
            try Data(name.utf8).write(to: url)
        }
        return ShelfItem(fileURL: url)
    }

    private func source(for shelf: ShelfViewModel) -> MultiFileDragSourceNSView {
        let view = MultiFileDragSourceNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.onDragCompleted = { shelf.completeDrag(withIDs: $0, operation: $1) }
        return view
    }

    private func end(_ source: MultiFileDragSourceNSView, _ operation: NSDragOperation = []) {
        source.draggingSession(session, endedAt: .zero, operation: operation)
    }

    func testOriginalFilesAndFoldersPublishURLsAndAllowNativeCopyMoveOnly() throws {
        let file = try item("file.txt"), folder = try item("folder", folder: true)
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [file, folder])
        let view = source(for: shelf)
        let dragging = try XCTUnwrap(view.prepareDraggingItems(shelf.items))
        defer { end(view) }
        let mask = view.draggingSession(session, sourceOperationMaskFor: .outsideApplication)
        XCTAssertEqual(mask, [.copy, .move])
        XCTAssertFalse(mask.contains(.link))
        XCTAssertFalse(mask.contains(.generic))
        XCTAssertFalse(mask.contains(.delete))
        XCTAssertEqual(view.draggingSession(session, sourceOperationMaskFor: .withinApplication), .copy)
        XCTAssertFalse(view.ignoreModifierKeys(for: session)) // AppKit handles Option/Command.
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        XCTAssertTrue(pb.writeObjects(try dragging.map { try XCTUnwrap($0.item as? NSURL) }))
        let exported = try XCTUnwrap(pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])
        XCTAssertEqual(exported, [file.fileURL, folder.fileURL])
        XCTAssertEqual(try String(contentsOf: folder.fileURL.appendingPathComponent("inside.txt")), "folder contents")
    }

    func testAlwaysCopySettingIsPersistedAndCapturedForWholeGesture() throws {
        let file = try item("copy.txt")
        let view = source(for: ShelfViewModel(indexNumber: 1, initialItems: [file]))
        AppSettings.shared.alwaysCopyOnDragOut = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "alwaysCopyOnDragOut"))
        XCTAssertNotNil(view.prepareDraggingItems([file]))
        AppSettings.shared.alwaysCopyOnDragOut = false
        XCTAssertEqual(view.draggingSession(session, sourceOperationMaskFor: .outsideApplication), .copy)
        XCTAssertTrue(view.ignoreModifierKeys(for: session))
        end(view)
        XCTAssertNotNil(view.prepareDraggingItems([file]))
        XCTAssertEqual(view.draggingSession(session, sourceOperationMaskFor: .outsideApplication), [.copy, .move])
        XCTAssertFalse(view.ignoreModifierKeys(for: session))
        end(view)
    }

    func testMixedTemporaryBatchAlwaysCopiesAndSurvivesSourceShelfClosing() throws {
        let store = TemporaryFileStore(root: root.appendingPathComponent("cache"))
        let resource = try store.createResource(filename: "snippet.txt")
        try Data("shared snippet".utf8).write(to: resource.fileURL)
        let temporary = ShelfItem(resource: resource)
        let original = try item("original.txt")
        let first = ShelfViewModel(indexNumber: 1, initialItems: [original, temporary])
        let view = source(for: first)
        let dragging = try XCTUnwrap(view.prepareDraggingItems(first.items))
        XCTAssertEqual(view.draggingSession(session, sourceOperationMaskFor: .outsideApplication), .copy)
        XCTAssertTrue(view.ignoreModifierKeys(for: session))
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        XCTAssertTrue(pb.writeObjects(try dragging.map { try XCTUnwrap($0.item as? NSURL) }))
        let second = ShelfViewModel(indexNumber: 2, initialItems: PasteboardExtractor.extractItems(from: pb))
        XCTAssertEqual(second.items.count, 2)
        end(view, .copy)
        XCTAssertTrue(first.items.isEmpty)
        XCTAssertTrue(first.beginClosing())
        store.sweepAbandonedSessions()
        XCTAssertEqual(try String(contentsOf: temporary.fileURL), "shared snippet")
        XCTAssertEqual(try String(contentsOf: original.fileURL), "original.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resource.directory.appendingPathComponent(".exported").path))
        XCTAssertTrue(second.items.contains { $0.fileURL == temporary.fileURL })
    }

    func testCancelledMultiSelectionPreservesItemsAndIgnoresLateCompletion() throws {
        let a = try item("a.txt"), b = try item("b.txt"), added = try item("added.txt")
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [a, b])
        shelf.selectedItemIDs = [a.id]
        let view = source(for: shelf)
        XCTAssertNotNil(view.prepareDraggingItems(shelf.effectiveDragItems))
        shelf.addItems([added])
        shelf.selectedItemIDs = [b.id]
        end(view)
        end(view, .copy)
        XCTAssertEqual(Set(shelf.items.map(\.id)), [a.id, b.id, added.id])
        XCTAssertEqual(shelf.selectedItemIDs, [b.id])
        XCTAssertEqual(try String(contentsOf: a.fileURL), "a.txt")
    }

    func testCopyCompletionRemovesOnlySnapshotAndRunsOnce() throws {
        let a = try item("a.txt"), b = try item("b.txt"), added = try item("new.txt")
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [a, b])
        let view = source(for: shelf)
        var callbacks = 0
        view.onDragCompleted = { ids, operation in
            callbacks += 1
            XCTAssertFalse(DragSourceMonitor.shared.isDraggingFromShelf)
            shelf.completeDrag(withIDs: ids, operation: operation)
        }
        XCTAssertNotNil(view.prepareDraggingItems([a]))
        XCTAssertNil(view.prepareDraggingItems([b])) // No overlapping snapshot.
        shelf.addItems([added])
        shelf.selectedItemIDs = [b.id]
        end(view, .copy)
        end(view, .copy)
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(Set(shelf.items.map(\.id)), [b.id, added.id])
        XCTAssertEqual(try String(contentsOf: a.fileURL), "a.txt")
    }

    func testCopyWithAutomaticRemovalDisabledKeepsShelf() throws {
        AppSettings.shared.removeItemsAfterDragOut = false
        let file = try item("keep.txt")
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [file])
        let view = source(for: shelf)
        XCTAssertNotNil(view.prepareDraggingItems([file]))
        end(view, .copy)
        XCTAssertEqual(shelf.items.map(\.id), [file.id])
        XCTAssertEqual(try String(contentsOf: file.fileURL), "keep.txt")
    }

    func testReportedMoveNeverDeletesSourceOrDiscardsUnconfirmedItems() throws {
        let file = try item("unconfirmed.txt")
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [file])
        let view = source(for: shelf)
        XCTAssertNotNil(view.prepareDraggingItems([file]))
        end(view, .move)
        XCTAssertEqual(shelf.items.map(\.id), [file.id])
        XCTAssertEqual(try String(contentsOf: file.fileURL), "unconfirmed.txt")
        XCTAssertTrue(shelf.statusMessage?.contains("保留") == true)
    }

    func testPartialMoveKeepsSkippedFileAndNewItemsWithoutStaleMovedReferences() throws {
        AppSettings.shared.removeItemsAfterDragOut = false
        let file = try item("file.txt"), folder = try item("folder", folder: true)
        let skipped = try item("skipped.txt"), added = try item("added.txt")
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [file, folder, skipped])
        let view = source(for: shelf)
        XCTAssertNotNil(view.prepareDraggingItems(shelf.items))
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        // Emulate a receiver moving two paths and skipping the third. This is a
        // real filesystem/state regression, not a Finder end-to-end test.
        try FileManager.default.moveItem(at: file.fileURL, to: destination.appendingPathComponent("file.txt"))
        try FileManager.default.moveItem(at: folder.fileURL, to: destination.appendingPathComponent("folder"))
        shelf.addItems([added])
        end(view, .move)
        XCTAssertEqual(Set(shelf.items.map(\.id)), [skipped.id, added.id])
        XCTAssertEqual(try String(contentsOf: skipped.fileURL), "skipped.txt")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("file.txt")), "file.txt")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("folder/inside.txt")), "folder contents")
    }

    func testUnsupportedOperationsNeverCompleteOrDeleteAnything() throws {
        let file = try item("safe.txt")
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [file])
        let view = source(for: shelf)
        var callbacks = 0
        view.onDragCompleted = { _, _ in callbacks += 1 }
        for operation: NSDragOperation in [.link, .generic, .delete] {
            XCTAssertNotNil(view.prepareDraggingItems([file]))
            end(view, operation)
        }
        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(shelf.items.map(\.id), [file.id])
        XCTAssertEqual(try String(contentsOf: file.fileURL), "safe.txt")
    }

    func testDanglingSymlinkIsNotMistakenForMovedSource() throws {
        let target = try item("target.txt")
        let linkURL = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: target.fileURL)
        let link = ShelfItem(fileURL: linkURL)
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [link])
        let view = source(for: shelf)
        XCTAssertNotNil(view.prepareDraggingItems([link]))
        try FileManager.default.removeItem(at: target.fileURL)
        end(view, .move)
        XCTAssertEqual(shelf.items.map(\.id), [link.id])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path), target.fileURL.path)
    }

    func testMissingFilePreventsWholeDragAndDoesNotEnterDraggingState() throws {
        let present = try item("present.txt"), missing = try item("missing.txt")
        try FileManager.default.removeItem(at: missing.fileURL)
        let shelf = ShelfViewModel(indexNumber: 1, initialItems: [present, missing])
        let view = source(for: shelf)
        XCTAssertNil(view.prepareDraggingItems(shelf.items))
        XCTAssertEqual(DragSourceMonitor.shared.activeDragCount, initialDragCount)
        XCTAssertEqual(shelf.items.count, 2)
        XCTAssertEqual(try String(contentsOf: present.fileURL), "present.txt")
    }
}
