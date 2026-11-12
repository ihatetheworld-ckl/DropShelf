import AppKit
import Foundation

/// An isolated public-API experiment, not a strength selector for DropShelf.
private final class HapticProbe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let patterns: [(String, NSHapticFeedbackManager.FeedbackPattern)] = [
        ("通用（generic）", .generic),
        ("对齐（alignment）", .alignment),
        ("压力变化（levelChange）", .levelChange)
    ]
    private let rhythms: [(String, [TimeInterval])] = [
        ("单次", [0]), ("双次 240 ms", [0, 0.24]), ("双次 320 ms", [0, 0.32])
    ]
    private let timing = NSPopUpButton(frame: .zero, pullsDown: false)
    private let status = NSTextField(wrappingLabelWithString: "请选择一组测试；听到或看到请求不代表硬件实际执行。")
    private var buttons: [NSButton] = []
    private var window: NSWindow!
    private var generation = UUID()
    private var logURL: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("haptic-probe-requests.jsonl")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "DropShelf · Force Touch 触觉对比实验"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = NSView()
        window.contentView = content

        let heading = NSTextField(labelWithString: "比较手感，不预设哪个更强")
        heading.font = .boldSystemFont(ofSize: 18)
        let instructions = NSTextField(wrappingLabelWithString:
            "请用触控板点击“试用”，等待 0.8 秒开始，保持手指轻放，不必用力按。每次只执行所选的一组。")
        instructions.preferredMaxLayoutWidth = 730
        timing.addItems(withTitles: ["立即请求（now）", "随界面刷新（drawCompleted）"])
        let timingRow = NSStackView(views: [NSTextField(labelWithString: "触发时机："), timing])
        timingRow.spacing = 8

        var rows: [[NSView]] = [[NSTextField(labelWithString: "系统模式")]]
        rows[0].append(contentsOf: rhythms.map { NSTextField(labelWithString: $0.0) })
        for (patternIndex, pattern) in patterns.enumerated() {
            var row: [NSView] = [NSTextField(labelWithString: pattern.0)]
            for rhythmIndex in rhythms.indices {
                let button = NSButton(title: "试用", target: self, action: #selector(test(_:)))
                button.bezelStyle = .rounded
                button.tag = patternIndex * rhythms.count + rhythmIndex
                button.setAccessibilityLabel(pattern.0 + "，" + rhythms[rhythmIndex].0)
                buttons.append(button)
                row.append(button)
            }
            rows.append(row)
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 18
        grid.column(at: 0).width = 205
        for index in 1...3 { grid.column(at: index).width = 145 }

        status.font = .systemFont(ofSize: 13, weight: .medium)
        status.preferredMaxLayoutWidth = 730
        let stop = NSButton(title: "停止本次测试", target: self, action: #selector(stopTest))
        stop.bezelStyle = .rounded
        let caveat = NSTextField(wrappingLabelWithString:
            "三种模式不是力度档位。对齐、压力变化仅供实验比较；当前 DropShelf 的唤起仍使用通用模式。系统可能省略反馈，本窗口只能记录 API 请求，不能测量实际震动或强度。")
        caveat.preferredMaxLayoutWidth = 730
        caveat.font = .systemFont(ofSize: 11)
        caveat.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [heading, instructions, timingRow, grid, status, stop, caveat])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        record(["event": "launched", "physical_feedback_verified": false])
        // Capture only our own view hierarchy for layout checks; no screen capture.
        content.layoutSubtreeIfNeeded()
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(
                to: logURL.deletingLastPathComponent().appendingPathComponent("probe-layout.png"))
        }
    }

    @objc private func test(_ sender: NSButton) {
        generation = UUID()
        let request = generation
        let pattern = patterns[sender.tag / rhythms.count]
        let rhythm = rhythms[sender.tag % rhythms.count]
        let performanceTime: NSHapticFeedbackManager.PerformanceTime = timing.indexOfSelectedItem == 0 ? .now : .drawCompleted
        let timingName = timing.indexOfSelectedItem == 0 ? "now" : "drawCompleted"
        let began = ProcessInfo.processInfo.systemUptime
        setControlsEnabled(false)
        status.stringValue = "请保持手指接触：0.8 秒后测试「\(pattern.0) · \(rhythm.0) · \(timingName)」"
        record(["event": "test_requested", "pattern": pattern.0, "rhythm": rhythm.0, "timing": timingName])
        for (index, offset) in rhythm.1.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + offset) { [weak self] in
                guard let self = self, self.generation == request, self.window.isVisible else { return }
                self.status.stringValue = "正在请求「\(pattern.0) · \(rhythm.0)」第 \(index + 1) 次…"
                self.window.contentView?.needsDisplay = true
                NSHapticFeedbackManager.defaultPerformer.perform(pattern.1, performanceTime: performanceTime)
                self.record(["event": "api_request", "pattern": pattern.0, "rhythm": rhythm.0,
                             "timing": timingName, "pulse": index + 1,
                             "elapsed_ms": (ProcessInfo.processInfo.systemUptime - began) * 1000,
                             "app_active": NSApp.isActive, "physical_feedback_verified": false])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + (rhythm.1.last ?? 0) + 0.25) { [weak self] in
            guard let self = self, self.generation == request, self.window.isVisible else { return }
            self.status.stringValue = "本组请求已结束：「\(pattern.0) · \(rhythm.0) · \(timingName)」。请比较实际触感。"
            self.setControlsEnabled(true)
        }
    }

    @objc private func stopTest() {
        generation = UUID()
        setControlsEnabled(true)
        status.stringValue = "已停止尚未发送的请求。"
        record(["event": "cancelled"])
    }

    private func setControlsEnabled(_ enabled: Bool) {
        buttons.forEach { $0.isEnabled = enabled }
        timing.isEnabled = enabled
    }

    private func record(_ fields: [String: Any]) {
        var entry = fields
        entry["date"] = ISO8601DateFormatter().string(from: Date())
        guard var data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        data.append(0x0a)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data) } catch {}
    }

    func windowWillClose(_ notification: Notification) {
        generation = UUID()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
private let delegate = HapticProbe()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
