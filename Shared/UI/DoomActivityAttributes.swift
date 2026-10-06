import ActivityKit
import Foundation

/// Live Activity shown in the Dynamic Island / Lock Screen while you scroll —
/// iOS's version of the Android floating counter bubble.
///
/// ⚠️ The backend sends `content-state` JSON that must match these property
/// names (see backend/supabase/functions/ingest/index.ts). Numbers only — no
/// `Date` fields, to avoid Codable date-format mismatches. Newer fields decode
/// with defaults, so an older backend can never break the activity.
struct DoomActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var todayCount: Int
        var sessionCount: Int
        var goal: Int
        var armed: Bool
        var appName: String
        /// Unix seconds.
        var updatedAt: Double
        /// Counts include Screen Time estimates (auto mode).
        var estimated: Bool = false
        /// Unix seconds the current visit started (0 = unknown). Drives the
        /// live timer, which iOS ticks without any updates.
        var sessionStart: Double = 0
        /// Days in a row under the daily cap.
        var streak: Int = 0

        private enum CodingKeys: String, CodingKey {
            case todayCount, sessionCount, goal, armed, appName, updatedAt, estimated, sessionStart, streak
        }
    }

    /// Unix seconds.
    var sessionStartEpoch: Double
}

extension DoomActivityAttributes.ContentState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        todayCount = try c.decodeIfPresent(Int.self, forKey: .todayCount) ?? 0
        sessionCount = try c.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        goal = try c.decodeIfPresent(Int.self, forKey: .goal) ?? 100
        armed = try c.decodeIfPresent(Bool.self, forKey: .armed) ?? false
        appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? "Instagram"
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        estimated = try c.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
        sessionStart = try c.decodeIfPresent(Double.self, forKey: .sessionStart) ?? 0
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
    }

    var mood: Mood { Mood.from(count: todayCount, goal: goal) }
    var progress: Double { goal > 0 ? min(Double(todayCount) / Double(goal), 1) : 0 }
    var isOverCap: Bool { goal > 0 && todayCount > goal }

    /// Start of the current visit, if known and plausible.
    var sessionStartDate: Date? {
        guard sessionStart > 0 else { return nil }
        let date = Date(timeIntervalSince1970: sessionStart)
        return date <= Date().addingTimeInterval(60) ? date : nil
    }
}
