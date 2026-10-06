import BackgroundTasks
import Foundation
import WidgetKit

/// Occasional background refresh: re-arms Screen Time monitoring if iOS
/// dropped it, re-syncs recent days and refreshes the battle widget's cached
/// leaderboard.
enum BackgroundRefresh {
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "app.doomscore") + ".refresh" }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run() async {
        schedule()
        ScreenTimeService.shared.ensureMonitoring()
        await SyncService.shared.pushRecentDays(force: true)
        await AppModel.shared.battle.refreshForWidget()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
