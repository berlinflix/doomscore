import XCTest

final class StatsEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func ledger(_ totals: [(Date, Int)]) -> Ledger {
        var ledger = Ledger()
        for (day, total) in totals {
            var record = DayRecord(day: DayKey(day, calendar: calendar))
            record.total = total
            record.perApp = ["instagram": total]
            record.hourly[23] = total
            record.watchSeconds = Double(total) * 20
            ledger[record.day] = record
        }
        return ledger
    }

    func testStreakCountsDaysUnderCapIncludingEmptyDays() {
        let now = date(2026, 9, 30)
        let data = ledger([
            (date(2026, 9, 25), 250), // over cap → breaks
            (date(2026, 9, 26), 40),
            // 27th: no data → counts as clean
            (date(2026, 9, 28), 90),
            (date(2026, 9, 29), 100),
            (date(2026, 9, 30), 12),
        ])
        let streak = StatsEngine.streak(ledger: data, goal: 100, installDate: date(2026, 9, 20), calendar: calendar, now: now)
        XCTAssertEqual(streak.current, 5)
        XCTAssertTrue(streak.todayAlive)
        XCTAssertGreaterThanOrEqual(streak.best, 5)
    }

    func testStreakBreaksWhenTodayIsOverCap() {
        let now = date(2026, 9, 30)
        let data = ledger([(date(2026, 9, 29), 10), (date(2026, 9, 30), 150)])
        let streak = StatsEngine.streak(ledger: data, goal: 100, installDate: date(2026, 9, 28), calendar: calendar, now: now)
        XCTAssertEqual(streak.current, 0)
        XCTAssertFalse(streak.todayAlive)
    }

    func testWeekSummary() {
        let now = date(2026, 9, 30) // Wednesday
        let data = ledger([
            (date(2026, 9, 28), 100), // Mon
            (date(2026, 9, 29), 300), // Tue
            (date(2026, 9, 30), 50),  // Wed
            (date(2026, 9, 21), 70),  // previous week
        ])
        let summary = StatsEngine.summary(for: .week, containing: now, ledger: data, goal: 200, calendar: calendar, now: now)
        XCTAssertEqual(summary.total, 450)
        XCTAssertEqual(summary.elapsedDays, 3)
        XCTAssertEqual(summary.bestDay?.count, 300)
        XCTAssertEqual(summary.peakHour, 23)
        XCTAssertEqual(summary.archetype, .nightOwl)
        XCTAssertEqual(summary.perApp.first?.app, .instagram)
        XCTAssertNotNil(summary.changeVsPrevious)
        XCTAssertEqual(summary.thumbMeters, 450 * StatsEngine.metersPerReel, accuracy: 0.001)
    }

    func testTouchGrassArchetype() {
        let now = date(2026, 9, 30)
        let data = ledger([(date(2026, 9, 30), 3)])
        let summary = StatsEngine.summary(for: .week, containing: now, ledger: data, goal: 100, calendar: calendar, now: now)
        XCTAssertEqual(summary.archetype, .touchGrass)
    }

    func testMoodScale() {
        XCTAssertEqual(Mood.from(count: 0, goal: 100), .fresh)
        XCTAssertEqual(Mood.from(count: 10, goal: 100), .chill)
        XCTAssertEqual(Mood.from(count: 95, goal: 100), .cooked)
        XCTAssertEqual(Mood.from(count: 300, goal: 100), .melted)
    }

    func testDayKeyRoundTrip() {
        let key = DayKey(date(2026, 1, 5), calendar: calendar)
        XCTAssertEqual(key.rawValue, "2026-01-05")
        XCTAssertEqual(key.adding(days: 30, calendar: calendar).rawValue, "2026-02-04")
        XCTAssertEqual(DayKey(rawValue: "2026-02-04"), key.adding(days: 30, calendar: calendar))
    }
}
