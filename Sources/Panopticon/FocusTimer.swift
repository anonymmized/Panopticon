import AppKit

final class FocusTimer: ObservableObject {
    @Published var remaining: Double = 25 * 60
    @Published var isRunning = false
    @Published private(set) var sessionDuration: Double = 25 * 60
    var soundEnabled = true
    var onChange: (() -> Void)?
    private var endDate: Date?
    private var timer: Timer?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.dictionary(forKey: "focusSession") {
            sessionDuration = SettingsRules.number(
                saved["duration"] as? Double ?? 1500, 1...5400, fallback: 1500)
            remaining = SettingsRules.number(saved["remaining"] as? Double ?? sessionDuration,
                0...sessionDuration, fallback: sessionDuration)
            if let end = saved["end"] as? Date {
                remaining = SettingsRules.number(end.timeIntervalSinceNow, 0...sessionDuration, fallback: 0)
                endDate = Date().addingTimeInterval(remaining)
                isRunning = remaining > 0
                if isRunning {
                    startTicker()
                } else {
                    endDate = nil
                    persist()
                }
            }
        }
    }
    deinit { timer?.invalidate() }
    /// A duration picker configures the next session without discarding a pause.
    func prepareNextSession(minutes: Double) {
        if !isRunning && remaining >= sessionDuration { reset(minutes: minutes) }
    }
    func toggle(minutes: Double) {
        if isRunning {
            remaining = max(0, endDate?.timeIntervalSinceNow ?? remaining)
            endDate = nil
            isRunning = false
            timer?.invalidate()
            timer = nil
        } else {
            if remaining <= 0 {
                remaining = Self.duration(minutes)
                sessionDuration = remaining
            }
            endDate = Date().addingTimeInterval(remaining)
            isRunning = true
            startTicker()
        }
        persist()
        onChange?()
    }
    private func startTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let end = self.endDate else { return }
            self.remaining = max(0, end.timeIntervalSinceNow)
            if self.remaining == 0 {
                self.endDate = nil
                self.isRunning = false
                self.timer?.invalidate()
                self.timer = nil
                self.persist()
                if self.soundEnabled { NSSound(named: "Glass")?.play() }
            }
            self.onChange?()
        }
        timer?.tolerance = 0.1
    }
    private func persist() {
        var state: [String: Any] = ["remaining": remaining, "duration": sessionDuration]
        if let endDate { state["end"] = endDate }
        defaults.set(state, forKey: "focusSession")
    }
    func reset(minutes: Double) {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remaining = Self.duration(minutes)
        sessionDuration = remaining
        isRunning = false
        persist()
        onChange?()
    }
    var progress: Double { min(1, max(0, 1 - remaining / max(sessionDuration, 1))) }
    var hasStarted: Bool { isRunning || remaining < sessionDuration }
    private static func duration(_ minutes: Double) -> Double {
        SettingsRules.number(minutes, 5...90, fallback: 25) * 60
    }
    var text: String {
        let seconds = max(0, Int(ceil(remaining)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
