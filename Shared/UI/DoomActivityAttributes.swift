import ActivityKit
import Foundation

/// Live Activity shown in the Dynamic Island / Lock Screen while you scroll —
/// iOS's version of the Android floating counter bubble.
///
/// ⚠️ The backend sends `content-state` JSON that must match these property
/// names exactly (see backend/supabase/functions/ingest/index.ts). Numbers
/// only — no `Date` fields, to avoid Codable date-format mismatches.
struct DoomActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var todayCount: Int
        var sessionCount: Int
        var goal: Int
        var armed: Bool
        var appName: String
        /// Unix seconds.
        var updatedAt: Double
    }

    /// Unix seconds.
    var sessionStartEpoch: Double
}

extension DoomActivityAttributes.ContentState {
    var mood: Mood { Mood.from(count: todayCount, goal: goal) }
    var progress: Double { goal > 0 ? min(Double(todayCount) / Double(goal), 1) : 0 }
}
