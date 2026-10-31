import Foundation
import Combine

public enum ShakeSensitivity: String, CaseIterable, Identifiable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .low: return "低（需明显来回晃动）"
        case .medium: return "中（推荐默认灵敏度）"
        case .high: return "高（轻微晃动即唤起）"
        }
    }

    public var requiredDirectionChanges: Int {
        switch self {
        case .low: return 4
        case .medium: return 3
        case .high: return 2
        }
    }

    public var minimumSegmentDistance: CGFloat {
        switch self {
        case .low: return 28
        case .medium: return 18
        case .high: return 12
        }
    }

    public var timeWindow: TimeInterval {
        switch self {
        case .low: return 0.42
        case .medium: return 0.48
        case .high: return 0.55
        }
    }
}

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @Published public var shakeToSummonEnabled: Bool {
        didSet { UserDefaults.standard.set(shakeToSummonEnabled, forKey: "shakeToSummonEnabled") }
    }

    @Published public var optionDragToSummonEnabled: Bool {
        didSet { UserDefaults.standard.set(optionDragToSummonEnabled, forKey: "optionDragToSummonEnabled") }
    }

    @Published public var shakeSensitivity: ShakeSensitivity {
        didSet { UserDefaults.standard.set(shakeSensitivity.rawValue, forKey: "shakeSensitivity") }
    }

    @Published public var autoCloseWhenEmptied: Bool {
        didSet { UserDefaults.standard.set(autoCloseWhenEmptied, forKey: "autoCloseWhenEmptied") }
    }

    @Published public var removeItemsAfterDragOut: Bool {
        didSet { UserDefaults.standard.set(removeItemsAfterDragOut, forKey: "removeItemsAfterDragOut") }
    }

    @Published public var autoCollapseEmptyShelfSeconds: Double {
        didSet { UserDefaults.standard.set(autoCollapseEmptyShelfSeconds, forKey: "autoCollapseEmptyShelfSeconds") }
    }

    @Published public var soundEffectsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "shakeToSummonEnabled": true,
            "optionDragToSummonEnabled": true,
            "shakeSensitivity": ShakeSensitivity.medium.rawValue,
            "autoCloseWhenEmptied": true,
            "removeItemsAfterDragOut": true,
            "autoCollapseEmptyShelfSeconds": 5.0,
            "soundEffectsEnabled": true
        ])

        self.shakeToSummonEnabled = defaults.bool(forKey: "shakeToSummonEnabled")
        self.optionDragToSummonEnabled = defaults.bool(forKey: "optionDragToSummonEnabled")
        let rawSens = defaults.string(forKey: "shakeSensitivity") ?? ShakeSensitivity.medium.rawValue
        self.shakeSensitivity = ShakeSensitivity(rawValue: rawSens) ?? .medium
        self.autoCloseWhenEmptied = defaults.bool(forKey: "autoCloseWhenEmptied")
        self.removeItemsAfterDragOut = defaults.bool(forKey: "removeItemsAfterDragOut")
        self.autoCollapseEmptyShelfSeconds = defaults.double(forKey: "autoCollapseEmptyShelfSeconds")
        self.soundEffectsEnabled = defaults.bool(forKey: "soundEffectsEnabled")
    }
}
