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

    /// Fallback when the automation can't open the arm screen by itself
    /// (iOS < 26): a time-sensitive nudge on top of the reels app.
    static func sendArmNudge(for app: SourceApp) async {
        let settings = SharedSettings.shared
        guard settings.nudgesEnabled else { return }
        if let last = settings.lastNudgeAt, Date().timeIntervalSince(last) < 10 * 60 { return }
        guard await isAuthorized() else { return }
        settings.lastNudgeAt = Date()

        let content = UNMutableNotificationContent()
        content.title = "counter's off 👀"
        content.body = "tap to start counting your \(app.feedName) — takes 2 sec"
        content.sound = nil
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.threadIdentifier = "arm-nudge"
        content.userInfo = ["route": "arm?auto=1&return=\(app.rawValue)"]
        let request = UNNotificationRequest(identifier: "arm-nudge", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Nightly damage report + Sunday recap. Static copy, deep-linked.
    static func scheduleRecaps() {
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
        weekly.body = "tap for your weekly wrapped"
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
