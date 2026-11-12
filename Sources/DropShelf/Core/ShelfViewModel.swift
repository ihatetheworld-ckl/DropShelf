import AppKit
import Combine
import Foundation

/// All shelf state is mutated on the main thread. Workers receive immutable URL snapshots.
public final class ShelfViewModel: ObservableObject, Identifiable {
    public let id: UUID = UUID()
    public let indexNumber: Int
    @Published public private(set) var items: [ShelfItem] = []
    @Published public var selectedItemIDs: Set<UUID> = []
    @Published public var isDropTargeted = false
    @Published public var isPinned = false {
        didSet {
            if isPinned { cancelEmptyShelfTimeout() }
            else if items.isEmpty { scheduleEmptyShelfTimeout() }
        }
    }
    @Published public var isCollapsed = false
    @Published public var isGridView = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var isClosed = false
    @Published public var statusMessage: String?
    public private(set) var lastOperationReport: String?
    public var onRequestClose: (() -> Void)?
    public var onRequestResize: ((Bool) -> Void)?
    public var onRequestQuickLook: (() -> Void)?
    public var onRequestOperationReport: ((String) -> Void)?
    private var pendingImports = 0
    public var isImporting: Bool { pendingImports > 0 }
    private var autoCloseTimer: Timer?
    private var toastGeneration = UUID()
    // Injection points exercise races and failures without altering the real filesystem.
    var archiveOperation: ([FileOperationInput]) throws -> TemporaryResource = { try FileOperationService.createArchive($0) }
    var moveOperation: ([FileOperationInput], URL, FileConflictPolicy) -> [FileMoveResult] = { FileOperationService.move($0, to: $1, policy: $2) }

    public init(indexNumber: Int, initialItems: [ShelfItem] = []) {
        self.indexNumber = indexNumber
        self.items = initialItems
        if initialItems.isEmpty { scheduleEmptyShelfTimeout() }
    }
    deinit { autoCloseTimer?.invalidate() }

    public var totalSizeFormatted: String {
        let total = items.reduce(Int64(0)) { $0 + $1.fileSize }
        guard total > 0 else { return "\(items.count) 项" }
        return "\(items.count) 项 · " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    public var effectiveDragItems: [ShelfItem] {
        let selected = items.filter { selectedItemIDs.contains($0.id) }
        return selected.isEmpty ? items : selected
    }
    public func addItems(_ newItems: [ShelfItem]) {
        guard !isClosed, !newItems.isEmpty else { return }
        cancelEmptyShelfTimeout()
        var existingPaths = Set(items.map { $0.fileURL.standardizedFileURL.path })
        var addedCount = 0
        for item in newItems where existingPaths.insert(item.fileURL.standardizedFileURL.path).inserted {
            items.append(item)
            addedCount += 1
        }
        if addedCount > 0 {
            if items.count > 1 && items.count <= 9 { isGridView = true }
            playFeedbackSound(named: "Pop")
        }
    }
    public func addFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        guard !isClosed else { return false }
        pendingImports += 1
        cancelEmptyShelfTimeout()
        let accepted = PasteboardExtractor.extractItemsAsync(from: pasteboard) { [weak self] extracted, errors in
            guard let self = self else { return }
            self.pendingImports -= 1
            guard !self.isClosed else { return }
            self.addItems(extracted)
            if !errors.isEmpty { self.report("已添加 \(extracted.count) 项，\(errors.count) 项失败。\n" + errors.joined(separator: "\n")) }
            if self.items.isEmpty { self.scheduleEmptyShelfTimeout() }
        }
        if !accepted {
            pendingImports -= 1
            showToast("无法读取拖入或粘贴的内容")
            scheduleEmptyShelfTimeout()
        }
        return accepted
    }
    public func removeItems(withIDs ids: Set<UUID>) {
        guard !isClosed, !isBusy else { return }
        items.removeAll { ids.contains($0.id) }
        selectedItemIDs.subtract(ids)
        closeIfEmptied()
    }
    public func completeDrag(withIDs ids: Set<UUID>, operation: NSDragOperation) {
        guard !isClosed, !isBusy, items.contains(where: { ids.contains($0.id) }) else { return }
        if operation == .move {
            // A receiver can accept a move before finishing it, or skip individual
            // files. Keep every original URL that still exists for recovery. A
            // vanished source reference must go even when automatic removal is off.
            let movedIDs = Set(items.filter {
                ids.contains($0.id) && FileOperationService.sourceIsMissing($0.fileURL)
            }.map { $0.id })
            removeItems(withIDs: movedIDs)
            if items.contains(where: { ids.contains($0.id) }) {
                showToast("目标已接收移动请求；仍在原位置的项目已保留")
            }
        } else if operation == .copy && AppSettings.shared.removeItemsAfterDragOut {
            removeItems(withIDs: ids)
        }
    }
    public func clearAll() {
        guard !isClosed, !isBusy else { return }
        items.removeAll()
        selectedItemIDs.removeAll()
        closeIfEmptied()
    }
    private func closeIfEmptied() {
        if items.isEmpty && AppSettings.shared.autoCloseWhenEmptied && !isPinned { onRequestClose?() }
    }
    @discardableResult
    public func beginClosing() -> Bool {
        guard !isClosed else { return false }
        guard !isBusy else { showToast("文件操作进行中，请完成后关闭"); return false }
        isClosed = true
        cancelEmptyShelfTimeout()
        items.removeAll()
        selectedItemIDs.removeAll()
        return true
    }
    public func toggleSelection(for item: ShelfItem, exclusive: Bool) {
        if exclusive {
            selectedItemIDs = selectedItemIDs == [item.id] ? [] : [item.id]
        } else if selectedItemIDs.contains(item.id) { selectedItemIDs.remove(item.id) }
        else { selectedItemIDs.insert(item.id) }
    }
    public func selectAll() { selectedItemIDs = Set(items.map { $0.id }) }
    public func toggleCollapsed() {
        guard !isClosed else { return }
        isCollapsed.toggle()
        onRequestResize?(isCollapsed)
    }
    static func toggleAllCollapsed(_ shelves: [ShelfViewModel]) {
        let active = shelves.filter { !$0.isClosed }
        let collapse = active.contains { !$0.isCollapsed }
        for shelf in active where shelf.isCollapsed != collapse { shelf.toggleCollapsed() }
    }

