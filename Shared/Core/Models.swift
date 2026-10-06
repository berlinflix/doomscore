import Foundation

// MARK: - Source apps

/// Short-video feeds Doomscore knows how to count.
enum SourceApp: String, Codable, CaseIterable, Sendable, Identifiable {
    case instagram, youtube, tiktok, snapchat, other

    var id: String { rawValue }

    /// Apps the user can toggle on/off (`other` is an internal bucket).
    static let tracked: [SourceApp] = [.instagram, .youtube, .tiktok, .snapchat]

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .tiktok: "TikTok"
        case .snapchat: "Snapchat"
        case .other: "Other"
        }
    }

    /// What the app calls its vertical feed.
    var feedName: String {
        switch self {
        case .instagram: "Reels"
        case .youtube: "Shorts"
        case .tiktok: "For You"
        case .snapchat: "Spotlight"
        case .other: "clips"
        }
    }

    var shortLabel: String {
        switch self {
        case .instagram: "IG"
        case .youtube: "YT"
        case .tiktok: "TT"
        case .snapchat: "SC"
        case .other: "??"
        }
    }

    /// URL used to bounce the user back after arming the counter.
    var launchURL: URL? {
        switch self {
        case .instagram: URL(string: "instagram://app")
        case .youtube: URL(string: "youtube://")
        case .tiktok: URL(string: "snssdk1233://")
        case .snapchat: URL(string: "snapchat://")
        case .other: nil
        }
    }
}

// MARK: - Day keys

/// A calendar day in the user's current time zone, encoded as "yyyy-MM-dd".
/// Lexicographic order equals chronological order.
struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.rawValue = String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func today(calendar: Calendar = .current) -> DayKey { DayKey(Date(), calendar: calendar) }

    var components: DateComponents {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    func startDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        let start = startDate(calendar: calendar)
        let shifted = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return DayKey(shifted, calendar: calendar)
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }

    var description: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad day key \(raw)"))
        }
        self = key
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Daily record

/// Everything Doomscore stores about one day. Only aggregates — never content.
struct DayRecord: Codable, Equatable, Sendable {
    var day: DayKey
    var total: Int = 0
    var perApp: [String: Int] = [:]
    var hourly: [Int] = Array(repeating: 0, count: 24)
    var watchSeconds: Double = 0
    var watchPerApp: [String: Double] = [:]
    var adsSkipped: Int = 0
    var rewatchesSkipped: Int = 0
    var sessions: Int = 0
    var longestSession: Int = 0
    var firstReelAt: Date?
    var lastReelAt: Date?
    var updatedAt: Date = .distantPast
    /// Part of `total` estimated from Screen Time minutes (auto mode).
    var estimatedReels: Int = 0
    /// Minutes the tracked apps were open, per Screen Time.
    var screenMinutes: Int = 0

    init(day: DayKey) { self.day = day }

    func count(for app: SourceApp) -> Int { perApp[app.rawValue] ?? 0 }
    func seconds(for app: SourceApp) -> Double { watchPerApp[app.rawValue] ?? 0 }

    var topApp: SourceApp? {
        guard let best = perApp.max(by: { $0.value < $1.value }), best.value > 0 else { return nil }
        return SourceApp(rawValue: best.key)
    }

    var averageSecondsPerReel: Double? { total > 0 ? watchSeconds / Double(total) : nil }

    /// Whether any of today's number is a Screen Time estimate.
    var isEstimated: Bool { estimatedReels > 0 }

    private enum CodingKeys: String, CodingKey {
        case day, total, perApp, hourly, watchSeconds, watchPerApp, adsSkipped, rewatchesSkipped
        case sessions, longestSession, firstReelAt, lastReelAt, updatedAt, estimatedReels, screenMinutes
    }

    // Tolerant decoding so adding fields in future versions never wipes history.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(DayKey.self, forKey: .day)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        perApp = try c.decodeIfPresent([String: Int].self, forKey: .perApp) ?? [:]
        let hours = try c.decodeIfPresent([Int].self, forKey: .hourly) ?? []
        hourly = hours.count == 24 ? hours : Array(repeating: 0, count: 24)
        watchSeconds = try c.decodeIfPresent(Double.self, forKey: .watchSeconds) ?? 0
        watchPerApp = try c.decodeIfPresent([String: Double].self, forKey: .watchPerApp) ?? [:]
        adsSkipped = try c.decodeIfPresent(Int.self, forKey: .adsSkipped) ?? 0
        rewatchesSkipped = try c.decodeIfPresent(Int.self, forKey: .rewatchesSkipped) ?? 0
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        longestSession = try c.decodeIfPresent(Int.self, forKey: .longestSession) ?? 0
        firstReelAt = try c.decodeIfPresent(Date.self, forKey: .firstReelAt)
        lastReelAt = try c.decodeIfPresent(Date.self, forKey: .lastReelAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        estimatedReels = try c.decodeIfPresent(Int.self, forKey: .estimatedReels) ?? 0
        screenMinutes = try c.decodeIfPresent(Int.self, forKey: .screenMinutes) ?? 0
    }
}

