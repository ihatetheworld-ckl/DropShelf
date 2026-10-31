import AppKit
import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.blue.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 46, height: 46)
                        Image(systemName: "tray.2.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DropShelf 偏好设置")
                            .font(.system(size: 16, weight: .bold))
                        Text("零延迟、纯原生的 macOS 悬浮文件暂存架（无任何等待限制）")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)

                Divider()

                GroupBox(label: Label("唤起手势与触发方式", systemImage: "cursorarrow.motionlines")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("拖拽文件/内容时晃动鼠标唤起架子 (Shake to Summon)", isOn: $settings.shakeToSummonEnabled)

                        HStack {
                            Text("晃动灵敏度：")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Picker("", selection: $settings.shakeSensitivity) {
                                ForEach(ShakeSensitivity.allCases) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                            .disabled(!settings.shakeToSummonEnabled)
                        }

                        Toggle("按住 Option (⌥) 键拖拽立即唤起架子（无需晃动）", isOn: $settings.optionDragToSummonEnabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Label("架子行为与自动化", systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("将文件拖出架子后自动从架子移除", isOn: $settings.removeItemsAfterDragOut)
                        Toggle("架子内文件全部拖出后自动关闭架子（未固定时）", isOn: $settings.autoCloseWhenEmptied)
                        Toggle("启用提示音效", isOn: $settings.soundEffectsEnabled)

                        HStack {
                            Text("空白架子自动收起等待时间：")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Slider(value: $settings.autoCollapseEmptyShelfSeconds, in: 2...15, step: 1)
                                .frame(width: 150)
                            Text("\(Int(settings.autoCollapseEmptyShelfSeconds)) 秒")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Label("全局快捷键说明", systemImage: "command")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("在鼠标位置新建空白架子：")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("⇧ + ⌘ + D")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        HStack {
                            Text("折叠 / 展开所有活动架子：")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("⌥ + ⇧ + Space")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        HStack {
                            Text("架子内快捷操作：")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Space 快速预览 · ⌘C 复制 · ⌘V 粘贴")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.system(size: 12))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 460, idealWidth: 480, maxWidth: .infinity, minHeight: 380, idealHeight: 500, maxHeight: .infinity)
    }
}
