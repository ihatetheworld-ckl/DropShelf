import AppKit
import SwiftUI

public struct ShelfContentView: View {
    @ObservedObject public var viewModel: ShelfViewModel

    public init(viewModel: ShelfViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: viewModel.isCollapsed ? 22 : 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: viewModel.isCollapsed ? 22 : 16, style: .continuous)
                        .strokeBorder(
                            viewModel.isDropTargeted
                                ? Color.accentColor.opacity(0.95)
                                : Color.white.opacity(0.18),
                            lineWidth: viewModel.isDropTargeted ? 2.5 : 1.0
                        )
                )

            if viewModel.isCollapsed {
                collapsedPillView
            } else {
                expandedShelfView
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: viewModel.isCollapsed)
        .animation(.easeInOut(duration: 0.16), value: viewModel.isDropTargeted)
        .animation(.easeInOut(duration: 0.18), value: viewModel.items.count)
    }

    // MARK: - Collapsed Pill View
    private var collapsedPillView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.22))
                    .frame(width: 28, height: 28)
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .overlay {
                if !viewModel.items.isEmpty {
                    DragSourceOverlay(
                        itemsProvider: { viewModel.effectiveDragItems },
                        onDragCompleted: { draggedIDs, _ in
                            if AppSettings.shared.removeItemsAfterDragOut {
                                viewModel.removeItems(withIDs: draggedIDs)
                            }
                        }
                    )
                }
            }
            .help("按住图标可直接拖出文件")

            ZStack {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("架子 #\(viewModel.indexNumber)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("\(viewModel.items.count) 个文件")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 4)
                }
                WindowDragHandleOverlay(onDoubleClick: {
                    viewModel.toggleCollapsed()
                })
            }

            Button {
                viewModel.toggleCollapsed()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("展开文件架")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Expanded Shelf View
    private var expandedShelfView: some View {
        VStack(spacing: 0) {
            topHeaderBar
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if viewModel.items.isEmpty {
                emptyDropZoneView
                    .padding(10)
            } else {
                mainItemsArea
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)

                bottomActionFooter
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .padding(.top, 4)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = viewModel.statusMessage {
                Text(toast)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.78))
                    .clipShape(Capsule())
                    .padding(.bottom, 34)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    // MARK: - Top Header Bar
    private var topHeaderBar: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.onRequestClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭架子")

            Button {
                viewModel.toggleCollapsed()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("收起为迷你胶囊")

            Button {
                viewModel.isPinned.toggle()
                if viewModel.isPinned {
                    viewModel.cancelEmptyShelfTimeout()
                }
            } label: {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(viewModel.isPinned ? .accentColor : .secondary)
                    .frame(width: 20, height: 20)
                    .background(viewModel.isPinned ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(viewModel.isPinned ? "已固定（清空后不自动关闭）" : "固定架子")

            ZStack {
                HStack(spacing: 4) {
                    Spacer(minLength: 2)
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(viewModel.items.isEmpty ? "DropShelf #\(viewModel.indexNumber)" : viewModel.totalSizeFormatted)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                }
                WindowDragHandleOverlay(onDoubleClick: {
                    viewModel.toggleCollapsed()
                })
            }
            .frame(maxWidth: .infinity, minHeight: 22)
            .help("按住此处可拖动架子窗口（双击收起）")

            if viewModel.items.count > 1 {
                Button {
                    viewModel.isGridView.toggle()
                } label: {
                    Image(systemName: viewModel.isGridView ? "square.stack.3d.up.fill" : "square.grid.2x2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .help(viewModel.isGridView ? "切换为堆叠视图" : "切换为网格视图")
            }

            Menu {
                Button("快速预览 (Space)") {
                    viewModel.onRequestQuickLook?()
                }
                .disabled(viewModel.items.isEmpty)

                Divider()

                Button("打包为 ZIP 压缩包") {
                    viewModel.createZipArchive()
                }
                .disabled(viewModel.items.isEmpty)

                Button("复制文件到剪贴板 (⌘C)") {
                    viewModel.copyItemsToClipboard()
                }
                .disabled(viewModel.items.isEmpty)

                Button("复制文件路径") {
                    viewModel.copyPathsToClipboard()
                }
                .disabled(viewModel.items.isEmpty)

                Button("在 Finder 中显示") {
                    viewModel.revealInFinder()
                }
                .disabled(viewModel.items.isEmpty)

                Button("移动到指定文件夹...") {
                    viewModel.moveToDestinationFolder()
                }
                .disabled(viewModel.items.isEmpty)

                Divider()

                Button("从剪贴板粘贴内容 (⌘V)") {
                    _ = viewModel.addFromPasteboard(.general)
                }

                if !viewModel.items.isEmpty {
                    Divider()
                    Button("清空架子", role: .destructive) {
                        viewModel.clearAll()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Empty Drop Zone
    private var emptyDropZoneView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .foregroundColor(viewModel.isDropTargeted ? .accentColor : Color.secondary.opacity(0.35))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(viewModel.isDropTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                )
                .overlay {
                    WindowDragHandleOverlay()
                }

            VStack(spacing: 8) {
                Image(systemName: viewModel.isDropTargeted ? "arrow.down.doc.fill" : "tray.and.arrow.down")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(viewModel.isDropTargeted ? .accentColor : .secondary)

                Text(viewModel.isDropTargeted ? "松开鼠标放入架子" : "拖入文件、图片、文本或链接")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.85))
                    .multilineTextAlignment(.center)

                Button {
                    _ = viewModel.addFromPasteboard(.general)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10))
                        Text("粘贴剪贴板")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main Items Area (Stack vs Grid)
    private var mainItemsArea: some View {
        Group {
            if viewModel.items.count == 1 || !viewModel.isGridView {
                stackedShowcaseView
            } else {
                gridItemsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stackedShowcaseView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    WindowDragHandleOverlay()
                }

            VStack(spacing: 6) {
                ZStack {
                    ForEach(Array(viewModel.items.prefix(3).enumerated().reversed()), id: \.element.id) { idx, item in
                        Image(nsImage: item.thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 82, height: 82)
                            .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
                            .rotationEffect(.degrees(idx == 0 ? 0 : (idx == 1 ? -6 : 6)))
                            .offset(x: CGFloat(idx) * 3, y: CGFloat(idx) * -3)
                    }

                    if viewModel.items.count > 1 {
                        Text("\(viewModel.items.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .offset(x: 34, y: -32)
                    }

                    DragSourceOverlay(
                        itemsProvider: { viewModel.effectiveDragItems },
                        onSingleClick: { _ in
                            viewModel.selectAll()
                        },
                        onDoubleClick: {
                            if let first = viewModel.items.first {
                                NSWorkspace.shared.open(first.fileURL)
                            }
                        },
                        onRightClickMenu: {
                            buildContextMenu(for: nil)
                        },
                        onDragCompleted: { draggedIDs, _ in
                            if AppSettings.shared.removeItemsAfterDragOut {
                                viewModel.removeItems(withIDs: draggedIDs)
                            }
                        }
                    )
                }
                .frame(width: 110, height: 92)
                .help("按住文件图标拖出文件 · 双击打开")

                ZStack {
                    VStack(spacing: 3) {
                        if let first = viewModel.items.first {
                            Text(viewModel.items.count == 1 ? first.displayName : "\(first.displayName) 等 \(viewModel.items.count) 项")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 10)
                        }

                        Text("拖图标取出文件 · 拖空白处移动架子")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    WindowDragHandleOverlay()
                }
            }
            .padding(8)
        }
    }

    private var gridItemsView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74, maximum: 92), spacing: 8)], spacing: 8) {
                ForEach(viewModel.items) { item in
                    ShelfGridItemCell(
                        item: item,
                        isSelected: viewModel.selectedItemIDs.contains(item.id),
                        viewModel: viewModel,
                        contextMenuBuilder: { buildContextMenu(for: item) }
                    )
                }
            }
            .padding(4)
        }
    }

    // MARK: - Bottom Action Footer
    private var bottomActionFooter: some View {
        HStack(spacing: 6) {
            // Drag All Handle
            ZStack {
                HStack(spacing: 4) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 11))
                    Text(viewModel.selectedItemIDs.isEmpty ? "按住拖出全部 (\(viewModel.items.count))" : "拖出所选 (\(viewModel.selectedItemIDs.count))")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                DragSourceOverlay(
                    itemsProvider: { viewModel.effectiveDragItems },
                    onSingleClick: { _ in
                        viewModel.selectAll()
                    },
                    onDoubleClick: {
                        viewModel.onRequestQuickLook?()
                    },
                    onRightClickMenu: {
                        buildContextMenu(for: nil)
                    },
                    onDragCompleted: { draggedIDs, _ in
                        if AppSettings.shared.removeItemsAfterDragOut {
                            viewModel.removeItems(withIDs: draggedIDs)
                        }
                    }
                )
            }
            .frame(height: 26)

            Button {
                viewModel.createZipArchive()
            } label: {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("一键打包为 ZIP")

            Button {
                viewModel.onRequestQuickLook?()
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("快速预览 (Space)")
        }
    }

    // MARK: - Context Menu Builder
    private func buildContextMenu(for specificItem: ShelfItem?) -> NSMenu {
        if let item = specificItem, !viewModel.selectedItemIDs.contains(item.id) {
            viewModel.selectedItemIDs = [item.id]
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开", action: #selector(ContextMenuActions.openSelected(_:)), keyEquivalent: "")
        openItem.target = ContextMenuActions.shared
        openItem.representedObject = viewModel
        menu.addItem(openItem)

        let previewItem = NSMenuItem(title: "快速预览 (Space)", action: #selector(ContextMenuActions.quickLook(_:)), keyEquivalent: " ")
        previewItem.target = ContextMenuActions.shared
        previewItem.representedObject = viewModel
        menu.addItem(previewItem)

        let finderItem = NSMenuItem(title: "在 Finder 中显示", action: #selector(ContextMenuActions.revealInFinder(_:)), keyEquivalent: "")
        finderItem.target = ContextMenuActions.shared
        finderItem.representedObject = viewModel
        menu.addItem(finderItem)

        menu.addItem(.separator())

        let zipItem = NSMenuItem(title: "打包为 ZIP", action: #selector(ContextMenuActions.zipItems(_:)), keyEquivalent: "")
        zipItem.target = ContextMenuActions.shared
        zipItem.representedObject = viewModel
        menu.addItem(zipItem)

        let copyItem = NSMenuItem(title: "复制文件", action: #selector(ContextMenuActions.copyFiles(_:)), keyEquivalent: "")
        copyItem.target = ContextMenuActions.shared
        copyItem.representedObject = viewModel
        menu.addItem(copyItem)

        let copyPathItem = NSMenuItem(title: "复制路径", action: #selector(ContextMenuActions.copyPaths(_:)), keyEquivalent: "")
        copyPathItem.target = ContextMenuActions.shared
        copyPathItem.representedObject = viewModel
        menu.addItem(copyPathItem)

        menu.addItem(.separator())

        let removeItem = NSMenuItem(title: "从架子移除", action: #selector(ContextMenuActions.removeSelected(_:)), keyEquivalent: "")
        removeItem.target = ContextMenuActions.shared
        removeItem.representedObject = viewModel
        menu.addItem(removeItem)

        return menu
    }
}

private struct ShelfGridItemCell: View {
    @ObservedObject var item: ShelfItem
    let isSelected: Bool
    @ObservedObject var viewModel: ShelfViewModel
    let contextMenuBuilder: () -> NSMenu

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Image(nsImage: item.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)

                Text(item.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.26) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )

            DragSourceOverlay(
                itemsProvider: {
                    if isSelected {
                        return viewModel.effectiveDragItems
                    } else {
                        return [item]
                    }
                },
                onSingleClick: { event in
                    let isCommand = event.modifierFlags.contains(.command)
                    viewModel.toggleSelection(for: item, exclusive: !isCommand)
                },
                onDoubleClick: {
                    NSWorkspace.shared.open(item.fileURL)
                },
                onRightClickMenu: contextMenuBuilder,
                onDragCompleted: { draggedIDs, _ in
                    if AppSettings.shared.removeItemsAfterDragOut {
                        viewModel.removeItems(withIDs: draggedIDs)
                    }
                }
            )

            Button {
                viewModel.removeItems(withIDs: [item.id])
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            .padding(3)
        }
    }
}

private final class ContextMenuActions: NSObject {
    static let shared = ContextMenuActions()

    @objc func openSelected(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? ShelfViewModel else { return }
        for item in vm.effectiveDragItems {
            NSWorkspace.shared.open(item.fileURL)
        }
    }

    @objc func quickLook(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? ShelfViewModel else { return }
        vm.onRequestQuickLook?()
    }

    @objc func revealInFinder(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? ShelfViewModel else { return }
        vm.revealInFinder()
    }

    @objc func zipItems(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? ShelfViewModel else { return }
        vm.createZipArchive()
    }

    @objc func copyFiles(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? ShelfViewModel else { return }
        vm.copyItemsToClipboard()
    }

    @objc func copyPaths(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? ShelfViewModel else { return }
        vm.copyPathsToClipboard()
    }

    @objc func removeSelected(_ sender: NSMenuItem) {
        guard let vm = sender.representedObject as? ShelfViewModel else { return }
        let ids = Set(vm.effectiveDragItems.map { $0.id })
        vm.removeItems(withIDs: ids)
    }
}

public final class MovableVisualEffectView: NSVisualEffectView {
    public override var mouseDownCanMoveWindow: Bool {
        return true
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

public struct VisualEffectBackground: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode

    public func makeNSView(context: Context) -> MovableVisualEffectView {
        let view = MovableVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: MovableVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
