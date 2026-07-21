import Foundation

// MARK: - Model

/// A wall-clock date/time plus the time zone it should be interpreted in. All-day events
/// are date-only (time components zero, `isAllDay == true`).
struct EventDate: Equatable {
    var components: DateComponents   // year…second (wall clock)
    var timeZone: TimeZone
    var isAllDay: Bool

    /// The absolute instant this wall-clock time denotes in its zone.
    func absolute() -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: components)
    }
}

enum Freq: String { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

/// One `BYDAY` token: an optional ordinal (`2MO` → 2, `-1FR` → -1) and a weekday
/// (Gregorian numbering, Sun = 1 … Sat = 7).
struct ByDay: Equatable { var ordinal: Int?; var weekday: Int }

/// A parsed `RRULE`.
struct RRule: Equatable {
    var freq: Freq
    var interval: Int = 1
    var count: Int?
    var until: Date?          // absolute instant
    var byDay: [ByDay] = []
    var byMonthDay: [Int] = []
    var byMonth: [Int] = []
    var bySetPos: [Int] = []
    var wkst: Int = 2         // Gregorian weekday; Monday default
}

/// A parsed VEVENT (recurrence unexpanded).
struct VEvent {
    /// Which configured Live Calendar this came from (stamped by `CalendarFeed`).
    var calendarId: UUID?
    var uid: String = ""
    var summary: String = ""
    var location: String?
    var descriptionText: String?
    var url: String?
    /// Raw strings that may carry a video-call link (CONFERENCE / X-*-CONFERENCE values, etc.).
    var conferenceHints: [String] = []
    var start: EventDate
    var end: EventDate?
    var rrule: RRule?
    var exdates: [EventDate] = []
    var rdates: [EventDate] = []
}

// MARK: - ICS parsing

/// A minimal, dependency-free RFC 5545 reader: line unfolding, property/param parsing, and
/// VEVENT extraction. Time zones are resolved through Foundation's `TimeZone` (IANA tz
/// database) from the `TZID` — this sidesteps parsing VTIMEZONE offset rules, which is correct
/// in practice because feeds (Proton included) use IANA zone names.
enum ICSParser {
    /// One physical line: property name, params, and the raw value.
    private struct Line { var name: String; var params: [(String, String)]; var value: String }

    static func parse(_ text: String, defaultTimeZone: TimeZone = .current) -> [VEvent] {
        let lines = unfold(text)
        var events: [VEvent] = []
        var cur: PartialEvent?
        for raw in lines {
            guard let line = splitLine(raw) else { continue }
            switch line.name.uppercased() {
            case "BEGIN" where line.value.uppercased() == "VEVENT":
                cur = PartialEvent()
            case "END" where line.value.uppercased() == "VEVENT":
                if let e = cur?.build(defaultTimeZone: defaultTimeZone) { events.append(e) }
                cur = nil
            default:
                cur?.apply(line, defaultTimeZone: defaultTimeZone)
            }
        }
        return events
    }

    /// Under construction between BEGIN:VEVENT … END:VEVENT.
    private struct PartialEvent {
        var uid = "", summary = ""
        var location: String?, descriptionText: String?, url: String?
        var conferenceHints: [String] = []
        var start: EventDate?, end: EventDate?
        var rrule: RRule?
        var exdates: [EventDate] = [], rdates: [EventDate] = []

        mutating func apply(_ line: Line, defaultTimeZone: TimeZone) {
            let name = line.name.uppercased()
            let val = Self.unescapeText(line.value)
            switch name {
            case "UID":         uid = line.value
            case "SUMMARY":     summary = val
            case "LOCATION":    location = val
            case "DESCRIPTION": descriptionText = val
            case "URL":         url = line.value
            case "DTSTART":     start = Self.parseDate(line, defaultTimeZone: defaultTimeZone)
            case "DTEND":       end = Self.parseDate(line, defaultTimeZone: defaultTimeZone)
            case "DURATION":    pendingDuration = line.value
            case "RRULE":       rrule = ICSParser.parseRRule(line.value, defaultTimeZone: defaultTimeZone)
            case "EXDATE":      exdates += Self.parseDateList(line, defaultTimeZone: defaultTimeZone)
            case "RDATE":       rdates += Self.parseDateList(line, defaultTimeZone: defaultTimeZone)
            case "CONFERENCE", "X-GOOGLE-CONFERENCE", "X-MICROSOFT-SKYPETEAMSMEETINGURL":
                conferenceHints.append(line.value)
            default:
                if name.contains("CONFERENCE") || name.hasPrefix("X-") && line.value.contains("http") {
                    conferenceHints.append(line.value)
                }
            }
        }
        var pendingDuration: String?