// MARK: - Ledger (history)

struct Ledger: Codable, Sendable {
    var version: Int = 1
    var days: [String: DayRecord] = [:]

    init() {}

    subscript(day: DayKey) -> DayRecord? {
        get { days[day.rawValue] }
        set { days[day.rawValue] = newValue }
    }

    var firstDay: DayKey? { days.keys.min().flatMap(DayKey.init(rawValue:)) }

    func total(from start: DayKey, through end: DayKey) -> Int {
        days.values.reduce(0) { $1.day >= start && $1.day <= end ? $0 + $1.total : $0 }
    }
}

// MARK: - Live state (written by the broadcast extension)

struct LiveState: Codable, Equatable, Sendable {
    var broadcastActive: Bool = false
    var heartbeat: Date = .distantPast
    var startedAt: Date?
    var today: DayRecord
    var sessionCount: Int = 0
    var sessionStartedAt: Date?
    var currentApp: SourceApp?
    var inReels: Bool = false
    var lastCountAt: Date?

    init(today: DayRecord) { self.today = today }

    /// The extension writes a heartbeat every few seconds; a stale heartbeat
    /// means it was killed without `broadcastFinished`.
    func isArmed(now: Date = Date()) -> Bool {
        broadcastActive && now.timeIntervalSince(heartbeat) < 25
    }

    private enum CodingKeys: String, CodingKey {
        case broadcastActive, heartbeat, startedAt, today, sessionCount, sessionStartedAt, currentApp, inReels, lastCountAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        today = try c.decode(DayRecord.self, forKey: .today)
        broadcastActive = try c.decodeIfPresent(Bool.self, forKey: .broadcastActive) ?? false
        heartbeat = try c.decodeIfPresent(Date.self, forKey: .heartbeat) ?? .distantPast
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        sessionCount = try c.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        sessionStartedAt = try c.decodeIfPresent(Date.self, forKey: .sessionStartedAt)
        currentApp = try c.decodeIfPresent(SourceApp.self, forKey: .currentApp)
        inReels = try c.decodeIfPresent(Bool.self, forKey: .inReels) ?? false
        lastCountAt = try c.decodeIfPresent(Date.self, forKey: .lastCountAt)
    }
}

// MARK: - Foreground hint (written by the Shortcuts automation intents)

struct ForegroundHint: Codable, Equatable, Sendable {
    var app: SourceApp
    var openedAt: Date
    var closedAt: Date?

    /// Without an "Is Closed" automation we never learn when the app closed,
    /// so the hint expires after two hours.
    func isForeground(now: Date = Date()) -> Bool {
        closedAt == nil && now.timeIntervalSince(openedAt) < 2 * 3600
    }
}

// MARK: - Detector diagnostics (Settings → Detector lab)

struct DetectorDiagnostics: Codable, Sendable {
    var updatedAt: Date = Date()
    var framesProcessed: Int = 0
    var processedFPS: Double = 0
    var swipesForward: Int = 0
    var swipesBackward: Int = 0
    var ocrRuns: Int = 0
    var lastOCRMillis: Double = 0
    var context: String = "unknown"
    var contextApp: String?
    var lastScore: Int = 0
    var lastDecision: String = "—"
    var availableMemoryMB: Double = 0
    var counted: Int = 0
    var adsSkipped: Int = 0
    var rewatchesSkipped: Int = 0
    var recentEvents: [String] = []
}

// MARK: - Cached leaderboard (written by the app, read by the battle widget)

struct CachedLeaderboard: Codable, Sendable {
    struct Row: Codable, Sendable, Hashable {
        var name: String
        var emoji: String
        var colorHex: String
        var reels: Int
        var isMe: Bool
    }
    var day: DayKey
    var rows: [Row]
    var updatedAt: Date
}

// MARK: - JSON coding

enum JSONCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
