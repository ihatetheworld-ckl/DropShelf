import Foundation
import Darwin

/// A shared lease. Shelves and in-flight operations retain this object. Exported files
/// are deliberately durable: other applications cannot acknowledge finishing a URL.
final class TemporaryResource {
    let fileURL: URL
    let directory: URL
    private let lock = NSLock()
    private var exported: Bool

    init(fileURL: URL, directory: URL) {
        self.fileURL = fileURL
        self.directory = directory
        self.exported = FileManager.default.fileExists(atPath: directory.appendingPathComponent(".exported").path)
    }

    func preserveForExternalUse() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !exported else { return }
        try Data("DropShelf export v1".utf8).write(to: directory.appendingPathComponent(".exported"), options: .atomic)
        exported = true
    }

    deinit {
        if !exported { try? FileManager.default.removeItem(at: directory) }
    }
}

private final class WeakResource {
    weak var value: TemporaryResource?
    init(_ value: TemporaryResource) { self.value = value }
}

final class TemporaryFileStore {
    static let shared = TemporaryFileStore()
    static let marker = "DropShelf temporary session v1"
    let root: URL
    let session: URL
    private var sessionLock: Int32 = -1
    private let lock = NSLock()
    private var resources: [String: WeakResource] = [:]

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.local.dropshelf/TemporaryFiles-v1", isDirectory: true)) {
        self.root = root
        self.session = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // A failed store initialization is surfaced by createResource/createWorkspace.
        do {
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try Data(Self.marker.utf8).write(to: session.appendingPathComponent(".owner"), options: .atomic)
            sessionLock = open(session.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard sessionLock >= 0, flock(sessionLock, LOCK_EX | LOCK_NB) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            sweepAbandonedSessions()
        } catch {
            if sessionLock >= 0 { close(sessionLock); sessionLock = -1 }
            // Leave only our marked directory for the next successful startup sweep.
        }
    }

    deinit {
        if sessionLock >= 0 { close(sessionLock) }
    }

    func createResource(filename: String) throws -> TemporaryResource {
        guard sessionLock >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        let directory = session.appendingPathComponent("asset-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let safeName = URL(fileURLWithPath: filename).lastPathComponent
        guard !safeName.isEmpty, safeName != ".", safeName != "..", !safeName.hasPrefix(".") else {
            try? FileManager.default.removeItem(at: directory)
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let resource = TemporaryResource(fileURL: directory.appendingPathComponent(safeName), directory: directory)
        try Data(safeName.utf8).write(to: directory.appendingPathComponent(".asset"), options: .atomic)
        lock.lock()
        resources[resource.fileURL.path] = WeakResource(resource)
        lock.unlock()
        return resource
    }

    func createWorkspace() throws -> URL {
        guard sessionLock >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        let directory = session.appendingPathComponent("job-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    /// Resolve only exact files in our marked store, never arbitrary user paths.
    func resource(for url: URL) -> TemporaryResource? {
        let url = url.standardizedFileURL
        lock.lock()
        defer { lock.unlock() }
        if let existing = resources[url.path]?.value { return existing }
        let asset = url.deletingLastPathComponent()
        let owner = asset.deletingLastPathComponent()
        guard owner.deletingLastPathComponent() == root.standardizedFileURL,
              UUID(uuidString: owner.lastPathComponent) != nil,
              isRealDirectory(owner), isRealDirectory(asset),
              asset.lastPathComponent.hasPrefix("asset-"),
              (try? String(contentsOf: owner.appendingPathComponent(".owner"), encoding: .utf8)) == Self.marker,
              (try? String(contentsOf: asset.appendingPathComponent(".asset"), encoding: .utf8)) == url.lastPathComponent,
              FileManager.default.fileExists(atPath: asset.appendingPathComponent(".exported").path) else { return nil }
        let resource = TemporaryResource(fileURL: url, directory: asset)
        resources[url.path] = WeakResource(resource)
        return resource
    }

    /// Locks protect concurrent instances; exported assets survive restarts. No legacy
    /// /tmp directory is adopted or deleted because its ownership is unprovable.
    func sweepAbandonedSessions() {
        let fm = FileManager.default
        for owner in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            guard owner != session, UUID(uuidString: owner.lastPathComponent) != nil,
                  isRealDirectory(owner),
                  (try? String(contentsOf: owner.appendingPathComponent(".owner"), encoding: .utf8)) == Self.marker else { continue }
            let fd = open(owner.appendingPathComponent(".lock").path, O_RDWR | O_NOFOLLOW)
            guard fd >= 0 else { continue }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); continue }
            for child in (try? fm.contentsOfDirectory(at: owner, includingPropertiesForKeys: nil)) ?? [] {
                guard isRealDirectory(child) else { continue }
                let name = child.lastPathComponent
                let assetID = name.hasPrefix("asset-") ? UUID(uuidString: String(name.dropFirst(6))) : nil
                let jobID = name.hasPrefix("job-") ? UUID(uuidString: String(name.dropFirst(4))) : nil
                if jobID != nil || (assetID != nil && !fm.fileExists(atPath: child.appendingPathComponent(".exported").path)) {
                    try? fm.removeItem(at: child)
                }
            }
            let remaining = (try? fm.contentsOfDirectory(atPath: owner.path)) ?? []
            if Set(remaining).isSubset(of: [".owner", ".lock"]) { try? fm.removeItem(at: owner) }
            close(fd)
        }
    }

    private func isRealDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }
}
