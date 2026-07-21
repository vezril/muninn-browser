import Foundation

/// One concrete occurrence of an event (recurrence already expanded).
struct Occurrence {
    let event: VEvent
    let start: Date
    let end: Date
    var joinURL: URL? { JoinLink.extract(from: event) }
    var title: String { event.summary }
}

/// Expands a `VEvent` (recurring or not) into concrete occurrences, and resolves "the next
/// upcoming occurrence" across a set of events. Pure — fully unit-testable from `.ics` fixtures.
enum Recurrence {

    /// All occurrences whose span intersects `[windowStart, windowEnd]`, ascending by start.
    static func occurrences(of e: VEvent, windowStart: Date, windowEnd: Date,
                            hardLimit: Int = 5000) -> [Occurrence] {
        guard let seriesStart = e.start.absolute() else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = e.start.timeZone
        if let r = e.rrule { cal.firstWeekday = r.wkst }

        let duration = occurrenceDuration(e, seriesStart: seriesStart)

        var starts: [Date]
        if let r = e.rrule {
            starts = expand(r, seriesStart: seriesStart, cal: cal, windowEnd: windowEnd, hardLimit: hardLimit)
        } else {
            starts = [seriesStart]
        }
        // RDATE additions (each carries its own zone).
        starts += e.rdates.compactMap { $0.absolute() }
        // EXDATE removals (match by absolute instant).
        let excluded = Set(e.exdates.compactMap { $0.absolute() })
        starts = Array(Set(starts.filter { !excluded.contains($0) })).sorted()

        var out: [Occurrence] = []
        for s in starts {
            let end = s.addingTimeInterval(duration)
            if end > windowStart && s < windowEnd {
                out.append(Occurrence(event: e, start: s, end: end))
            }
        }
        return out
    }