        func build(defaultTimeZone: TimeZone) -> VEvent? {
            guard let start else { return nil }
            var end = self.end
            if end == nil, let dur = pendingDuration, let secs = ICSParser.parseDuration(dur),
               let base = start.absolute() {
                var cal = Calendar(identifier: .gregorian); cal.timeZone = start.timeZone
                let endDate = base.addingTimeInterval(secs)
                end = EventDate(components: cal.dateComponents([.year,.month,.day,.hour,.minute,.second], from: endDate),
                                timeZone: start.timeZone, isAllDay: start.isAllDay)
            }
            return VEvent(uid: uid, summary: summary, location: location, descriptionText: descriptionText,
                          url: url, conferenceHints: conferenceHints, start: start, end: end,
                          rrule: rrule, exdates: exdates, rdates: rdates)
        }

        // Escaped-text unescape (RFC 5545 §3.3.11): \n \, \; \\.
        static func unescapeText(_ s: String) -> String {
            s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
             .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
             .replacingOccurrences(of: "\\\\", with: "\\")
        }

        static func parseDate(_ line: Line, defaultTimeZone: TimeZone) -> EventDate? {
            parseOneDate(value: line.value, params: line.params, defaultTimeZone: defaultTimeZone)
        }
        static func parseDateList(_ line: Line, defaultTimeZone: TimeZone) -> [EventDate] {
            line.value.split(separator: ",").compactMap {
                parseOneDate(value: String($0), params: line.params, defaultTimeZone: defaultTimeZone)
            }
        }

        static func parseOneDate(value: String, params: [(String, String)], defaultTimeZone: TimeZone) -> EventDate? {
            let param = { (k: String) -> String? in params.first { $0.0.uppercased() == k }?.1 }
            let isDate = param("VALUE")?.uppercased() == "DATE" || (!value.contains("T"))
            var tz = defaultTimeZone
            if value.hasSuffix("Z") { tz = TimeZone(identifier: "UTC")! }
            else if let tzid = param("TZID"), let t = TimeZone(identifier: tzid) { tz = t }
            guard let comps = ICSParser.dateComponents(from: value, allDay: isDate) else { return nil }
            return EventDate(components: comps, timeZone: tz, isAllDay: isDate)
        }
    }

    // MARK: line handling

