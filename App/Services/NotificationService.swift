import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { scheduleRecaps() }
        return granted
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// A reels app opened while nothing is tracking: a quiet reminder to
    /// connect Screen Time (never a screen-broadcast prompt).
    static func sendTrackingNudge(for app: SourceApp) async {
        let settings = SharedSettings.shared
        guard settings.nudgesEnabled else { return }
        if let last = settings.lastNudgeAt, Date().timeIntervalSince(last) < 60 * 60 { return }
        guard await isAuthorized() else { return }
        settings.lastNudgeAt = Date()

        let content = UNMutableNotificationContent()
        content.title = "doomscore isn't tracking 👀"
        content.body = "connect Screen Time once and your \(app.feedName) count runs by itself"
        content.sound = nil
        content.interruptionLevel = .active
        content.threadIdentifier = "tracking-nudge"
        content.userInfo = ["route": "today"]
        let request = UNNotificationRequest(identifier: "tracking-nudge", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Opt-in exact mode (Settings → exact mode): fallback when the
    /// automation can't bring up the arm screen by itself (iOS < 26).
    static func sendExactModeNudge(for app: SourceApp) async {
        let settings = SharedSettings.shared
        guard settings.nudgesEnabled, settings.preciseAutoPrompt else { return }
        if let last = settings.lastNudgeAt, Date().timeIntervalSince(last) < 10 * 60 { return }
        guard await isAuthorized() else { return }
        settings.lastNudgeAt = Date()

        let content = UNMutableNotificationContent()
        content.title = "exact mode is off"
        content.body = "tap to count your \(app.feedName) exactly"
        content.sound = nil
        content.interruptionLevel = .active
        content.threadIdentifier = "arm-nudge"
        content.userInfo = ["route": "arm?return=\(app.rawValue)"]
        let request = UNNotificationRequest(identifier: "arm-nudge", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancelRecaps() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-recap", "weekly-wrapped"])
    }

    /// Nightly damage report + Sunday recap. Static copy, deep-linked.
    /// Off switch: Settings → "nightly report + weekly recap".
    static func scheduleRecaps() {
        guard SharedSettings.shared.recapsEnabled else { return }
        let center = UNUserNotificationCenter.current()

        let daily = UNMutableNotificationContent()
        daily.title = "today's damage report 📊"
        daily.body = "see how cooked you got today"
        daily.userInfo = ["route": "today"]
        var dailyTime = DateComponents()
        dailyTime.hour = 21
        dailyTime.minute = 30
        center.add(UNNotificationRequest(
            identifier: "daily-recap",
            content: daily,
            trigger: UNCalendarNotificationTrigger(dateMatching: dailyTime, repeats: true)
        ))

        let weekly = UNMutableNotificationContent()
        weekly.title = "your week in doom is ready 📼"
        weekly.body = "tap for your weekly recap"
        weekly.userInfo = ["route": "wrapped?period=week"]
        var weeklyTime = DateComponents()
        weeklyTime.weekday = 1
        weeklyTime.hour = 19
        center.add(UNNotificationRequest(
            identifier: "weekly-wrapped",
            content: weekly,
            trigger: UNCalendarNotificationTrigger(dateMatching: weeklyTime, repeats: true)
        ))
    }
}
