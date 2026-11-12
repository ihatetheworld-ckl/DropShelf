import AppKit
import Combine

/// AppKit has no public trackpad amplitude control. A short pair of generic
/// cues makes a summon easier to distinguish without misusing pressure patterns.
final class ShelfHapticFeedback {
    static let shared = ShelfHapticFeedback()
    static let secondTapDelay: TimeInterval = 0.12

    private let perform: () -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let settings: AppSettings
    private var generation = UUID()
    private var observations = Set<AnyCancellable>()

    init(settings: AppSettings = .shared,
         perform: @escaping () -> Void = {
             // Devices/preferences may change; never cache the performer.
             NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
         },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
         }) {
        self.settings = settings
        self.perform = perform
        self.schedule = schedule
        // Cancel even an off/on toggle between taps, or a style change back.
        settings.$hapticFeedbackEnabled.dropFirst().sink { [weak self] _ in
            self?.cancelPendingFeedback()
        }.store(in: &observations)
        settings.$summonHapticStyle.dropFirst().sink { [weak self] _ in
            self?.cancelPendingFeedback()
        }.store(in: &observations)
    }

    func play() {
        cancelPendingFeedback()
        guard settings.hapticFeedbackEnabled else { return }
        let request = generation
        perform()
        guard settings.summonHapticStyle == .doubleTap else { return }
        schedule(Self.secondTapDelay) { [weak self] in
            guard let self = self, self.generation == request,
                  self.settings.hapticFeedbackEnabled,
                  self.settings.summonHapticStyle == .doubleTap else { return }
            self.perform()
        }
    }

    func cancelPendingFeedback() { generation = UUID() }
}