    /// Join continuation lines (a line starting with a space or tab continues the previous one).
    private static func unfold(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t" {
                if !out.isEmpty { out[out.count - 1] += raw.dropFirst() }
            } else {
                out.append(String(raw))
            }
        }
        return out
    }

    /// Split `NAME;PARAM=VAL;PARAM="v:v":VALUE` into name, params, and value (first unquoted colon).
    private static func splitLine(_ s: String) -> Line? {
        var name = "", value = ""
        var params: [(String, String)] = []
        var inQuote = false
        var idx = s.startIndex
        // name / params section ends at the first unquoted ':'
        var head = ""
        while idx < s.endIndex {
            let c = s[idx]
            if c == "\"" { inQuote.toggle() }
            if c == ":" && !inQuote { value = String(s[s.index(after: idx)...]); break }
            head.append(c); idx = s.index(after: idx)
        }
        if value.isEmpty && !s.contains(":") { return nil }
        // head = NAME;PARAM=..;PARAM=..
        let parts = splitUnquoted(head, on: ";")
        guard let n = parts.first else { return nil }
        name = n
        for p in parts.dropFirst() {
            let kv = splitUnquoted(p, on: "=")
            if kv.count == 2 { params.append((kv[0], kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")))) }
        }
        return Line(name: name, params: params, value: value)
    }

    private static func splitUnquoted(_ s: String, on sep: Character) -> [String] {
        var out: [String] = [], cur = "", inQuote = false
        for c in s {
            if c == "\"" { inQuote.toggle(); cur.append(c); continue }
            if c == sep && !inQuote { out.append(cur); cur = "" } else { cur.append(c) }
        }
        out.append(cur); return out
    }

    // MARK: value parsers

    /// `20260721` or `20260721T090000` (optionally trailing `Z`) → wall-clock components.
    static func dateComponents(from raw: String, allDay: Bool) -> DateComponents? {
        let s = raw.hasSuffix("Z") ? String(raw.dropLast()) : raw
        func intAt(_ str: Substring, _ lo: Int, _ len: Int) -> Int? {
            let a = str.index(str.startIndex, offsetBy: lo, limitedBy: str.endIndex)
            guard let a, let b = str.index(a, offsetBy: len, limitedBy: str.endIndex) else { return nil }
            return Int(str[a..<b])
        }
        let ss = Substring(s)
        guard let y = intAt(ss, 0, 4), let m = intAt(ss, 4, 2), let d = intAt(ss, 6, 2) else { return nil }
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        if allDay { c.hour = 0; c.minute = 0; c.second = 0; return c }
        // time part after 'T'
        guard let tPos = s.firstIndex(of: "T") else { c.hour = 0; c.minute = 0; c.second = 0; return c }
        let t = s[s.index(after: tPos)...]
        c.hour = intAt(t, 0, 2) ?? 0; c.minute = intAt(t, 2, 2) ?? 0; c.second = intAt(t, 4, 2) ?? 0
        return c
    }

    static func parseRRule(_ value: String, defaultTimeZone: TimeZone) -> RRule? {
        var map: [String: String] = [:]
        for pair in value.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { map[kv[0].uppercased()] = String(kv[1]) }
        }
        guard let freqRaw = map["FREQ"], let freq = Freq(rawValue: freqRaw.uppercased()) else { return nil }
        var r = RRule(freq: freq)
        if let i = map["INTERVAL"], let v = Int(i), v > 0 { r.interval = v }
        if let c = map["COUNT"], let v = Int(c) { r.count = v }
        if let u = map["UNTIL"] {
            let allDay = !u.contains("T")
            if let comps = dateComponents(from: u, allDay: allDay) {
                let tz = u.hasSuffix("Z") ? TimeZone(identifier: "UTC")! : defaultTimeZone
                var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
                r.until = cal.date(from: comps)
            }
        }
        if let b = map["BYDAY"] { r.byDay = b.split(separator: ",").compactMap(parseByDay) }
        if let b = map["BYMONTHDAY"] { r.byMonthDay = b.split(separator: ",").compactMap { Int($0) } }
        if let b = map["BYMONTH"] { r.byMonth = b.split(separator: ",").compactMap { Int($0) } }
        if let b = map["BYSETPOS"] { r.bySetPos = b.split(separator: ",").compactMap { Int($0) } }
        if let w = map["WKST"] { r.wkst = weekdayNumber(String(w)) ?? 2 }
        return r
    }

    private static func parseByDay(_ token: Substring) -> ByDay? {
        let s = String(token)
        let dayCode = String(s.suffix(2)).uppercased()
        guard let wd = weekdayNumber(dayCode) else { return nil }
        let ordPart = String(s.dropLast(2))
        let ordinal = ordPart.isEmpty ? nil : Int(ordPart)
        return ByDay(ordinal: ordinal, weekday: wd)
    }

    /// SU=1 … SA=7 (Gregorian).
    static func weekdayNumber(_ code: String) -> Int? {
        ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7][code.uppercased()]
    }

    /// RFC 5545 DURATION → seconds (e.g. `PT1H`, `P1DT2H30M`, `-PT15M`).
    static func parseDuration(_ s: String) -> TimeInterval? {
        var str = Substring(s), sign = 1.0
        if str.first == "-" { sign = -1; str = str.dropFirst() } else if str.first == "+" { str = str.dropFirst() }
        guard str.first == "P" else { return nil }
        str = str.dropFirst()
        var total = 0.0, inTime = false, num = ""
        for ch in str {
            switch ch {
            case "T": inTime = true
            case "0"..."9": num.append(ch)
            default:
                guard let n = Double(num) else { return nil }
                num = ""
                switch ch {
                case "W": total += n * 604800
                case "D": total += n * 86400
                case "H": total += n * 3600
                case "M": total += inTime ? n * 60 : n * 2_592_000
                case "S": total += n
                default: return nil
                }
            }
        }
        return sign * total
    }
}

// MARK: - Join-link extraction

/// Finds a video-call join URL in an event (CONFERENCE fields, URL, LOCATION, DESCRIPTION).
enum JoinLink {
    private static let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com",
                                "meet.proton.me", "whereby.com", "webex.com"]

    static func extract(from e: VEvent) -> URL? {
        let haystacks = e.conferenceHints + [e.url, e.location, e.descriptionText].compactMap { $0 }
        for h in haystacks {
            for url in urls(in: h) where hosts.contains(where: { url.host?.contains($0) == true }) {
                return url
            }
        }
        return nil
    }

    private static func urls(in text: String) -> [URL] {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return det.matches(in: text, range: range).compactMap { $0.url }
    }
}
