import Foundation

// "Auto mode": Apple's Screen Time API (FamilyControls + DeviceActivity).
//
// iOS never lets an app see another app's screen without a broadcast, but it
// will tell an authorised app "Instagram has now been open N minutes today".
// Doomscore listens for those minute marks in a tiny monitor extension and
// turns minutes into reels with the user's scroll pace. No recording, no red
// pill, no taps — it runs all day. Precise mode (screen broadcast) is optional
// and calibrates the pace.
//
// Everything in this file is pure logic (unit tested in
// Tests/ScreenTimeEstimatorTests.swift); the framework glue lives in
// ActivityMonitor/ and App/Services/ScreenTimeService.swift.

// MARK: - Slots

/// Apps tracked through Screen Time. YouTube and Snapchat aren't offered:
/// Screen Time can't tell Shorts/Spotlight from the rest of those apps.
enum ScreenTimeSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case instagram = "ig"
    case tiktok = "tt"

    var id: String { rawValue }

    var app: SourceApp {
        switch self {
        case .instagram: .instagram
        case .tiktok: .tiktok
        }
    }

    /// Reels per minute of app time before precise mode has calibrated it.
    func defaultPace(style: ScrollStyle) -> Double {
        switch self {
        case .instagram: style.instagramPace
        case .tiktok: 5.0
        }
    }

    static let paceRange: ClosedRange<Double> = 0.5...15
}

/// Onboarding quiz answer: how much of someone's Instagram time is reels.
enum ScrollStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case reelsOnly, mixed, mostlyChats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reelsOnly: "basically only reels"
        case .mixed: "reels + feed + stories"
        case .mostlyChats: "mostly DMs, some reels"
        }
    }

    var emoji: String {
        switch self {
        case .reelsOnly: "🫠"
        case .mixed: "🌀"
        case .mostlyChats: "💬"
        }
    }

    var instagramPace: Double {
        switch self {
        case .reelsOnly: 5.0
        case .mixed: 3.5
        case .mostlyChats: 1.5
        }
    }
}

// MARK: - Threshold ladder

enum ScreenTimeLadder {
    /// Bump when the thresholds change so the app re-registers monitoring.
    static let version = 1

    /// Minutes of use at which Screen Time wakes the monitor extension:
    /// every minute for the first hour, then gradually coarser.
    static let thresholds: [Int] = {
        var minutes = Array(1...60)
        minutes += stride(from: 62, through: 180, by: 2)
        minutes += stride(from: 185, through: 480, by: 5)
        minutes += stride(from: 490, through: 960, by: 10)
        return minutes
    }()

    static let watchdogActivity = "doomscore.watchdog"

    static func activityName(for slot: ScreenTimeSlot) -> String { "doomscore.\(slot.rawValue)" }

    static func eventName(slot: ScreenTimeSlot, minutes: Int) -> String { "\(slot.rawValue).\(minutes)" }

    static func parse(_ name: String) -> (slot: ScreenTimeSlot, minutes: Int)? {
        let parts = name.split(separator: ".")
        guard parts.count == 2,
              let slot = ScreenTimeSlot(rawValue: String(parts[0])),
              let minutes = Int(parts[1]), minutes > 0 else { return nil }
        return (slot, minutes)
    }
}

// MARK: - Stored state

/// One day of Screen Time–based tracking.
struct ScreenTimeDay: Codable, Equatable, Sendable {
    var day: DayKey
    /// Minutes each app was in front today (monotonic), keyed by `SourceApp`.
    var minutes: [String: Int] = [:]
    /// Minutes that happened while precise mode was counting — those reels
    /// were counted exactly, so they're never estimated.
    var coveredMinutes: [String: Int] = [:]
    /// Estimated reels, accumulated at the pace in effect at the time, so a
    /// later recalibration never makes today's number go down.
    var estimatedReels: [String: Double] = [:]
    var hourlyReels: [Double] = Array(repeating: 0, count: 24)
    var lastEventAt: [String: Date] = [:]
    var sessions: Int = 0
    var longestSessionReels: Double = 0
    var firstAt: Date?
    var lastAt: Date?
    var updatedAt: Date = .distantPast

    init(day: DayKey) { self.day = day }

    var totalMinutes: Int { minutes.values.reduce(0, +) }
    var totalEstimated: Int { estimatedReels.values.reduce(0) { $0 + Int($1.rounded()) } }

