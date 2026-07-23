import XCTest
@testable import Muninn

final class PomodoroEngineTests: XCTestCase {

    private func cfg(every: Int = 4, auto: Bool = true) -> PomodoroConfig {
        PomodoroConfig(focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, longBreakEvery: every, autoStartNext: auto)
    }

    // MARK: pure transition rule

    func testFocusGoesToShortBreakThenBackToFocus() {
        let c = cfg()
        XCTAssertEqual(Pomodoro.next(after: .focus, completedFocus: 1, config: c), .shortBreak)
        XCTAssertEqual(Pomodoro.next(after: .shortBreak, completedFocus: 1, config: c), .focus)
    }

    func testLongBreakEveryFourthFocus() {
        let c = cfg(every: 4)
        XCTAssertEqual(Pomodoro.next(after: .focus, completedFocus: 4, config: c), .longBreak)
        XCTAssertEqual(Pomodoro.next(after: .focus, completedFocus: 8, config: c), .longBreak)
        XCTAssertEqual(Pomodoro.next(after: .focus, completedFocus: 3, config: c), .shortBreak)
        XCTAssertEqual(Pomodoro.next(after: .longBreak, completedFocus: 4, config: c), .focus)
    }

    // MARK: engine

    func testTickCountsDownAndCompletes() {
        var c = cfg(); c.focusMinutes = 1                    // 60s
        let e = PomodoroEngine(config: c)
        e.start()
        for _ in 0..<59 { XCTAssertNil(e.tick()) }
        XCTAssertEqual(e.remaining, 1)
        let ended = e.tick()
        XCTAssertEqual(ended, .focus)                        // this tick finished focus
        XCTAssertEqual(e.phase, .shortBreak)
        XCTAssertEqual(e.completedFocus, 1)
        XCTAssertEqual(e.remaining, 5 * 60)                  // short break duration
    }

    func testPausedEngineDoesNotTick() {
        let e = PomodoroEngine(config: cfg())
        let before = e.remaining
        XCTAssertNil(e.tick())                               // not started
        XCTAssertEqual(e.remaining, before)
    }

    func testFullCycleReachesLongBreak() {
        var c = cfg(every: 2); c.focusMinutes = 1; c.shortBreakMinutes = 1; c.longBreakMinutes = 1
        let e = PomodoroEngine(config: c)
        e.start()
        XCTAssertEqual(e.skip(), .focus);      XCTAssertEqual(e.phase, .shortBreak)  // 1st focus done
        XCTAssertEqual(e.skip(), .shortBreak); XCTAssertEqual(e.phase, .focus)
        XCTAssertEqual(e.skip(), .focus);      XCTAssertEqual(e.phase, .longBreak)   // 2nd focus → long
    }

    func testApplyConfigUpdatesIdleDuration() {
        let e = PomodoroEngine(config: cfg())
        XCTAssertEqual(e.remaining, 25 * 60)
        var c = cfg(); c.focusMinutes = 50
        e.apply(c)
        XCTAssertEqual(e.remaining, 50 * 60)                 // idle at full duration → reflects new length
    }

    func testResetReturnsToFirstFocus() {
        var c = cfg(); c.focusMinutes = 1
        let e = PomodoroEngine(config: c)
        e.start(); _ = e.skip(); _ = e.skip()
        e.reset()
        XCTAssertEqual(e.phase, .focus)
        XCTAssertEqual(e.completedFocus, 0)
        XCTAssertFalse(e.isRunning)
        XCTAssertEqual(e.remaining, 60)
    }
}
