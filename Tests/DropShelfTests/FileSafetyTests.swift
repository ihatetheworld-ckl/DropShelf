import XCTest
import AppKit
@testable import DropShelf

final class FileSafetyTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DropShelfTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func file(_ relative: String, _ content: String = "original") throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }
    func contents(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func testSameLocationNeverDeletesSource() throws {
        let source = try file("document.txt")
        let result = FileOperationService.move([.init(url: source)], to: root)
        XCTAssertEqual(result[0].state, .sameLocation)
        XCTAssertEqual(try contents(source), "original")
    }
    func testSameLocationThroughFolderSymlink() throws {
        let source = try file("source/document.txt")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source.deletingLastPathComponent())
        XCTAssertEqual(FileOperationService.move([.init(url: source)], to: alias)[0].state, .sameLocation)
        XCTAssertEqual(try contents(source), "original")
    }
    func testDefaultConflictPreservesBothFiles() throws {
        let source = try file("a/name.txt", "source")
        let target = try file("b/name.txt", "existing")
        let result = FileOperationService.move([.init(url: source)], to: target.deletingLastPathComponent())
        XCTAssertEqual(result[0].state, .conflict)
        XCTAssertEqual(try contents(source), "source")
        XCTAssertEqual(try contents(target), "existing")
    }
    func testKeepBothRenamesAndMovesWithoutOverwriting() throws {
        let source = try file("a/name.txt", "source")
        let target = try file("b/name.txt", "existing")
        _ = try file("b/name (2).txt", "reserved")
        let result = FileOperationService.move([.init(url: source)], to: target.deletingLastPathComponent(), policy: .keepBoth)
        XCTAssertEqual(result[0].state, .moved)
        XCTAssertEqual(result[0].destination.lastPathComponent, "name (3).txt")
        XCTAssertEqual(try contents(target), "existing")
        XCTAssertEqual(try contents(result[0].destination), "source")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }
    func testDanglingSymlinkIsAConflict() throws {
        let source = try file("a/name.txt")
        let destination = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: destination.appendingPathComponent("name.txt").path, withDestinationPath: "/nonexistent/DropShelf-test")
        XCTAssertEqual(FileOperationService.move([.init(url: source)], to: destination)[0].state, .conflict)
        XCTAssertEqual(try contents(source), "original")
    }
    func testFailedMovePreservesSourceAndReportsFailure() throws {
        let source = try file("a/name.txt")
        let result = FileOperationService.move([.init(url: source)], to: root.appendingPathComponent("missing/folder"))
        XCTAssertEqual(result[0].state, .failed)
        XCTAssertFalse(result[0].removesFromShelf)
        XCTAssertEqual(try contents(source), "original")
        XCTAssertNotNil(result[0].detail)
    }
    func testFolderCannotMoveInsideItself() throws {
        let source = try file("folder/child/file.txt").deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertEqual(FileOperationService.move([.init(url: source)], to: source.appendingPathComponent("child"))[0].state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("child/file.txt").path))
    }
    func testManagedTemporaryMoveCopiesSoExportRemainsValid() throws {
        let source = try file("a/name.txt")
        let folder = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let result = FileOperationService.move([.init(url: source, isManagedTemporary: true)], to: folder)
        XCTAssertEqual(result[0].state, .copied)
        XCTAssertEqual(try contents(source), "original")
        XCTAssertEqual(try contents(result[0].destination), "original")
    }
    func testArchiveKeepsDuplicateNamesAndFoldersAndHiddenFiles() throws {
        let a = try file("a/same.txt", "first")
        let b = try file("b/same.txt", "second")
        let c = try file("c/same (2).txt", "third")
        let hidden = try file("folder/.hidden", "hidden")
        let store = TemporaryFileStore(root: root.appendingPathComponent("cache"))
        let archive = try FileOperationService.createArchive([a,b,c,hidden.deletingLastPathComponent()].map { .init(url: $0) }, store: store)
        let output = root.appendingPathComponent("unpacked")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.fileURL.path, output.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try contents(output.appendingPathComponent("same.txt")), "first")
        XCTAssertEqual(try contents(output.appendingPathComponent("same (2).txt")), "second")
        XCTAssertEqual(try contents(output.appendingPathComponent("same (2) (2).txt")), "third")
        XCTAssertEqual(try contents(output.appendingPathComponent("folder/.hidden")), "hidden")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: store.session.path).contains { $0.hasPrefix("job-") })
    }
    func testArchiveCopyFailureLeavesNoOutputOrWorkspace() throws {
        let a = try file("file.txt")
        let store = TemporaryFileStore(root: root.appendingPathComponent("cache"))
        XCTAssertThrowsError(try FileOperationService.createArchive([.init(url: a), .init(url: root.appendingPathComponent("missing.txt"))], store: store))
        XCTAssertEqual(try contents(a), "original")
        let children = try FileManager.default.contentsOfDirectory(atPath: store.session.path)
        XCTAssertFalse(children.contains { $0.hasPrefix("job-") || $0.hasPrefix("asset-") })
    }
    func testConcurrentArchivesNeverShareOutputPaths() throws {
        let source = try file("same.txt")
        let store = TemporaryFileStore(root: root.appendingPathComponent("cache"))
        let queue = DispatchQueue(label: "archive-test", attributes: .concurrent)
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [TemporaryResource] = []
        var failures: [Error] = []
        for _ in 0..<3 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    let archive = try FileOperationService.createArchive([.init(url: source)], store: store)
                    lock.lock(); results.append(archive); lock.unlock()
                } catch { lock.lock(); failures.append(error); lock.unlock() }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 15), .success)
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(Set(results.map { $0.fileURL }).count, 3)
        XCTAssertTrue(results.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
    }
    func testCrossVolumeCopyPreservesSource() throws {
        guard let path = ProcessInfo.processInfo.environment["DROPSHELF_TEST_VOLUME"] else {
            throw XCTSkip("使用 scripts/test_cross_volume.sh 创建专用 APFS 测试卷")
        }
        let source = try file("source.txt", "cross-volume")
        let destination = URL(fileURLWithPath: path).appendingPathComponent("DropShelfTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: destination) }
        let sourceVolume = try FileManager.default.attributesOfFileSystem(forPath: root.path)[.systemNumber] as? NSNumber
        let targetVolume = try FileManager.default.attributesOfFileSystem(forPath: destination.path)[.systemNumber] as? NSNumber
        XCTAssertNotEqual(sourceVolume, targetVolume)
        let result = FileOperationService.move([.init(url: source)], to: destination)
        XCTAssertEqual(result[0].state, .copied)
        XCTAssertEqual(try contents(source), "cross-volume")
        XCTAssertEqual(try contents(result[0].destination), "cross-volume")
    }

}