    private enum CodingKeys: String, CodingKey {
        case day, minutes, coveredMinutes, estimatedReels, hourlyReels, lastEventAt
        case sessions, longestSessionReels, firstAt, lastAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(DayKey.self, forKey: .day)
        minutes = try c.decodeIfPresent([String: Int].self, forKey: .minutes) ?? [:]
        coveredMinutes = try c.decodeIfPresent([String: Int].self, forKey: .coveredMinutes) ?? [:]
        estimatedReels = try c.decodeIfPresent([String: Double].self, forKey: .estimatedReels) ?? [:]
        let hours = try c.decodeIfPresent([Double].self, forKey: .hourlyReels) ?? []
        hourlyReels = hours.count == 24 ? hours : Array(repeating: 0, count: 24)
        lastEventAt = try c.decodeIfPresent([String: Date].self, forKey: .lastEventAt) ?? [:]
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        longestSessionReels = try c.decodeIfPresent(Double.self, forKey: .longestSessionReels) ?? 0
        firstAt = try c.decodeIfPresent(Date.self, forKey: .firstAt)
        lastAt = try c.decodeIfPresent(Date.self, forKey: .lastAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

/// The visit currently in progress (drives the Dynamic Island).
struct ScreenTimeSession: Codable, Equatable, Sendable {
    var app: SourceApp
    var startedAt: Date
    var lastEventAt: Date
    var minutes: Int
    var reels: Double
}

/// When monitoring for a slot last (re)started. Thresholds registered with
/// `includesPastActivity: false` count from that moment on the day of
/// registration, and from midnight on later days.
struct ScreenTimeRegistration: Codable, Equatable, Sendable {
    var registeredAt: Date
    var day: DayKey
    var baselineMinutes: Int
    var ladderVersion: Int
}

/// Shared between the app and the monitor extension (App Group file).
struct ScreenTimeState: Codable, Sendable {
    var registrations: [String: ScreenTimeRegistration] = [:]
    var days: [String: ScreenTimeDay] = [:]
    var session: ScreenTimeSession?
    var lastEventAt: Date?
    /// Recent thresholds that arrived before they were physically possible.
    var premature: [Date] = []
    /// Set after a burst of premature thresholds (an iOS bug that also
    /// "uses up" the real ones) — the app re-registers monitoring.
    var needsRearmSince: Date?
    var lastIngestAt: Date?
    /// Last finished day each app's pace was calibrated from (app → day).
    var calibratedThrough: [String: String] = [:]

    init() {}

    subscript(day: DayKey) -> ScreenTimeDay? { days[day.rawValue] }

    private enum CodingKeys: String, CodingKey {
        case registrations, days, session, lastEventAt, premature, needsRearmSince, lastIngestAt, calibratedThrough
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        registrations = try c.decodeIfPresent([String: ScreenTimeRegistration].self, forKey: .registrations) ?? [:]
        days = try c.decodeIfPresent([String: ScreenTimeDay].self, forKey: .days) ?? [:]
        session = try c.decodeIfPresent(ScreenTimeSession.self, forKey: .session)
        lastEventAt = try c.decodeIfPresent(Date.self, forKey: .lastEventAt)
        premature = try c.decodeIfPresent([Date].self, forKey: .premature) ?? []
        needsRearmSince = try c.decodeIfPresent(Date.self, forKey: .needsRearmSince)
        lastIngestAt = try c.decodeIfPresent(Date.self, forKey: .lastIngestAt)
        calibratedThrough = try c.decodeIfPresent([String: String].self, forKey: .calibratedThrough) ?? [:]
    }
}

// MARK: - Estimator

enum ScreenTimeEstimator {
    struct Event: Sendable, Equatable {
        var slot: ScreenTimeSlot
        /// Threshold that was reached, in minutes.
        var threshold: Int
        var at: Date
        /// When a Shortcuts automation saw the app open, if recently.
        var openedAt: Date?
    }

    enum Rejection: String, Sendable {
        /// More minutes than could have passed since counting began.
        case premature
    }

    enum Outcome: Sendable, Equatable {
        case accepted(delta: Int, sessionStarted: Bool)
        case duplicate
        case rejected(Rejection)
    }

    /// No threshold for this long = the visit ended.
    static let sessionGap: TimeInterval = 4 * 60
    static let keepDays = 800

    /// Applies one threshold callback. Duplicate, late and premature
    /// callbacks (all of which iOS produces) are absorbed here.
    static func apply(
        _ event: Event,
        to state: inout ScreenTimeState,
        pace: Double,
        preciseActive: Bool,
        calendar: Calendar = .current
    ) -> Outcome {
        let now = event.at
        let key = DayKey(now, calendar: calendar)
        let startOfDay = calendar.startOfDay(for: now)
        let app = event.slot.app.rawValue
        var day = state.days[key.rawValue] ?? ScreenTimeDay(day: key)

        var base = 0
        var origin = startOfDay
        if let registration = state.registrations[event.slot.rawValue],
           registration.day == key, registration.registeredAt > startOfDay {
            base = registration.baselineMinutes
            origin = registration.registeredAt
        }

        // Usage can't outrun the clock.
        let elapsed = Int(max(0, now.timeIntervalSince(origin)) / 60)
        guard event.threshold <= elapsed + 1 else {
            notePremature(at: now, in: &state)
            return .rejected(.premature)
        }

        let current = day.minutes[app] ?? 0
        var value = base + event.threshold
        guard value > current else { return .duplicate }
        if let last = day.lastEventAt[app] {
            let sinceLast = Int((max(0, now.timeIntervalSince(last)) / 60).rounded(.up))
            value = min(value, current + sinceLast + 1)
        }
        let delta = value - current
        let safePace = min(max(pace, ScreenTimeSlot.paceRange.lowerBound), ScreenTimeSlot.paceRange.upperBound)
        let reels = preciseActive ? 0 : Double(delta) * safePace

        day.minutes[app] = value
        if preciseActive {
            day.coveredMinutes[app, default: 0] += delta
        } else {
            day.estimatedReels[app, default: 0] += reels
            let hour = calendar.component(.hour, from: now)
            if day.hourlyReels.indices.contains(hour) { day.hourlyReels[hour] += reels }
        }
        day.lastEventAt[app] = now
        let visitStart = max(startOfDay, now.addingTimeInterval(-Double(delta) * 60))
        if day.firstAt == nil { day.firstAt = visitStart }
        day.lastAt = now
        day.updatedAt = now

        var started = false
        if var session = state.session,
           session.app == event.slot.app,
           now.timeIntervalSince(session.lastEventAt) <= sessionGap,
           DayKey(session.startedAt, calendar: calendar) == key {
            session.lastEventAt = now
            session.minutes += delta
            session.reels += reels
            state.session = session
        } else {
            started = true
            if !preciseActive { day.sessions += 1 }
            var startedAt = visitStart
            if let opened = event.openedAt, opened <= now, now.timeIntervalSince(opened) < 15 * 60, opened >= startOfDay {
                startedAt = min(startedAt, opened)
            }
            state.session = ScreenTimeSession(app: event.slot.app, startedAt: startedAt, lastEventAt: now, minutes: delta, reels: reels)
        }
        if let session = state.session {
            day.longestSessionReels = max(day.longestSessionReels, session.reels)
        }

        state.days[key.rawValue] = day
        state.lastEventAt = now
        prune(&state, today: key, calendar: calendar)
        return .accepted(delta: delta, sessionStarted: started)
    }

    /// Call right before (re)starting monitoring for a slot.
    static func register(_ slot: ScreenTimeSlot, at now: Date, in state: inout ScreenTimeState, calendar: Calendar = .current) {
        let key = DayKey(now, calendar: calendar)
        let minutes = state.days[key.rawValue]?.minutes[slot.app.rawValue] ?? 0
        state.registrations[slot.rawValue] = ScreenTimeRegistration(
            registeredAt: now,
            day: key,
            baselineMinutes: minutes,
            ladderVersion: ScreenTimeLadder.version
        )
        state.premature.removeAll()
        state.needsRearmSince = nil
    }

    /// Ends the current visit if nothing happened for `idleFor` seconds.
    @discardableResult
    static func endSession(in state: inout ScreenTimeState, at now: Date, idleFor: TimeInterval = 150) -> ScreenTimeSession? {
        guard let session = state.session, now.timeIntervalSince(session.lastEventAt) >= idleFor else { return nil }
        state.session = nil
        return session
    }

    /// Blends a day's measured pace (exact reels from precise mode ÷ the
    /// Screen Time minutes it covered) into the stored one.
    static func calibratedPace(previous: Double?, exactReels: Int, coveredMinutes: Int) -> Double? {
        guard coveredMinutes >= 8, exactReels > 0 else { return nil }
        let measured = Double(exactReels) / Double(coveredMinutes)
        guard ScreenTimeSlot.paceRange.contains(measured) else { return nil }
        guard let previous else { return measured }
        return previous * 0.6 + measured * 0.4
    }

    private static func notePremature(at now: Date, in state: inout ScreenTimeState) {
        state.premature = state.premature.filter { now.timeIntervalSince($0) < 120 } + [now]
        if state.premature.count >= 3, state.needsRearmSince == nil { state.needsRearmSince = now }
    }

    private static func prune(_ state: inout ScreenTimeState, today: DayKey, calendar: Calendar) {
        guard state.days.count > keepDays else { return }
        let cutoff = today.adding(days: -keepDays, calendar: calendar)
        state.days = state.days.filter { $0.value.day >= cutoff }
    }
}

// MARK: - Merging with exact counts

extension ScreenTimeDay {
    /// Adds this day's estimate to the exact (precise-mode) record.
    func merged(into exact: DayRecord) -> DayRecord {
        var record = exact
        var added = 0
        for (app, value) in estimatedReels {
            let reels = Int(value.rounded())
            guard reels > 0 else { continue }
            record.perApp[app, default: 0] += reels
            added += reels
        }
        record.total += added
        record.estimatedReels += added
        record.screenMinutes += totalMinutes
        if record.hourly.count == 24 {
            for hour in 0..<24 { record.hourly[hour] += Int(hourlyReels[hour].rounded()) }
        }
        for (app, value) in minutes {
            let uncovered = max(0, value - (coveredMinutes[app] ?? 0))
            guard uncovered > 0 else { continue }
            record.watchSeconds += Double(uncovered * 60)
            record.watchPerApp[app, default: 0] += Double(uncovered * 60)
        }
        record.sessions += sessions
        record.longestSession = max(record.longestSession, Int(longestSessionReels.rounded()))
        if added > 0, let firstAt { record.firstReelAt = min(record.firstReelAt ?? firstAt, firstAt) }
        if added > 0, let lastAt { record.lastReelAt = max(record.lastReelAt ?? lastAt, lastAt) }
        record.updatedAt = max(record.updatedAt, updatedAt)
        return record
    }
}
