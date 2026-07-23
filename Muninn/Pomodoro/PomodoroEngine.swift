import Foundation

/// Which part of the Pomodoro cycle is running.
enum PomodoroPhase: String, Codable {
    case focus, shortBreak, longBreak
    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
}

/// User-customizable durations + behaviour. Persisted via `PomodoroSettings`.
struct PomodoroConfig: Equatable, Codable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var longBreakEvery = 4        // a long break after every N focus sessions
    var autoStartNext = true

    /// Length of `phase` in seconds (clamped to ≥ 1 min).
    func duration(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus: return max(1, focusMinutes) * 60
        case .shortBreak: return max(1, shortBreakMinutes) * 60
        case .longBreak: return max(1, longBreakMinutes) * 60
        }
    }
}

/// Pure phase-transition rule (unit-tested).
enum Pomodoro {
    /// The phase that follows `phase`. `completedFocus` counts focus sessions finished so far (including
    /// the one just ending, if `phase == .focus`). A long break lands after every `longBreakEvery`th focus.
    static func next(after phase: PomodoroPhase, completedFocus: Int, config: PomodoroConfig) -> PomodoroPhase {
        switch phase {
        case .focus:
            return completedFocus % max(1, config.longBreakEvery) == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }
}

/// The running timer state machine. UI drives it with a 1-second `tick()`.
final class PomodoroEngine {
    private(set) var phase: PomodoroPhase = .focus
    private(set) var remaining: Int
    private(set) var completedFocus = 0
    private(set) var isRunning = false
    private(set) var config: PomodoroConfig

    init(config: PomodoroConfig) {
        self.config = config
        self.remaining = config.duration(for: .focus)
    }

    var total: Int { config.duration(for: phase) }
    var elapsedFraction: Double { total > 0 ? Double(total - remaining) / Double(total) : 0 }

    func start() { isRunning = true }
    func pause() { isRunning = false }
    func toggle() { isRunning.toggle() }

    /// Back to a fresh first focus session.
    func reset() {
        isRunning = false; phase = .focus; completedFocus = 0
        remaining = config.duration(for: .focus)
    }

    /// Apply new durations/behaviour. If the current phase is untouched (idle at full duration), the
    /// countdown reflects the new length immediately; a paused mid-phase clock is preserved.
    func apply(_ new: PomodoroConfig) {
        let atFullDuration = remaining == config.duration(for: phase)
        config = new
        if !isRunning && atFullDuration { remaining = config.duration(for: phase) }
    }

    /// Advance one second. Returns the phase that just ENDED if this tick finished it, else nil.
    @discardableResult
    func tick() -> PomodoroPhase? {
        guard isRunning else { return nil }
        if remaining > 0 { remaining -= 1 }
        return remaining <= 0 ? complete(autoStart: config.autoStartNext) : nil
    }

    /// Jump to the next phase now (as if the current one ended); preserves running/paused state.
    @discardableResult
    func skip() -> PomodoroPhase { complete(autoStart: isRunning) }

    private func complete(autoStart: Bool) -> PomodoroPhase {
        let ended = phase
        if ended == .focus { completedFocus += 1 }
        phase = Pomodoro.next(after: ended, completedFocus: completedFocus, config: config)
        remaining = config.duration(for: phase)
        isRunning = autoStart
        return ended
    }
}

/// Persisted Pomodoro configuration.
enum PomodoroSettings {
    private static let key = "muninn.pomodoro.config"
    static var config: PomodoroConfig {
        get {
            guard let d = UserDefaults.standard.data(forKey: key),
                  let c = try? JSONDecoder().decode(PomodoroConfig.self, from: d) else { return PomodoroConfig() }
            return c
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
}
