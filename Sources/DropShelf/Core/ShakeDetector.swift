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

/// A mouse drag event can be a window move or selection, and the drag pasteboard
/// retains data after a completed drop. Arm only on a new pasteboard generation
/// observed after this gesture's mouse-down, never on leftover types alone.
struct DragSummonTracker {
    private var initialChangeCount: Int?
    private var contentChangeCount: Int?
    private var samples: [CursorSample] = []
    private var hasSummoned = false
    private var lastSummonTime = -TimeInterval.infinity

    mutating func beginGesture(pasteboardChangeCount: Int) {
        initialChangeCount = pasteboardChangeCount
        contentChangeCount = nil
        samples.removeAll()
        hasSummoned = false
    }

    mutating func endGesture() {
        initialChangeCount = nil
        contentChangeCount = nil
        samples.removeAll()
        hasSummoned = false
    }

    mutating func shouldSummon(at point: CGPoint, time: TimeInterval,
                               pasteboardChangeCount: Int, containsSupportedContent: Bool,
                               optionHeld: Bool = false, isInternalDrag: Bool = false,
                               shakeEnabled: Bool = true, optionEnabled: Bool = true,
                               config: ShakeAnalysisInput = ShakeAnalysisInput(
                                requiredDirectionChanges: 3, minimumSegmentDistance: 18, timeWindow: 0.48)) -> Bool {
        guard let initialChangeCount = initialChangeCount,
              pasteboardChangeCount != initialChangeCount,
              containsSupportedContent, !isInternalDrag else {
            samples.removeAll()
            contentChangeCount = nil
            return false
        }
        // Source apps may add formats during a drag. This must never reset the
        // one-summon latch; a new mouse-down is required for another summon.
        guard !hasSummoned else { return false }
        guard time - lastSummonTime >= 1.0 else {
            samples.removeAll()
            return false
        }
        if contentChangeCount != pasteboardChangeCount {
            contentChangeCount = pasteboardChangeCount
            samples.removeAll()
        }

        if optionEnabled && optionHeld {
            hasSummoned = true
            lastSummonTime = time
            samples.removeAll()
            return true
        }
        guard shakeEnabled else {
            samples.removeAll()
            return false
        }
        samples.append(CursorSample(point: point, timestamp: time))
        samples.removeAll { time - $0.timestamp > config.timeWindow }
        guard ShakeEvaluator.isShakeDetected(samples: samples, config: config) else { return false }
        hasSummoned = true
        lastSummonTime = time
        samples.removeAll()
        return true
    }
}

public final class ShakeDetector {
    public var onSummonRequested: ((CGPoint) -> Void)?
    /// Returns true if an internal shelf drag is currently active so we don't summon a duplicate shelf when dragging items out of a shelf.
    public var isInternalDragActive: (() -> Bool)?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var tracker = DragSummonTracker()

    static func containsSupportedContent(types: [NSPasteboard.PasteboardType]?) -> Bool {
        let supported: Set<NSPasteboard.PasteboardType> = [
            .fileURL, .URL, .png, .tiff, .string,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ]
        return (types ?? []).contains { supported.contains($0) }
    }

    public init() {}

    public func startMonitoring() {
        stopMonitoring()

        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.handleMouseEvent(event)
        }
        // Global monitors exclude our app. Local boundaries prevent a shelf drag
        // or a click in this app from leaking into the next external gesture.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    public func stopMonitoring() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        tracker.endGesture()
    }

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            tracker.beginGesture(pasteboardChangeCount: NSPasteboard(name: .drag).changeCount)
        case .leftMouseUp:
            tracker.endGesture()
        case .leftMouseDragged:
            handleMouseDragged(event: event)
        default:
            break
        }
    }

    private func handleMouseDragged(event: NSEvent) {
        let settings = AppSettings.shared
        let sensitivity = settings.shakeSensitivity
        let pasteboard = NSPasteboard(name: .drag)
        let point = NSEvent.mouseLocation
        let shouldSummon = tracker.shouldSummon(
            at: point, time: ProcessInfo.processInfo.systemUptime,
            pasteboardChangeCount: pasteboard.changeCount,
            containsSupportedContent: Self.containsSupportedContent(types: pasteboard.types),
            optionHeld: event.modifierFlags.contains(.option),
            isInternalDrag: isInternalDragActive?() == true,
            shakeEnabled: settings.shakeToSummonEnabled,
            optionEnabled: settings.optionDragToSummonEnabled,
            config: ShakeAnalysisInput(requiredDirectionChanges: sensitivity.requiredDirectionChanges,
                                       minimumSegmentDistance: sensitivity.minimumSegmentDistance,
                                       timeWindow: sensitivity.timeWindow))
        if shouldSummon {
            // Event-monitor handlers run on main. Deliver synchronously so a
            // queued callback cannot resurrect a gesture after mouse-up.
            onSummonRequested?(point)
        }
    }
}
