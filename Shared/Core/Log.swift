import os

/// Unified logging. Never log OCR text, usernames or anything read from the
/// screen — only counters and decisions.
enum Log {
    private static let subsystem = "app.doomscore"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let detector = Logger(subsystem: subsystem, category: "detector")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let activity = Logger(subsystem: subsystem, category: "live-activity")
}
