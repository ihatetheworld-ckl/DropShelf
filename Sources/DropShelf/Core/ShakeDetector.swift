import AppKit
import Foundation

public struct CursorSample {
    public let point: CGPoint
    public let timestamp: TimeInterval

    public init(point: CGPoint, timestamp: TimeInterval) {
        self.point = point
        self.timestamp = timestamp
    }
}

public struct ShakeAnalysisInput {
    public let requiredDirectionChanges: Int
    public let minimumSegmentDistance: CGFloat
    public let timeWindow: TimeInterval

    public init(
        requiredDirectionChanges: Int = 3,
        minimumSegmentDistance: CGFloat = 18,
        timeWindow: TimeInterval = 0.48
    ) {
        self.requiredDirectionChanges = requiredDirectionChanges
        self.minimumSegmentDistance = minimumSegmentDistance
        self.timeWindow = timeWindow
    }
}

public enum ShakeEvaluator {
    /// Evaluates whether a sequence of cursor samples within a time window constitutes a rapid back-and-forth shake gesture.
    public static func isShakeDetected(
        samples: [CursorSample],
        config: ShakeAnalysisInput
    ) -> Bool {
        guard samples.count >= 4 else { return false }

        // Check dominant axis (X or Y)
        let horizontalReversals = countAxisReversals(
            samples: samples,
            axisExtractor: { $0.x },
            minSegmentDistance: config.minimumSegmentDistance
        )

        if horizontalReversals >= config.requiredDirectionChanges {
            return true
        }

        let verticalReversals = countAxisReversals(
            samples: samples,
            axisExtractor: { $0.y },
            minSegmentDistance: config.minimumSegmentDistance
        )

        return verticalReversals >= config.requiredDirectionChanges
    }

    private static func countAxisReversals(
        samples: [CursorSample],
        axisExtractor: (CGPoint) -> CGFloat,
        minSegmentDistance: CGFloat
    ) -> Int {
        guard let first = samples.first else { return 0 }
        var anchorValue = axisExtractor(first.point)
        var currentDirection: Int = 0 // -1 or +1
        var reversals = 0
        var extremeValue = anchorValue

        for sample in samples.dropFirst() {
            let value = axisExtractor(sample.point)
            if currentDirection == 0 {
                let delta = value - anchorValue
                if abs(delta) >= minSegmentDistance {
                    currentDirection = delta > 0 ? 1 : -1
                    extremeValue = value
                }
            } else if currentDirection == 1 {
                if value > extremeValue {
                    extremeValue = value
                } else if (extremeValue - value) >= minSegmentDistance {
                    reversals += 1
                    currentDirection = -1
                    anchorValue = extremeValue
                    extremeValue = value
                }
            } else if currentDirection == -1 {
                if value < extremeValue {
                    extremeValue = value
                } else if (value - extremeValue) >= minSegmentDistance {
                    reversals += 1
                    currentDirection = 1
                    anchorValue = extremeValue
                    extremeValue = value
                }
            }
        }

        return reversals
    }
}

public final class ShakeDetector {
    public var onSummonRequested: ((CGPoint) -> Void)?
    /// Returns true if an internal shelf drag is currently active so we don't summon a duplicate shelf when dragging items out of a shelf.
    public var isInternalDragActive: (() -> Bool)?

    private var globalDragMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var localDragMonitor: Any?
    private var samples: [CursorSample] = []
    private var lastKnownDragChangeCount: Int = -1
    private var summonedForCurrentDragSession: Bool = false
    private var lastSummonTimestamp: TimeInterval = 0

    public init() {}

    public func startMonitoring() {
        stopMonitoring()

        let dragPasteboard = NSPasteboard(name: .drag)
        lastKnownDragChangeCount = dragPasteboard.changeCount

        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleMouseDragged(event: event)
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.resetDragSession()
        }
    }

    public func stopMonitoring() {
        if let monitor = globalDragMonitor {
            NSEvent.removeMonitor(monitor)
            globalDragMonitor = nil
        }
        if let monitor = globalMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseUpMonitor = nil
        }
        if let monitor = localDragMonitor {
            NSEvent.removeMonitor(monitor)
            localDragMonitor = nil
        }
    }

    private func resetDragSession() {
        samples.removeAll()
        summonedForCurrentDragSession = false
    }

    private func handleMouseDragged(event: NSEvent) {
        if isInternalDragActive?() == true {
            return
        }

        let settings = AppSettings.shared
        let now = ProcessInfo.processInfo.systemUptime
        let mouseLocation = NSEvent.mouseLocation

        // Cooldown of 1.0s between summons
        guard now - lastSummonTimestamp > 1.0 else { return }

        // Check if system drag pasteboard has active items or updated changeCount
        let dragPasteboard = NSPasteboard(name: .drag)
        let currentChangeCount = dragPasteboard.changeCount
        if currentChangeCount != lastKnownDragChangeCount {
            lastKnownDragChangeCount = currentChangeCount
            summonedForCurrentDragSession = false
            samples.removeAll()
        }

        guard !summonedForCurrentDragSession else { return }

        // Ensure there's actually something on the drag pasteboard (or user is dragging from Finder/Browser/App)
        let hasDragTypes = !(dragPasteboard.types?.isEmpty ?? true)
        guard hasDragTypes else { return }

        // Option (⌥) + Drag instant summon without shaking
        if settings.optionDragToSummonEnabled && event.modifierFlags.contains(.option) {
            summonedForCurrentDragSession = true
            lastSummonTimestamp = now
            samples.removeAll()
            DispatchQueue.main.async { [weak self] in
                self?.onSummonRequested?(mouseLocation)
            }
            return
        }

        guard settings.shakeToSummonEnabled else { return }

        let sensitivity = settings.shakeSensitivity
        let timeWindow = sensitivity.timeWindow

        samples.append(CursorSample(point: mouseLocation, timestamp: now))
        samples.removeAll { now - $0.timestamp > timeWindow }

        let config = ShakeAnalysisInput(
            requiredDirectionChanges: sensitivity.requiredDirectionChanges,
            minimumSegmentDistance: sensitivity.minimumSegmentDistance,
            timeWindow: timeWindow
        )

        if ShakeEvaluator.isShakeDetected(samples: samples, config: config) {
            summonedForCurrentDragSession = true
            lastSummonTimestamp = now
            samples.removeAll()
            DispatchQueue.main.async { [weak self] in
                self?.onSummonRequested?(mouseLocation)
            }
        }
    }
}
