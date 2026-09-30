import Foundation

enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, year
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

struct DayCount: Hashable, Sendable, Identifiable {
    let day: DayKey
    let count: Int
    var id: String { day.rawValue }
    var date: Date { day.startDate() }
}

struct MonthCount: Hashable, Sendable, Identifiable {
    let year: Int
    let month: Int
    let count: Int
    var id: String { "\(year)-\(month)" }
    var date: Date { Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date() }
}

struct AppCount: Hashable, Sendable, Identifiable {
    let app: SourceApp
    let count: Int
    let seconds: Double
    var id: String { app.rawValue }
}

/// Gen-Z scroll personalities for the recap.
enum Archetype: String, Sendable {
    case touchGrass, speedrunner, deepDiver, nightOwl, earlyBird, lunchMenace, weekendWarrior, mainCharacter

    var title: String {
        switch self {
        case .touchGrass: "Touch Grass Champion"
        case .speedrunner: "The Speedrunner"
        case .deepDiver: "The Deep Diver"
        case .nightOwl: "Night Owl Doomer"
        case .earlyBird: "Sunrise Scroller"
        case .lunchMenace: "Lunch Break Menace"
        case .weekendWarrior: "Weekend Warrior"
        case .mainCharacter: "Main Character"
        }
    }

    var emoji: String {
        switch self {
        case .touchGrass: "🌱"
        case .speedrunner: "⚡️"
        case .deepDiver: "🤿"
        case .nightOwl: "🦉"
        case .earlyBird: "🌅"
        case .lunchMenace: "🍜"
        case .weekendWarrior: "🎉"
        case .mainCharacter: "💅"
        }
    }

    var blurb: String {
        switch self {
        case .touchGrass: "barely scrolled. are you even online? respect."
        case .speedrunner: "you judge a reel in under 7 seconds. ruthless."
        case .deepDiver: "you actually watch reels to the end. rare behavior."
        case .nightOwl: "your peak scroll hour is past bedtime. the 3am algorithm loves you."
        case .earlyBird: "reels before breakfast. bold strategy."
        case .lunchMenace: "lunch break = reel break. no notes."
        case .weekendWarrior: "weekdays? composed. weekends? unhinged."
        case .mainCharacter: "balanced, consistent, a little chaotic. main character behavior."
        }
    }
}

struct StreakInfo: Sendable, Equatable {
    /// Consecutive days (ending today) at or under the daily cap.
    var current: Int
    var best: Int
    /// Whether today is still inside the cap (streak alive).
    var todayAlive: Bool
}

struct PeriodSummary: Sendable {
    var period: StatsPeriod
    var interval: DateInterval
    var total: Int
    var elapsedDays: Int
    var activeDays: Int
    var averagePerDay: Double
    var bestDay: DayCount?
    var watchSeconds: Double
    var adsSkipped: Int
    var rewatchesSkipped: Int
    var perApp: [AppCount]
    var hourly: [Int]
    var peakHour: Int?
    /// Index 0 = Sunday … 6 = Saturday.
    var weekdayTotals: [Int]
    var busiestWeekday: Int?
    var series: [DayCount]
    var monthly: [MonthCount]
    var longestSession: Int
    var previousAveragePerDay: Double?
    var longestChillStreak: Int
    var archetype: Archetype

    var changeVsPrevious: Double? {
        guard let previous = previousAveragePerDay, previous > 0 else { return nil }
        return (averagePerDay - previous) / previous
    }

    var thumbMeters: Double { Double(total) * StatsEngine.metersPerReel }
    var hours: Double { watchSeconds / 3600 }
}

enum StatsEngine {
    /// One reel swipe moves roughly one phone screen of content.
    static let metersPerReel = 0.14

    // MARK: Streaks