    /// The soonest occurrence (across all events) that hasn't yet ended, relative to `now`.
    /// Looks ahead `horizonDays` (extended once if nothing is found nearer).
    static func nextOccurrence(in events: [VEvent], now: Date, horizonDays: Int = 60) -> Occurrence? {
        for horizon in [horizonDays, horizonDays * 6, 366 * 3] {
            let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: horizon, to: now) ?? now
            let all = events.flatMap { occurrences(of: $0, windowStart: now, windowEnd: end) }
            if let next = all.filter({ $0.end > now }).min(by: { $0.start < $1.start }) {
                return next
            }
        }
        return nil
    }

    // MARK: - internals

    private static func occurrenceDuration(_ e: VEvent, seriesStart: Date) -> TimeInterval {
        if let end = e.end?.absolute() { return max(0, end.timeIntervalSince(seriesStart)) }
        return e.start.isAllDay ? 86400 : 0
    }

    /// Ascending absolute start dates produced by the RRULE, from `seriesStart` up to
    /// `min(windowEnd, UNTIL)`, honouring COUNT (counted from the series start).
    private static func expand(_ r: RRule, seriesStart: Date, cal: Calendar,
                               windowEnd: Date, hardLimit: Int) -> [Date] {
        let hms = cal.dateComponents([.hour, .minute, .second], from: seriesStart)
        let cutoff = min(windowEnd, r.until ?? .distantFuture)
        var results: [Date] = []
        var emitted = 0
        var period = 0
        let periodCap = 200_000

        while period < periodCap {
            var candidates = candidateStarts(r, seriesStart: seriesStart, cal: cal, period: period, hms: hms)
            candidates = candidates.filter { $0 >= seriesStart }.sorted()
            if !r.bySetPos.isEmpty { candidates = applySetPos(candidates, r.bySetPos) }

            for d in candidates {
                if let until = r.until, d > until { return results }
                emitted += 1
                if d <= cutoff { results.append(d) }
                if let c = r.count, emitted >= c { return results }
                if emitted >= hardLimit { return results }
            }

            // Once the period base passes the cutoff, no later candidate can land in-window —
            // safe to stop (COUNT only ever limits the series, never extends it past the cutoff).
            if let base = periodBase(r, seriesStart: seriesStart, cal: cal, period: period), base > cutoff {
                break
            }
            period += 1
        }
        return results
    }

    /// The first instant of a period (used only as a stop heuristic).
    private static func periodBase(_ r: RRule, seriesStart: Date, cal: Calendar, period: Int) -> Date? {
        let unit: Calendar.Component
        switch r.freq { case .daily: unit = .day; case .weekly: unit = .weekOfYear
                        case .monthly: unit = .month; case .yearly: unit = .year }
        return cal.date(byAdding: unit, value: period * r.interval, to: seriesStart)
    }

    private static func candidateStarts(_ r: RRule, seriesStart: Date, cal: Calendar,
                                        period: Int, hms: DateComponents) -> [Date] {
        switch r.freq {
        case .daily:   return dailyCandidates(r, seriesStart: seriesStart, cal: cal, period: period)
        case .weekly:  return weeklyCandidates(r, seriesStart: seriesStart, cal: cal, period: period, hms: hms)
        case .monthly: return monthlyCandidates(r, seriesStart: seriesStart, cal: cal, period: period, hms: hms)
        case .yearly:  return yearlyCandidates(r, seriesStart: seriesStart, cal: cal, period: period, hms: hms)
        }
    }

    private static func dailyCandidates(_ r: RRule, seriesStart: Date, cal: Calendar, period: Int) -> [Date] {
        guard let base = cal.date(byAdding: .day, value: period * r.interval, to: seriesStart) else { return [] }
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: base)
        if !r.byMonth.isEmpty, let m = c.month, !r.byMonth.contains(m) { return [] }
        if !r.byMonthDay.isEmpty, let d = c.day, let dim = daysInMonth(base, cal), !matchesMonthDay(d, r.byMonthDay, dim) { return [] }
        if !r.byDay.isEmpty, let wd = c.weekday, !r.byDay.contains(where: { $0.weekday == wd }) { return [] }
        return [base]
    }

    private static func weeklyCandidates(_ r: RRule, seriesStart: Date, cal: Calendar,
                                         period: Int, hms: DateComponents) -> [Date] {
        // No BYDAY: keep the same weekday, step whole weeks.
        if r.byDay.isEmpty {
            guard let d = cal.date(byAdding: .weekOfYear, value: period * r.interval, to: seriesStart) else { return [] }
            if !r.byMonth.isEmpty, let m = cal.dateComponents([.month], from: d).month, !r.byMonth.contains(m) { return [] }
            return [d]
        }
        // BYDAY: enumerate the listed weekdays within this (interval-stepped) week.
        guard let weekStart = startOfWeek(seriesStart, cal: cal),
              let thisWeek = cal.date(byAdding: .weekOfYear, value: period * r.interval, to: weekStart) else { return [] }
        var out: [Date] = []
        for bd in r.byDay {
            let offset = (bd.weekday - cal.firstWeekday + 7) % 7
            guard let day = cal.date(byAdding: .day, value: offset, to: thisWeek),
                  let dt = setTime(hms, on: day, cal: cal) else { continue }
            if !r.byMonth.isEmpty, let m = cal.dateComponents([.month], from: dt).month, !r.byMonth.contains(m) { continue }
            out.append(dt)
        }
        return out
    }

    private static func monthlyCandidates(_ r: RRule, seriesStart: Date, cal: Calendar,
                                          period: Int, hms: DateComponents) -> [Date] {
        guard let monthBase = cal.date(byAdding: .month, value: period * r.interval, to: seriesStart) else { return [] }
        let ym = cal.dateComponents([.year, .month], from: monthBase)
        if !r.byMonth.isEmpty, let m = ym.month, !r.byMonth.contains(m) { return [] }
        return daysInTargetMonth(r, year: ym.year!, month: ym.month!, cal: cal, hms: hms,
                                 fallbackDay: cal.dateComponents([.day], from: seriesStart).day!)
    }

    private static func yearlyCandidates(_ r: RRule, seriesStart: Date, cal: Calendar,
                                         period: Int, hms: DateComponents) -> [Date] {
        guard let yearBase = cal.date(byAdding: .year, value: period * r.interval, to: seriesStart) else { return [] }
        let year = cal.dateComponents([.year], from: yearBase).year!
        let months = r.byMonth.isEmpty ? [cal.dateComponents([.month], from: seriesStart).month!] : r.byMonth
        var out: [Date] = []
        for m in months {
            out += daysInTargetMonth(r, year: year, month: m, cal: cal, hms: hms,
                                     fallbackDay: cal.dateComponents([.day], from: seriesStart).day!)
        }
        return out
    }

    /// The candidate dates within one (year, month), from BYDAY / BYMONTHDAY, else the fallback day.
    private static func daysInTargetMonth(_ r: RRule, year: Int, month: Int, cal: Calendar,
                                          hms: DateComponents, fallbackDay: Int) -> [Date] {
        var firstComps = DateComponents(); firstComps.year = year; firstComps.month = month; firstComps.day = 1
        guard let firstOfMonth = cal.date(from: firstComps),
              let dim = daysInMonth(firstOfMonth, cal) else { return [] }
        var days: [Int] = []

        if !r.byDay.isEmpty {
            for bd in r.byDay {
                let matching = (1...dim).filter { day -> Bool in
                    var c = DateComponents(); c.year = year; c.month = month; c.day = day
                    return cal.date(from: c).map { cal.component(.weekday, from: $0) == bd.weekday } ?? false
                }
                if let ord = bd.ordinal {
                    let idx = ord > 0 ? ord - 1 : matching.count + ord
                    if matching.indices.contains(idx) { days.append(matching[idx]) }
                } else {
                    days += matching
                }
            }
        } else if !r.byMonthDay.isEmpty {
            for md in r.byMonthDay {
                let day = md > 0 ? md : dim + md + 1
                if (1...dim).contains(day) { days.append(day) }
            }
        } else {
            if (1...dim).contains(fallbackDay) { days.append(fallbackDay) }
        }

        return days.sorted().compactMap { day -> Date? in
            var c = hms; c.year = year; c.month = month; c.day = day
            return cal.date(from: c)
        }
    }

    // MARK: small date helpers

    private static func applySetPos(_ sorted: [Date], _ positions: [Int]) -> [Date] {
        var picked: [Date] = []
        for p in positions {
            let idx = p > 0 ? p - 1 : sorted.count + p
            if sorted.indices.contains(idx) { picked.append(sorted[idx]) }
        }
        return picked.sorted()
    }

    private static func matchesMonthDay(_ day: Int, _ list: [Int], _ dim: Int) -> Bool {
        list.contains { $0 > 0 ? $0 == day : dim + $0 + 1 == day }
    }

    private static func daysInMonth(_ date: Date, _ cal: Calendar) -> Int? {
        cal.range(of: .day, in: .month, for: date)?.count
    }

    private static func startOfWeek(_ date: Date, cal: Calendar) -> Date? {
        cal.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: date).date
    }

    private static func setTime(_ hms: DateComponents, on day: Date, cal: Calendar) -> Date? {
        var c = cal.dateComponents([.year, .month, .day], from: day)
        c.hour = hms.hour; c.minute = hms.minute; c.second = hms.second
        return cal.date(from: c)
    }
}