    public func createZipArchive() {
        let targets = effectiveDragItems
        guard !isBusy, !isClosed, !targets.isEmpty else { return }
        isBusy = true
        cancelEmptyShelfTimeout()
        statusMessage = "正在打包 ZIP…（可继续拖入）"
        let operation = archiveOperation
        let inputs = targets.map(FileOperationInput.init)
        let ids = Set(targets.map { $0.id })
        DispatchQueue.global(qos: .userInitiated).async { [self, targets] in
            let result = Result { try operation(inputs) }
            DispatchQueue.main.async { [self, targets] in
                // Strong snapshot leases keep temporary inputs alive until completion.
                _ = targets
                isBusy = false
                switch result {
                case .success(let resource):
                    guard !isClosed, ids.isSubset(of: Set(items.map { $0.id })) else { return }
                    let zipItem = ShelfItem(resource: resource)
                    items.removeAll { ids.contains($0.id) }
                    items.append(zipItem)
                    selectedItemIDs.subtract(ids)
                    selectedItemIDs.insert(zipItem.id)
                    showToast("已打包 \(targets.count) 项；其余项目已保留")
                    playFeedbackSound(named: "Glass")
                case .failure(let error):
                    report("打包失败，原项目已保留。\n" + error.localizedDescription)
                }
            }
        }
    }
    @discardableResult
    public func prepareForExternalUse(_ targets: [ShelfItem]) -> Bool {
        guard targets.allSatisfy({ $0.preserveForExternalUse() }) else {
            showToast("文件不存在或无法保留临时文件，操作未完成")
            return false
        }
        return true
    }
    public func copyItemsToClipboard(_ pasteboard: NSPasteboard = .general) {
        let targets = effectiveDragItems
        guard !targets.isEmpty, prepareForExternalUse(targets) else { return }
        pasteboard.clearContents()
        showToast(pasteboard.writeObjects(targets.map { $0.fileURL as NSURL })
                  ? "已复制 \(targets.count) 个文件到剪贴板" : "复制失败，原项目已保留")
    }
    public func copyPathsToClipboard() {
        let targets = effectiveDragItems
        guard !targets.isEmpty, prepareForExternalUse(targets) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        showToast(pb.setString(targets.map { $0.fileURL.path }.joined(separator: "\n"), forType: .string)
                  ? "已复制文件路径" : "复制路径失败")
    }
    public func openItems(_ targets: [ShelfItem]) {
        guard prepareForExternalUse(targets) else { return }
        for item in targets { NSWorkspace.shared.open(item.fileURL) }
    }
    public func revealInFinder() {
        let targets = effectiveDragItems
        guard prepareForExternalUse(targets) else { return }
        NSWorkspace.shared.activateFileViewerSelecting(targets.map { $0.fileURL })
    }
    public func moveToDestinationFolder() {
        guard !isBusy, !isClosed, !effectiveDragItems.isEmpty else { return }
        let targets = effectiveDragItems
        let panel = NSOpenPanel()
        panel.title = "选择目标文件夹"
        panel.prompt = "移动到此处"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self = self, !self.isClosed, response == .OK, let folder = panel.url else { return }
            let alert = NSAlert()
            alert.messageText = "目标存在同名文件时如何处理？"
            alert.informativeText = "默认跳过同名项目。也可自动重命名以同时保留；不会覆盖已有文件。临时文件与跨磁盘项目将安全复制到目标并保留源文件，保证已导出的链接继续有效。"
            alert.addButton(withTitle: "保留已有（跳过）")
            alert.addButton(withTitle: "同时保留（重命名）")
            alert.addButton(withTitle: "取消")
            let choice = alert.runModal()
            guard choice != .alertThirdButtonReturn else { return }
            self.moveItems(targets, to: folder, policy: choice == .alertSecondButtonReturn ? .keepBoth : .skip)
        }
    }
    func moveItems(_ targets: [ShelfItem], to folder: URL, policy: FileConflictPolicy = .skip) {
        guard !isBusy, !isClosed, !targets.isEmpty else { return }
        guard Set(targets.map { $0.id }).isSubset(of: Set(items.map { $0.id })) else {
            showToast("架子内容已变化，请重新选择移动项目")
            return
        }
        isBusy = true
        cancelEmptyShelfTimeout()
        statusMessage = "正在处理文件…"
        let operation = moveOperation
        let inputs = targets.map(FileOperationInput.init)
        DispatchQueue.global(qos: .userInitiated).async { [self, targets] in
            let results = operation(inputs, folder, policy)
            DispatchQueue.main.async { [self, targets] in
                _ = targets
                isBusy = false
                let moved = results.filter { $0.state == .moved }.count
                let copied = results.filter { $0.state == .copied }.count
                let same = results.filter { $0.state == .sameLocation }.count
                let conflicts = results.filter { $0.state == .conflict }.count
                let failures = results.filter { $0.state == .failed }.count
                let summary = "移动 \(moved)，复制 \(copied)，原位跳过 \(same)，同名跳过 \(conflicts)，失败 \(failures)"
                let details = results.map { "\($0.source.path) → \($0.destination.path)\n\($0.state.rawValue)：\($0.detail ?? "")" }.joined(separator: "\n\n")
                report(summary + "\n\n" + details)
                removeItems(withIDs: Set(results.filter { $0.removesFromShelf }.map { $0.id }))
            }
        }
    }
    private func report(_ text: String) {
        lastOperationReport = text
        showToast(String(text.split(separator: "\n").first ?? ""))
        onRequestOperationReport?(text)
    }
    public func showToast(_ text: String) {
        let generation = UUID()
        toastGeneration = generation
        statusMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, self.toastGeneration == generation, !self.isBusy else { return }
            self.statusMessage = nil
        }
    }
    public func scheduleEmptyShelfTimeout() {
        cancelEmptyShelfTimeout()
        guard !isClosed, !isPinned, !isBusy, !isImporting, items.isEmpty else { return }
        let timeout = AppSettings.shared.autoCollapseEmptyShelfSeconds
        guard timeout > 0 else { return }
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self, !self.isClosed, self.items.isEmpty, !self.isPinned,
                  !self.isDropTargeted, !self.isBusy, !self.isImporting else { return }
            self.isCollapsed = true
            self.onRequestResize?(true)
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