    static func streak(ledger: Ledger, goal: Int, installDate: Date, calendar: Calendar = .current, now: Date = Date()) -> StreakInfo {
        let today = DayKey(now, calendar: calendar)
        let installDay = min(DayKey(installDate, calendar: calendar), ledger.firstDay ?? today)
        func isChill(_ day: DayKey) -> Bool { (ledger[day]?.total ?? 0) <= goal }

        let todayAlive = isChill(today)
        var current = 0
        if todayAlive {
            var day = today
            while day >= installDay, isChill(day) {
                current += 1
                day = day.adding(days: -1, calendar: calendar)
            }
        }

        var best = 0
        var run = 0
        var day = installDay
        var guardCounter = 0
        while day <= today, guardCounter < 3660 {
            if isChill(day) { run += 1; best = max(best, run) } else { run = 0 }
            day = day.adding(days: 1, calendar: calendar)
            guardCounter += 1
        }
        return StreakInfo(current: current, best: max(best, current), todayAlive: todayAlive)
    }

    // MARK: Period summaries

    static func interval(for period: StatsPeriod, containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: period.calendarComponent, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }

    static func summary(
        for period: StatsPeriod,
        containing date: Date,
        ledger: Ledger,
        goal: Int,
        installDate: Date? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> PeriodSummary {
        let interval = StatsEngine.interval(for: period, containing: date, calendar: calendar)
        let todayKey = DayKey(now, calendar: calendar)

        // Days of the period up to (and including) today.
        var days: [DayKey] = []
        var cursor = DayKey(interval.start, calendar: calendar)
        let lastDay = min(DayKey(interval.end.addingTimeInterval(-1), calendar: calendar), todayKey)
        var safety = 0
        while cursor <= lastDay, safety < 400 {
            days.append(cursor)
            cursor = cursor.adding(days: 1, calendar: calendar)
            safety += 1
        }

        var total = 0, ads = 0, rewatches = 0, longestSession = 0, activeDays = 0
        var watch = 0.0
        var hourly = Array(repeating: 0, count: 24)
        var weekday = Array(repeating: 0, count: 7)
        var appCounts: [SourceApp: Int] = [:]
        var appSeconds: [SourceApp: Double] = [:]
        var series: [DayCount] = []
        var monthly: [String: MonthCount] = [:]

        for day in days {
            let record = ledger[day]
            let count = record?.total ?? 0
            series.append(DayCount(day: day, count: count))
            let comps = day.components
            let monthKey = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            let previousMonth = monthly[monthKey]?.count ?? 0
            monthly[monthKey] = MonthCount(year: comps.year ?? 0, month: comps.month ?? 0, count: previousMonth + count)
            guard let record else { continue }
            total += record.total
            if record.total > 0 { activeDays += 1 }
            watch += record.watchSeconds
            ads += record.adsSkipped
            rewatches += record.rewatchesSkipped
            longestSession = max(longestSession, record.longestSession)
            for hour in 0..<24 { hourly[hour] += record.hourly[hour] }
            let weekdayIndex = calendar.component(.weekday, from: day.startDate(calendar: calendar)) - 1
            if (0..<7).contains(weekdayIndex) { weekday[weekdayIndex] += record.total }
            for (key, value) in record.perApp {
                if let app = SourceApp(rawValue: key) { appCounts[app, default: 0] += value }
            }
            for (key, value) in record.watchPerApp {
                if let app = SourceApp(rawValue: key) { appSeconds[app, default: 0] += value }
            }
        }

        let elapsed = max(days.count, 1)
        let average = Double(total) / Double(elapsed)
        let best = series.filter { $0.count > 0 }.max { $0.count < $1.count }
        let peakHour = hourly.max().flatMap { $0 > 0 ? hourly.firstIndex(of: $0) : nil }
        let busiestWeekday = weekday.max().flatMap { $0 > 0 ? weekday.firstIndex(of: $0) : nil }
        let perApp = appCounts
            .map { AppCount(app: $0.key, count: $0.value, seconds: appSeconds[$0.key] ?? 0) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
        let months = monthly.values.sorted { ($0.year, $0.month) < ($1.year, $1.month) }

        // Previous period, compared per elapsed day so partial periods are fair.
        var previousAverage: Double?
        if let previousDate = calendar.date(byAdding: period.calendarComponent, value: -1, to: interval.start) {
            let previousInterval = StatsEngine.interval(for: period, containing: previousDate, calendar: calendar)
            let start = DayKey(previousInterval.start, calendar: calendar)
            let end = DayKey(previousInterval.end.addingTimeInterval(-1), calendar: calendar)
            let hasData = ledger.days.values.contains { $0.day >= start && $0.day <= end }
            if hasData {
                let dayCount = max(calendar.dateComponents([.day], from: previousInterval.start, to: previousInterval.end).day ?? 1, 1)
                previousAverage = Double(ledger.total(from: start, through: end)) / Double(dayCount)
            }
        }

        // Longest run of days under the cap inside this period.
        var longestChill = 0, run = 0
        let installKey = installDate.map { DayKey($0, calendar: calendar) }
        for entry in series {
            if let installKey, entry.day < installKey { run = 0; continue }
            if entry.count <= goal { run += 1; longestChill = max(longestChill, run) } else { run = 0 }
        }

        let archetype = archetypeFor(
            total: total, average: average, watchSeconds: watch, peakHour: peakHour,
            weekdayTotals: weekday, series: series, calendar: calendar
        )

        return PeriodSummary(
            period: period,
            interval: interval,
            total: total,
            elapsedDays: elapsed,
            activeDays: activeDays,
            averagePerDay: average,
            bestDay: best,
            watchSeconds: watch,
            adsSkipped: ads,
            rewatchesSkipped: rewatches,
            perApp: perApp,
            hourly: hourly,
            peakHour: peakHour,
            weekdayTotals: weekday,
            busiestWeekday: busiestWeekday,
            series: series,
            monthly: months,
            longestSession: longestSession,
            previousAveragePerDay: previousAverage,
            longestChillStreak: longestChill,
            archetype: archetype
        )
    }

    static func archetypeFor(
        total: Int, average: Double, watchSeconds: Double, peakHour: Int?,
        weekdayTotals: [Int], series: [DayCount], calendar: Calendar
    ) -> Archetype {
        if total == 0 || average < 8 { return .touchGrass }
        let secondsPerReel = watchSeconds / Double(max(total, 1))
        if total >= 30, secondsPerReel > 0, secondsPerReel < 7 { return .speedrunner }
        if total >= 20, secondsPerReel > 28 { return .deepDiver }

        // Weekend vs weekday average (per calendar day present in the series).
        var weekendSum = 0, weekendDays = 0, weekdaySum = 0, weekdayDays = 0
        for entry in series {
            let weekday = calendar.component(.weekday, from: entry.day.startDate(calendar: calendar))
            if weekday == 1 || weekday == 7 { weekendSum += entry.count; weekendDays += 1 }
            else { weekdaySum += entry.count; weekdayDays += 1 }
        }
        if weekendDays > 0, weekdayDays > 0 {
            let weekendAvg = Double(weekendSum) / Double(weekendDays)
            let weekdayAvg = Double(weekdaySum) / Double(weekdayDays)
            if weekendAvg > 20, weekendAvg > weekdayAvg * 1.6 { return .weekendWarrior }
        }

        if let hour = peakHour {
            if hour >= 22 || hour < 4 { return .nightOwl }
            if (5...9).contains(hour) { return .earlyBird }
            if (12...14).contains(hour) { return .lunchMenace }
        }
        return .mainCharacter
    }

    // MARK: Fun comparisons

    static func distanceComparison(meters: Double) -> String {
        switch meters {
        case ..<1:
            return "not even a meter. touch grass legend 🌱"
        case ..<60:
            return String(format: "that's %.1f giraffes stacked 🦒", meters / 5.5)
        case ..<1_000:
            return String(format: "that's %.1f Eiffel Towers 🗼", meters / 330)
        case ..<8_849:
            return String(format: "that's %.1f Burj Khalifas 🏙️", meters / 828)
        default:
            return String(format: "that's %.2f Mount Everests 🏔️", meters / 8_849)
        }
    }

    static func movieComparison(seconds: Double) -> String {
        let movies = seconds / (2 * 3600)
        if movies < 0.5 { return "not even half a movie. we love that" }
        return String(format: "that's %.1f full movies 🍿", movies)
    }
}
