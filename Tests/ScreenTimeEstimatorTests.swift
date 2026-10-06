import XCTest

/// Auto mode: Screen Time minute marks → estimated reels, including the
/// duplicate / late / premature callbacks iOS really produces.
final class ScreenTimeEstimatorTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 6) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    private func key(day: Int = 6) -> DayKey { DayKey(date(12, 0, day: day), calendar: calendar) }

    @discardableResult
    private func apply(
        _ minutes: Int,
        at time: Date,
        to state: inout ScreenTimeState,
        slot: ScreenTimeSlot = .instagram,
        pace: Double = 4,
        precise: Bool = false,
        openedAt: Date? = nil
    ) -> ScreenTimeEstimator.Outcome {
        ScreenTimeEstimator.apply(
            .init(slot: slot, threshold: minutes, at: time, openedAt: openedAt),
            to: &state, pace: pace, preciseActive: precise, calendar: calendar
        )
    }

    func testMinutesBecomeReelsAtThePace() {
        var state = ScreenTimeState()
        for minute in 1...10 { apply(minute, at: date(14, minute), to: &state) }
        let day = state[key()]
        XCTAssertEqual(day?.minutes["instagram"], 10)
        XCTAssertEqual(day?.totalEstimated, 40)
        XCTAssertEqual(day?.sessions, 1)
        XCTAssertEqual(state.session.map { Int($0.reels) }, 40)
    }

    func testDuplicateCallbacksAreIgnored() {
        var state = ScreenTimeState()
        XCTAssertEqual(apply(1, at: date(14, 1), to: &state), .accepted(delta: 1, sessionStarted: true))
        XCTAssertEqual(apply(1, at: date(14, 1, 2), to: &state), .duplicate)
        XCTAssertEqual(state[key()]?.minutes["instagram"], 1)
    }

    func testPrematureBurstIsRejectedAndAsksForRearm() {
        var state = ScreenTimeState()
        ScreenTimeEstimator.register(.instagram, at: date(13, 30), in: &state, calendar: calendar)
        // The iOS bug: thresholds fire all at once right after monitoring starts.
        for minutes in [5, 10, 30, 60, 120] {
            XCTAssertEqual(apply(minutes, at: date(13, 30, 5), to: &state), .rejected(.premature))
        }
        XCTAssertNil(state[key()]?.minutes["instagram"])
        XCTAssertNotNil(state.needsRearmSince)

        // Re-registering clears the flag.
        ScreenTimeEstimator.register(.instagram, at: date(13, 31), in: &state, calendar: calendar)
        XCTAssertNil(state.needsRearmSince)
    }

    func testThresholdsCountFromRegistrationOnThatDay() {
        var state = ScreenTimeState()
        for minute in 1...50 { apply(minute, at: date(9, minute), to: &state) }
        ScreenTimeEstimator.register(.instagram, at: date(13, 30), in: &state, calendar: calendar)
        // The re-registered ladder starts at 1 again, on top of this morning's 50.
        XCTAssertEqual(apply(1, at: date(13, 31, 10), to: &state), .accepted(delta: 1, sessionStarted: true))
        XCTAssertEqual(state[key()]?.minutes["instagram"], 51)
    }

    func testLateEventsFromAnOldRegistrationAreRejected() {
        var state = ScreenTimeState()
        for minute in 1...20 { apply(minute, at: date(9, minute), to: &state) }
        ScreenTimeEstimator.register(.instagram, at: date(9, 30), in: &state, calendar: calendar)
        // "ig.21" from the previous ladder shows up after re-registering.
        XCTAssertEqual(apply(21, at: date(9, 30, 3), to: &state), .rejected(.premature))
        XCTAssertEqual(state[key()]?.minutes["instagram"], 20)
    }

    func testGrowthCantOutrunTheClock() {
        var state = ScreenTimeState()
        apply(5, at: date(10, 5), to: &state)
        apply(40, at: date(10, 7), to: &state)
        XCTAssertEqual(state[key()]?.minutes["instagram"], 8, "5 + 2 elapsed minutes + 1 slack")
    }

    func testPreciseModeMinutesAreCoveredNotEstimated() {
        var state = ScreenTimeState()
        for minute in 1...5 { apply(minute, at: date(10, minute), to: &state, precise: true) }
        let day = state[key()]
        XCTAssertEqual(day?.minutes["instagram"], 5)
        XCTAssertEqual(day?.coveredMinutes["instagram"], 5)
        XCTAssertEqual(day?.totalEstimated, 0)
        XCTAssertEqual(day?.sessions, 0, "precise mode counts its own sessions")
    }

    func testNewSessionAfterAGap() {
        var state = ScreenTimeState()
        for minute in 1...3 { apply(minute, at: date(10, minute), to: &state) }
        XCTAssertEqual(apply(4, at: date(10, 30), to: &state), .accepted(delta: 1, sessionStarted: true))
        XCTAssertEqual(state[key()]?.sessions, 2)
        XCTAssertEqual(state.session?.minutes, 1)
    }

    func testSessionStartsWhenTheAutomationSawTheAppOpen() {
        var state = ScreenTimeState()
        apply(1, at: date(10, 5), to: &state, openedAt: date(10, 3, 30))
        XCTAssertEqual(state.session?.startedAt, date(10, 3, 30))
    }

    func testEndSessionNeedsIdleTime() {
        var state = ScreenTimeState()
        apply(1, at: date(10, 1), to: &state)
        XCTAssertNil(ScreenTimeEstimator.endSession(in: &state, at: date(10, 2)))
        XCTAssertNotNil(ScreenTimeEstimator.endSession(in: &state, at: date(10, 4)))
        XCTAssertNil(state.session)
    }

    func testNextDayCountsFromMidnight() {
        var state = ScreenTimeState()
        ScreenTimeEstimator.register(.instagram, at: date(13, 30), in: &state, calendar: calendar)
        XCTAssertEqual(apply(15, at: date(0, 20, day: 7), to: &state), .accepted(delta: 15, sessionStarted: true))
        XCTAssertEqual(state[key(day: 7)]?.minutes["instagram"], 15)
    }

    func testAppsAreTrackedSeparately() {
        var state = ScreenTimeState()
        apply(1, at: date(10, 1), to: &state, slot: .instagram, pace: 4)
        apply(1, at: date(10, 2), to: &state, slot: .tiktok, pace: 6)
        let day = state[key()]
        XCTAssertEqual(day?.minutes, ["instagram": 1, "tiktok": 1])
        XCTAssertEqual(day?.totalEstimated, 10)
    }

    func testMergeAddsTheEstimateToExactCounts() {
        var exact = DayRecord(day: key())
        exact.total = 10
        exact.perApp = ["instagram": 10]
        var day = ScreenTimeDay(day: key())
        day.minutes = ["instagram": 12]
        day.coveredMinutes = ["instagram": 2]
        day.estimatedReels = ["instagram": 41.6]
        day.hourlyReels[14] = 41.6
        let merged = day.merged(into: exact)
        XCTAssertEqual(merged.total, 52)
        XCTAssertEqual(merged.estimatedReels, 42)
        XCTAssertEqual(merged.count(for: .instagram), 52)
        XCTAssertEqual(merged.screenMinutes, 12)
        XCTAssertEqual(merged.hourly[14], 42)
        XCTAssertEqual(merged.watchSeconds, 600, "only uncovered minutes add watch time")
        XCTAssertTrue(merged.isEstimated)
    }

    func testCalibrationBlendsTheMeasuredPace() {
        XCTAssertNil(ScreenTimeEstimator.calibratedPace(previous: nil, exactReels: 30, coveredMinutes: 5), "too little data")
        XCTAssertNil(ScreenTimeEstimator.calibratedPace(previous: nil, exactReels: 900, coveredMinutes: 10), "implausible")
        XCTAssertEqual(ScreenTimeEstimator.calibratedPace(previous: nil, exactReels: 60, coveredMinutes: 10), 6)
        XCTAssertEqual(ScreenTimeEstimator.calibratedPace(previous: 4, exactReels: 60, coveredMinutes: 10) ?? 0, 4.8, accuracy: 0.0001)
    }

    func testLadderNamesRoundTrip() {
        let thresholds = ScreenTimeLadder.thresholds
        XCTAssertEqual(thresholds.first, 1)
        XCTAssertEqual(thresholds.last, 960)
        XCTAssertEqual(thresholds, thresholds.sorted())
        XCTAssertEqual(Set(thresholds).count, thresholds.count)
        for slot in ScreenTimeSlot.allCases {
            for minutes in thresholds {
                let parsed = ScreenTimeLadder.parse(ScreenTimeLadder.eventName(slot: slot, minutes: minutes))
                XCTAssertEqual(parsed?.slot, slot)
                XCTAssertEqual(parsed?.minutes, minutes)
            }
        }
        XCTAssertNil(ScreenTimeLadder.parse("xx.5"))
        XCTAssertNil(ScreenTimeLadder.parse("ig.0"))
        XCTAssertNil(ScreenTimeLadder.parse("ig"))
    }

    func testStateDecodesFromOlderJSON() throws {
        let json = #"{"days":{"2026-10-06":{"day":"2026-10-06","minutes":{"instagram":3}}}}"#
        let state = try JSONCoding.decoder.decode(ScreenTimeState.self, from: Data(json.utf8))
        XCTAssertEqual(state[key()]?.minutes["instagram"], 3)
        XCTAssertEqual(state[key()]?.hourlyReels.count, 24)
    }
}
