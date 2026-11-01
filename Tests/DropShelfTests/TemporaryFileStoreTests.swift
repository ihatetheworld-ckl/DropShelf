import XCTest
import AppKit
@testable import DropShelf

final class TemporaryFileStoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DropShelfCacheTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testLastLeaseCleansUnexportedResource() throws {
        let store = TemporaryFileStore(root: root)
        var first: TemporaryResource? = try store.createResource(filename: "image.png")
        let url = first!.fileURL
        try Data("test".utf8).write(to: url)
        var second = first
        first = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNotNil(second)
        second = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testExportSurvivesLeaseReleaseAndStartupSweep() throws {
        var store: TemporaryFileStore? = TemporaryFileStore(root: root)
        var resource: TemporaryResource? = try store!.createResource(filename: "snippet.txt")
        let url = resource!.fileURL
        try Data("clipboard".utf8).write(to: url)
        try resource!.preserveForExternalUse()
        resource = nil
        store = nil
        let restarted = TemporaryFileStore(root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let adopted = restarted.resource(for: url)
        XCTAssertNotNil(adopted)
        XCTAssertEqual(try String(contentsOf: url), "clipboard")
    }
    func testAbandonedJobsAndUnexportedAssetsAreSweptButLiveSessionsAreNot() throws {
        var abandoned: TemporaryFileStore? = TemporaryFileStore(root: root)
        let staleSession = abandoned!.session
        let job = try abandoned!.createWorkspace()
        // Simulate a crash by leaving an asset directory without an in-memory lease.
        let staleAsset = staleSession.appendingPathComponent("asset-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staleAsset, withIntermediateDirectories: false)
        let live = TemporaryFileStore(root: root)
        let liveJob = try live.createWorkspace()
        XCTAssertTrue(FileManager.default.fileExists(atPath: job.path))
        abandoned = nil
        live.sweepAbandonedSessions()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleSession.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveJob.path))
    }
    func testSweepDoesNotDeleteUnmarkedDirectoriesOrFollowSymlinks() throws {
        let outside = root.appendingPathComponent("user-originals")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let original = outside.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: original)
        let link = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let unmarked = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: unmarked, withIntermediateDirectories: false)
        let store = TemporaryFileStore(root: root)
        store.sweepAbandonedSessions()
        XCTAssertEqual(try String(contentsOf: original), "keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unmarked.path))
        XCTAssertNil(store.resource(for: original))
    }
    @MainActor func testTemporaryFlagCannotAdoptOrDeleteUserOriginal() throws {
        _ = NSApplication.shared
        let url = root.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: url)
        autoreleasepool {
            let item = ShelfItem(fileURL: url, isTemporaryFile: true)
            XCTAssertFalse(item.isTemporaryFile)
            let shelf = ShelfViewModel(indexNumber: 1, initialItems: [item])
            shelf.clearAll()
        }
        XCTAssertEqual(try String(contentsOf: url), "original")
    }
    @MainActor func testClipboardAndCrossShelfCloseKeepTemporaryURLValid() async throws {
        _ = NSApplication.shared
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.setString("  exact text\n", forType: .string)
        var extracted = PasteboardExtractor.extractItems(from: pb)
        let url = try XCTUnwrap(extracted.first?.fileURL)
        XCTAssertEqual(try String(contentsOf: url), "  exact text\n")
        let first = ShelfViewModel(indexNumber: 1, initialItems: extracted)
        first.copyItemsToClipboard(pb)
        let second = ShelfViewModel(indexNumber: 2)
        XCTAssertTrue(second.addFromPasteboard(pb))
        for _ in 0..<200 where second.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(second.isImporting)
        XCTAssertTrue(second.items[0].isTemporaryFile)
        extracted.removeAll()
        XCTAssertTrue(first.beginClosing())
        XCTAssertEqual(try String(contentsOf: second.items[0].fileURL), "  exact text\n")
        XCTAssertTrue(second.beginClosing())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // Exported test data only; never touch the user's real clipboard/cache.
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
    @MainActor func testImageAndWebLinkMaterializeAsOwnedFiles() throws {
        _ = NSApplication.shared
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus(); NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill(); image.unlockFocus()
        pb.writeObjects([image])
        let images = PasteboardExtractor.extractItems(from: pb)
        XCTAssertEqual(images.first?.kind, .image)
        XCTAssertTrue(images.first?.isTemporaryFile == true)
        XCTAssertNotNil(NSImage(contentsOf: try XCTUnwrap(images.first?.fileURL)))
        pb.clearContents()
        pb.writeObjects([URL(string: "https://example.com/test")! as NSURL])
        let links = PasteboardExtractor.extractItems(from: pb)
        let data = try Data(contentsOf: XCTUnwrap(links.first?.fileURL))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        XCTAssertEqual(plist?["URL"], "https://example.com/test")
        XCTAssertTrue(links.first?.isTemporaryFile == true)
    }
}
