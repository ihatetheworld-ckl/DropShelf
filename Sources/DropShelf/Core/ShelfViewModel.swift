import AppKit
import Combine
import Foundation

public final class ShelfViewModel: ObservableObject, Identifiable {
    public let id: UUID = UUID()
    public let indexNumber: Int

    @Published public var items: [ShelfItem] = []
    @Published public var selectedItemIDs: Set<UUID> = []
    @Published public var isDropTargeted: Bool = false
    @Published public var isPinned: Bool = false
    @Published public var isCollapsed: Bool = false
    @Published public var isGridView: Bool = false
    @Published public var statusMessage: String? = nil

    public var onRequestClose: (() -> Void)?
    public var onRequestResize: ((Bool) -> Void)?
    public var onRequestQuickLook: (() -> Void)?

    private var autoCloseTimer: Timer?

    public init(indexNumber: Int, initialItems: [ShelfItem] = []) {
        self.indexNumber = indexNumber
        self.items = initialItems
        if initialItems.isEmpty {
            scheduleEmptyShelfTimeout()
        }
    }

    public var totalSizeFormatted: String {
        let total = items.reduce(Int64(0)) { $0 + $1.fileSize }
        guard total > 0 else { return "\(items.count) 项" }
        let sizeStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return "\(items.count) 项 · \(sizeStr)"
    }

    public var effectiveDragItems: [ShelfItem] {
        if selectedItemIDs.isEmpty {
            return items
        }
        let selected = items.filter { selectedItemIDs.contains($0.id) }
        return selected.isEmpty ? items : selected
    }

    public func addItems(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        cancelEmptyShelfTimeout()

        let existingPaths = Set(items.map { $0.fileURL.standardizedFileURL.path })
        var addedCount = 0
        for item in newItems {
            let path = item.fileURL.standardizedFileURL.path
            if !existingPaths.contains(path) {
                items.append(item)
                addedCount += 1
            }
        }

        if addedCount > 0 {
            if items.count > 1 && items.count <= 9 {
                isGridView = true
            }
            playFeedbackSound(named: "Pop")
        }
    }

    public func addFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let extracted = PasteboardExtractor.extractItems(from: pasteboard)
        guard !extracted.isEmpty else { return false }
        addItems(extracted)
        return true
    }

    public func removeItems(withIDs ids: Set<UUID>) {
        let removed = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        selectedItemIDs.subtract(ids)

        // Delay cleanup of temporary files (like generated ZIPs or web images) so Finder/apps finish asynchronous copy
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            for item in removed {
                item.cleanupIfNeeded()
            }
        }

        if items.isEmpty && AppSettings.shared.autoCloseWhenEmptied && !isPinned {
            onRequestClose?()
        }
    }

    public func clearAll() {
        for item in items {
            item.cleanupIfNeeded()
        }
        items.removeAll()
        selectedItemIDs.removeAll()
        if AppSettings.shared.autoCloseWhenEmptied && !isPinned {
            onRequestClose?()
        }
    }

    public func toggleSelection(for item: ShelfItem, exclusive: Bool) {
        if exclusive {
            if selectedItemIDs.count == 1 && selectedItemIDs.contains(item.id) {
                selectedItemIDs.removeAll()
            } else {
                selectedItemIDs = [item.id]
            }
        } else {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
            }
        }
    }

    public func selectAll() {
        selectedItemIDs = Set(items.map { $0.id })
    }

    public func toggleCollapsed() {
        isCollapsed.toggle()
        onRequestResize?(isCollapsed)
    }

    // MARK: - Actions (ZIP, Copy, Finder, AirDrop/Share)

    public func createZipArchive() {
        let targets = effectiveDragItems
        guard !targets.isEmpty else { return }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DropShelfArchives", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let zipName = targets.count == 1
            ? "\(targets[0].fileURL.deletingPathExtension().lastPathComponent).zip"
            : "DropShelf-\(formatter.string(from: Date())).zip"

        let zipURL = tempDir.appendingPathComponent(zipName)
        try? FileManager.default.removeItem(at: zipURL)

        showToast("正在打包 ZIP...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let stageDir = tempDir.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

            for item in targets {
                let dest = stageDir.appendingPathComponent(item.fileURL.lastPathComponent)
                try? FileManager.default.copyItem(at: item.fileURL, to: dest)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", stageDir.path, zipURL.path]

            do {
                try process.run()
                process.waitUntilExit()
                try? FileManager.default.removeItem(at: stageDir)

                if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: zipURL.path) {
                    let zipShelfItem = ShelfItem(fileURL: zipURL, displayName: zipName, isTemporaryFile: true)
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.items = [zipShelfItem]
                        self.selectedItemIDs = [zipShelfItem.id]
                        self.showToast("已打包为 \(zipName)")
                        self.playFeedbackSound(named: "Glass")
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.showToast("打包失败")
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: stageDir)
                DispatchQueue.main.async {
                    self?.showToast("打包出错")
                }
            }
        }
    }

    public func copyItemsToClipboard() {
        let targets = effectiveDragItems
        guard !targets.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(targets.map { $0.fileURL as NSURL })
        showToast("已复制 \(targets.count) 个文件到剪贴板")
    }

    public func copyPathsToClipboard() {
        let targets = effectiveDragItems
        guard !targets.isEmpty else { return }
        let paths = targets.map { $0.fileURL.path }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths, forType: .string)
        showToast("已复制文件路径")
    }

    public func revealInFinder() {
        let targets = effectiveDragItems
        guard !targets.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(targets.map { $0.fileURL })
    }

    public func moveToDestinationFolder() {
        let targets = effectiveDragItems
        guard !targets.isEmpty else { return }

        let openPanel = NSOpenPanel()
        openPanel.title = "选择目标文件夹"
        openPanel.prompt = "移动到此处"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false

        if openPanel.runModal() == .OK, let destFolder = openPanel.url {
            var movedIDs = Set<UUID>()
            for item in targets {
                let targetURL = destFolder.appendingPathComponent(item.fileURL.lastPathComponent)
                do {
                    if FileManager.default.fileExists(atPath: targetURL.path) {
                        try FileManager.default.removeItem(at: targetURL)
                    }
                    try FileManager.default.moveItem(at: item.fileURL, to: targetURL)
                    movedIDs.insert(item.id)
                } catch {
                    // Fallback to copy if across volumes or permission issue
                    if (try? FileManager.default.copyItem(at: item.fileURL, to: targetURL)) != nil {
                        movedIDs.insert(item.id)
                    }
                }
            }
            removeItems(withIDs: movedIDs)
            showToast("已移动 \(movedIDs.count) 个文件")
        }
    }

    public func showToast(_ text: String) {
        statusMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.statusMessage == text {
                self?.statusMessage = nil
            }
        }
    }

    public func scheduleEmptyShelfTimeout() {
        cancelEmptyShelfTimeout()
        let timeout = AppSettings.shared.autoCollapseEmptyShelfSeconds
        guard timeout > 0 else { return }
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.items.isEmpty && !self.isPinned && !self.isDropTargeted {
                self.onRequestClose?()
            }
        }
    }

    public func cancelEmptyShelfTimeout() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
    }

    private func playFeedbackSound(named name: String) {
        guard AppSettings.shared.soundEffectsEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
