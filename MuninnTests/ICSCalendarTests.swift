import XCTest
@testable import Muninn

/// live-calendars Group 2: the pure ICS parser + RFC 5545 recurrence + join-link extraction,
/// exercised from inline `.ics` fixtures (no network, no GUI).
final class ICSCalendarTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    /// An absolute Date from wall-clock parts in a zone.
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0,
                      tz: String = "UTC") -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: 0))!
    }

    private func wrap(_ body: String) -> String {
        "BEGIN:VCALENDAR\nVERSION:2.0\n\(body)\nEND:VCALENDAR"
    }

    private func starts(_ ics: String, _ from: Date, _ to: Date) -> [Date] {
        let events = ICSParser.parse(wrap(ics), defaultTimeZone: utc)
        return events.flatMap { Recurrence.occurrences(of: $0, windowStart: from, windowEnd: to) }
            .map { $0.start }.sorted()
    }

    // MARK: parsing

    func testParsesSingleEvent() {
        let events = ICSParser.parse(wrap("""
        BEGIN:VEVENT
        UID:a
        SUMMARY:Solo meeting
        DTSTART:20260722T090000Z
        DTEND:20260722T100000Z
        END:VEVENT
        """), defaultTimeZone: utc)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].summary, "Solo meeting")
        XCTAssertEqual(events[0].start.absolute(), date(2026, 7, 22, 9))
        XCTAssertEqual(events[0].end?.absolute(), date(2026, 7, 22, 10))
    }

    func testLineUnfoldingAndEscaping() {
        // Built explicitly so the fold is exactly one leading space (RFC 5545 §3.1) — a folded
        // value rejoins with no inserted whitespace.
        let ics = "BEGIN:VEVENT\nUID:b\nSUMMARY:Long\\, wrapped\n"
            + "DESCRIPTION:first line\n continued here\nDTSTART:20260722T090000Z\nEND:VEVENT"
        let events = ICSParser.parse(wrap(ics), defaultTimeZone: utc)
        XCTAssertEqual(events.first?.summary, "Long, wrapped")
        XCTAssertEqual(events.first?.descriptionText, "first linecontinued here")
    }

    func testTZIDResolvesToAbsoluteInstant() {
        // 09:00 America/New_York on 2026-07-22 (EDT, -4) == 13:00 UTC.
        let events = ICSParser.parse(wrap("""
        BEGIN:VEVENT
        UID:c
        DTSTART;TZID=America/New_York:20260722T090000
        DTEND;TZID=America/New_York:20260722T100000
        END:VEVENT
        """), defaultTimeZone: utc)
        XCTAssertEqual(events.first?.start.absolute(), date(2026, 7, 22, 13))
    }

    func testAllDayEvent() {
        let events = ICSParser.parse(wrap("""
        BEGIN:VEVENT
        UID:d
        DTSTART;VALUE=DATE:20260722
        END:VEVENT
        """), defaultTimeZone: utc)
        XCTAssertEqual(events.first?.start.isAllDay, true)
        let occ = Recurrence.occurrences(of: events[0], windowStart: date(2026, 7, 1), windowEnd: date(2026, 8, 1))
        XCTAssertEqual(occ.count, 1)
        XCTAssertEqual(occ[0].end.timeIntervalSince(occ[0].start), 86400) // all-day → 24h
    }

    func testDurationInsteadOfDtend() {
        let events = ICSParser.parse(wrap("""
        BEGIN:VEVENT
        UID:e
        DTSTART:20260722T090000Z
        DURATION:PT1H30M
        END:VEVENT
        """), defaultTimeZone: utc)
        XCTAssertEqual(events.first?.end?.absolute(), date(2026, 7, 22, 10, 30))
    }

    // MARK: recurrence

    func testDailyIntervalUntil() {
        // Jul 1,3,5,7,9 (INTERVAL=2, UNTIL inclusive).
        let s = starts("""
        BEGIN:VEVENT
        UID:f
        DTSTART:20260701T120000Z
        RRULE:FREQ=DAILY;INTERVAL=2;UNTIL=20260709T120000Z
        END:VEVENT
        """, date(2026, 6, 1), date(2026, 8, 1))
        XCTAssertEqual(s, [date(2026,7,1,12), date(2026,7,3,12), date(2026,7,5,12), date(2026,7,7,12), date(2026,7,9,12)])
    }

    func testWeeklyByDayCount() {
        // From Mon 2026-07-06: MO/WE/FR × 6 → Jul 6,8,10,13,15,17.
        let s = starts("""
        BEGIN:VEVENT
        UID:g
        DTSTART:20260706T090000Z
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=6
        END:VEVENT
        """, date(2026, 7, 1), date(2026, 8, 1))
        XCTAssertEqual(s, [date(2026,7,6,9), date(2026,7,8,9), date(2026,7,10,9),
                           date(2026,7,13,9), date(2026,7,15,9), date(2026,7,17,9)])
    }

    func testMonthlyByMonthDay() {
        let s = starts("""
        BEGIN:VEVENT
        UID:h
        DTSTART:20260115T090000Z
        RRULE:FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3
        END:VEVENT
        """, date(2026, 1, 1), date(2026, 12, 1))
        XCTAssertEqual(s, [date(2026,1,15,9), date(2026,2,15,9), date(2026,3,15,9)])
    }

    func testMonthlyLastFriday() {
        // BYDAY=-1FR from last Fri of Jan 2026 (Jan 30) → Jan 30, Feb 27, Mar 27.
        let s = starts("""
        BEGIN:VEVENT
        UID:i
        DTSTART:20260130T090000Z
        RRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=3
        END:VEVENT
        """, date(2026, 1, 1), date(2026, 5, 1))
        XCTAssertEqual(s, [date(2026,1,30,9), date(2026,2,27,9), date(2026,3,27,9)])
    }

    func testMonthlyBySetPosLastWeekday() {
        // Last weekday of the month (Mon–Fri, BYSETPOS=-1) from Jan 30 2026 (Fri) → Jan 30, Feb 27.
        let s = starts("""
        BEGIN:VEVENT
        UID:j
        DTSTART:20260130T090000Z
        RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=2
        END:VEVENT
        """, date(2026, 1, 1), date(2026, 4, 1))
        XCTAssertEqual(s, [date(2026,1,30,9), date(2026,2,27,9)])
    }

    func testExdateSkips() {
        // DAILY COUNT=4 (Jul 1,2,3,4) minus EXDATE Jul 2 → Jul 1,3,4.
        let s = starts("""
        BEGIN:VEVENT
        UID:k
        DTSTART:20260701T090000Z
        RRULE:FREQ=DAILY;COUNT=4
        EXDATE:20260702T090000Z
        END:VEVENT
        """, date(2026, 6, 1), date(2026, 8, 1))
        XCTAssertEqual(s, [date(2026,7,1,9), date(2026,7,3,9), date(2026,7,4,9)])
    }

    func testRdateAdds() {
        let s = starts("""
        BEGIN:VEVENT
        UID:l
        DTSTART:20260701T090000Z
        RDATE:20260705T090000Z
        END:VEVENT
        """, date(2026, 6, 1), date(2026, 8, 1))
        XCTAssertEqual(s, [date(2026,7,1,9), date(2026,7,5,9)])
    }

    func testWindowClipsRecurring() {
        // Infinite daily; window picks only the days inside it.
        let s = starts("""
        BEGIN:VEVENT
        UID:m
        DTSTART:20260101T090000Z
        RRULE:FREQ=DAILY
        END:VEVENT
        """, date(2026, 7, 10, 0), date(2026, 7, 13, 0))
        XCTAssertEqual(s, [date(2026,7,10,9), date(2026,7,11,9), date(2026,7,12,9)])
    }

    // MARK: next occurrence

    func testNextOccurrencePicksSoonestFuture() {
        let events = ICSParser.parse(wrap("""
        BEGIN:VEVENT
        UID:n1
        SUMMARY:Later
        DTSTART:20260722T150000Z
        DTEND:20260722T160000Z
        END:VEVENT
        BEGIN:VEVENT
        UID:n2
        SUMMARY:Sooner
        DTSTART:20260722T110000Z
        DTEND:20260722T120000Z
        END:VEVENT
        """), defaultTimeZone: utc)
        let next = Recurrence.nextOccurrence(in: events, now: date(2026, 7, 22, 10))
        XCTAssertEqual(next?.title, "Sooner")
        XCTAssertEqual(next?.start, date(2026, 7, 22, 11))
    }

    func testOngoingEventCountsAsNext() {
        let events = ICSParser.parse(wrap("""
        BEGIN:VEVENT
        UID:o
        SUMMARY:In progress
        DTSTART:20260722T100000Z
        DTEND:20260722T110000Z
        END:VEVENT
        """), defaultTimeZone: utc)
        // now is inside the event → still "next" (so Join stays available).
        let next = Recurrence.nextOccurrence(in: events, now: date(2026, 7, 22, 10, 30))
        XCTAssertEqual(next?.title, "In progress")
    }

    func testPastEventIsNotNext() {
        let events = ICSParser.parse(wrap("""
        BEGIN:VEVENT
        UID:p
        DTSTART:20260722T080000Z
        DTEND:20260722T090000Z
        END:VEVENT
        """), defaultTimeZone: utc)
        XCTAssertNil(Recurrence.nextOccurrence(in: events, now: date(2026, 7, 22, 10)))
    }

    // MARK: join links

    func testJoinLinkFromDescription() {
        let events = ICSParser.parse(wrap("""
        BEGIN:VEVENT
        UID:q
        DTSTART:20260722T090000Z
        DESCRIPTION:Dial in here https://us02web.zoom.us/j/123456789 see you
        END:VEVENT
        """), defaultTimeZone: utc)
        XCTAssertEqual(JoinLink.extract(from: events[0])?.absoluteString, "https://us02web.zoom.us/j/123456789")
    }

    func testJoinLinkFromConferenceField() {
        let events = ICSParser.parse(wrap("""
        BEGIN:VEVENT
        UID:r
        DTSTART:20260722T090000Z
        X-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij
        END:VEVENT
        """), defaultTimeZone: utc)
        XCTAssertEqual(JoinLink.extract(from: events[0])?.host, "meet.google.com")
    }

    func testNoJoinLink() {
        let events = ICSParser.parse(wrap("""
        BEGIN:VEVENT
        UID:s
        DTSTART:20260722T090000Z
        LOCATION:Room 3B
        END:VEVENT
        """), defaultTimeZone: utc)
        XCTAssertNil(JoinLink.extract(from: events[0]))
    }
}
