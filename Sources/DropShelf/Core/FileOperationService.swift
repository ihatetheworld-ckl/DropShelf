import Foundation
import Darwin

struct FileOperationInput {
    let id: UUID
    let url: URL
    let isManagedTemporary: Bool
    init(_ item: ShelfItem) {
        id = item.id
        url = item.fileURL
        isManagedTemporary = item.isTemporaryFile
    }
    init(id: UUID = UUID(), url: URL, isManagedTemporary: Bool = false) {
        self.id = id; self.url = url; self.isManagedTemporary = isManagedTemporary
    }
}

enum FileConflictPolicy { case skip, keepBoth }
enum FileMoveState: String { case moved = "已移动", copied = "已复制（源保留）", sameLocation = "原位跳过", conflict = "同名跳过", failed = "失败" }
struct FileMoveResult {
    let id: UUID
    let source: URL
    let destination: URL
    let state: FileMoveState
    let detail: String?
    var removesFromShelf: Bool { state == .moved || state == .copied }
}

enum FileOperationService {
    static func move(_ inputs: [FileOperationInput], to folder: URL,
                     policy: FileConflictPolicy = .skip) -> [FileMoveResult] {
        inputs.map { input in
            let source = input.url
            var destination = folder.appendingPathComponent(source.lastPathComponent)
            func result(_ state: FileMoveState, _ detail: String? = nil) -> FileMoveResult {
                FileMoveResult(id: input.id, source: source, destination: destination, state: state, detail: detail)
            }
            let canonicalSource = source.resolvingSymlinksInPath().standardizedFileURL
            let canonicalDestination = destination.resolvingSymlinksInPath().standardizedFileURL
            if canonicalSource == canonicalDestination || sameInode(source, destination) { return result(.sameLocation) }
            let resolvedFolder = folder.resolvingSymlinksInPath().standardizedFileURL.path
            if resolvedFolder.hasPrefix(canonicalSource.path + "/") {
                return result(.failed, "不能将文件夹移动到自身内部")
            }
            if exists(destination) {
                guard policy == .keepBoth else { return result(.conflict, "已保留目标同名文件") }
                destination = availableURL(in: folder, name: source.lastPathComponent)
            }
            do {
                // An exported temporary URL must remain valid for clipboard/external readers.
                if input.isManagedTemporary {
                    try publishCopy(source, to: destination)
                    return result(.copied)
                }
                if renameExclusive(source, destination) == 0 { return result(.moved) }
                let errorCode = errno
                guard errorCode == EXDEV else { throw posixError(errorCode) }
                // A directory can change during a long cross-volume copy. Never delete
                // that source tree after copying a snapshot of it.
                try publishCopy(source, to: destination)
                return result(.copied, "跨磁盘安全复制，源文件已保留")
            } catch {
                return result(.failed, error.localizedDescription)
            }
        }
    }

    static func createArchive(_ inputs: [FileOperationInput], store: TemporaryFileStore = .shared) throws -> TemporaryResource {
        guard !inputs.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        let fm = FileManager.default
        let workspace = try store.createWorkspace()
        defer { try? fm.removeItem(at: workspace) }
        let stage = workspace.appendingPathComponent("contents", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        var names = Set<String>()
        for input in inputs {
            let name = uniqueName(input.url.lastPathComponent, reserved: &names)
            do { try fm.copyItem(at: input.url, to: stage.appendingPathComponent(name)) }
            catch { throw NSError(domain: "DropShelf.Archive", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "无法打包 \(input.url.lastPathComponent)：\(error.localizedDescription)"]) }
        }
        let stem = inputs.count == 1 ? inputs[0].url.deletingPathExtension().lastPathComponent : "DropShelf"
        let output = try store.createResource(filename: (stem.hasPrefix(".") ? "Archive" : stem) + ".zip")
        let log = workspace.appendingPathComponent("ditto.log")
        guard fm.createFile(atPath: log.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", stage.path, output.fileURL.path]
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              (try output.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
            throw NSError(domain: "DropShelf.Archive", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "系统 ZIP 工具失败（\(process.terminationStatus)），原项目已保留"])
        }
        return output
    }

    private static func publishCopy(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".DropShelf-move-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: source, to: staging)
        guard renameExclusive(staging, destination) == 0 else { throw posixError(errno) }
    }

    private static func sameInode(_ a: URL, _ b: URL) -> Bool {
        var left = stat(), right = stat()
        return lstat(a.path, &left) == 0 && lstat(b.path, &right) == 0 && left.st_dev == right.st_dev && left.st_ino == right.st_ino
    }
    private static func renameExclusive(_ a: URL, _ b: URL) -> Int32 {
        renamex_np(a.path, b.path, UInt32(RENAME_EXCL))
    }
    private static func posixError(_ code: Int32) -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 // also recognize dangling symlinks
    }
    private static func availableURL(in folder: URL, name: String) -> URL {
        var names = Set<String>()
        var candidate = name
        while exists(folder.appendingPathComponent(candidate)) {
            candidate = uniqueName(name, reserved: &names)
        }
        return folder.appendingPathComponent(candidate)
    }
    private static func uniqueName(_ name: String, reserved: inout Set<String>) -> String {
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var candidate = name
        var index = 2
        while !reserved.insert(candidate.precomposedStringWithCanonicalMapping.lowercased()).inserted {
            candidate = stem + " (\(index))" + (ext.isEmpty ? "" : "." + ext)
            index += 1
        }
        return candidate
    }
}
