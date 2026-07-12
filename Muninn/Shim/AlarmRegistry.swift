import Foundation

/// `chrome.alarms` over a `DispatchSourceTimer` registry (Spike B Tier-1 mapping).
/// Wall-clock scheduling so alarms behave sensibly across sleep.
@MainActor
final class AlarmRegistry {
    struct Alarm { let name: String; let scheduledTime: Double; let periodInMinutes: Double? }

    private var alarms: [String: Alarm] = [:]
    private var timers: [String: DispatchSourceTimer] = [:]

    /// Invoked when an alarm fires; wired to the broker's event path.
    var onFire: ((Alarm) -> Void)?

    func create(name: String, info: [String: Any]) {
        let now = Date().timeIntervalSince1970 * 1000
        let when: Double
        if let at = info["when"] as? Double { when = at }
        else if let delay = info["delayInMinutes"] as? Double { when = now + delay * 60_000 }
        else if let period = info["periodInMinutes"] as? Double { when = now + period * 60_000 }
        else { when = now }
        let period = info["periodInMinutes"] as? Double
        let alarm = Alarm(name: name, scheduledTime: when, periodInMinutes: period)
        alarms[name] = alarm
        schedule(alarm)
    }

    func get(name: String) -> [String: Any]? { alarms[name].map(dict) }
    func getAll() -> [[String: Any]] { alarms.values.map(dict) }

    func clear(name: String) -> Bool {
        timers[name]?.cancel(); timers[name] = nil
        return alarms.removeValue(forKey: name) != nil
    }

    func clearAll() {
        timers.values.forEach { $0.cancel() }
        timers.removeAll(); alarms.removeAll()
    }

    // MARK: -

    private func dict(_ a: Alarm) -> [String: Any] {
        var d: [String: Any] = ["name": a.name, "scheduledTime": a.scheduledTime]
        if let p = a.periodInMinutes { d["periodInMinutes"] = p }
        return d
    }

    private func schedule(_ alarm: Alarm) {
        timers[alarm.name]?.cancel()
        let now = Date().timeIntervalSince1970 * 1000
        let delaySec = max(0, (alarm.scheduledTime - now) / 1000)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        if let period = alarm.periodInMinutes {
            timer.schedule(deadline: .now() + delaySec, repeating: period * 60)
        } else {
            timer.schedule(deadline: .now() + delaySec)
        }
        timer.setEventHandler { [weak self] in
            guard let self, let current = self.alarms[alarm.name] else { return }
            self.onFire?(current)
            if current.periodInMinutes == nil {
                self.timers[alarm.name]?.cancel()
                self.timers[alarm.name] = nil
                self.alarms.removeValue(forKey: alarm.name)
            }
        }
        timers[alarm.name] = timer
        timer.resume()
    }
}
