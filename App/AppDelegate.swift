import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Also runs when iOS launches us in the background for an automation
        // intent or a push-to-start Live Activity — keep token uploads flowing.
        LiveActivityService.shared.startObserving()
        return true
    }

    // Notification callbacks may arrive off the main thread — stay nonisolated
    // and hop explicitly.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let route = response.notification.request.content.userInfo["route"] as? String else { return }
        await MainActor.run { AppModel.shared.router.open(route: route) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
