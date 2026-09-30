import Foundation
import Observation
import SwiftUI
import WidgetKit

/// App-wide state. Reads what the broadcast extension writes to the App Group
/// and refreshes live when it pings (Darwin notifications).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let router = Router()
    let battle = BattleStore()

    private(set) var ledger = Ledger()
    private(set) var live: LiveState?
    private(set) var goal = 100
    private(set) var streak = StreakInfo(current: 0, best: 0, todayAlive: true)
    private(set) var automationVerified = false
    private(set) var closeAutomationSeen = false
    private(set) var trackedApps: Set<SourceApp> = Set(SourceApp.tracked)
    /// Bumped every time the extension reports a broadcast start.
    private(set) var broadcastStarts = 0

    private let store = SharedStore.shared
    private let settings = SharedSettings.shared
    @ObservationIgnored private var observers: [UUID] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private init() {
        reload()
        observeExtension()
        router.showOnboarding = !settings.onboardingComplete
    }

    // MARK: Derived

    var today: DayRecord {
        let key = DayKey.today()
        return ledger[key] ?? DayRecord(day: key)
    }

    var isArmed: Bool { live?.isArmed() ?? false }
    var mood: Mood { Mood.from(count: today.total, goal: goal) }
    var sessionCount: Int { isArmed ? (live?.sessionCount ?? 0) : 0 }

    /// Stable per-day seed so quips don't change on every refresh.
    var daySeed: Int { Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0 }

    var installDate: Date { settings.installDate }

    // MARK: Loading

    func reload() {
        ledger = store.mergedLedger()
        live = store.live
        goal = settings.dailyGoal
        trackedApps = settings.trackedApps
        automationVerified = settings.automationVerifiedAt != nil
        closeAutomationSeen = settings.closeAutomationSeenAt != nil
        recomputeStreak()
    }

    func reloadLive() {
        let latest = store.live
        guard latest != live else { return }
        live = latest
        if let today = latest?.today {
            if let existing = ledger[today.day], existing.updatedAt > today.updatedAt {
                // ledger is newer — keep it
            } else {
                ledger[today.day] = today
            }
        }
        recomputeStreak()
    }

    private func recomputeStreak() {
        streak = StatsEngine.streak(ledger: ledger, goal: goal, installDate: settings.installDate)
    }

    private func observeExtension() {
        let center = DarwinCenter.shared
        observers.append(center.observe(DarwinName.liveChanged) {
            Task { @MainActor in AppModel.shared.reloadLive() }
        })
        observers.append(center.observe(DarwinName.broadcastStarted) {
            Task { @MainActor in
                let model = AppModel.shared
                model.reloadLive()
                model.broadcastStarts += 1
            }
        })
        observers.append(center.observe(DarwinName.broadcastFinished) {
            Task { @MainActor in AppModel.shared.reload() }
        })
    }

    // MARK: Scene lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            reload()
            consumePendingRoute()
            startPolling()
            Task { await battle.bootstrapIfNeeded() }
            Task { await SyncService.shared.pushRecentDays() }
            Task { await RemoteConfigService.refreshIfNeeded() }
            Task { await LiveActivityService.shared.refresh() }
        case .background:
            pollTask?.cancel()
            pollTask = nil
            BackgroundRefresh.schedule()
            WidgetCenter.shared.reloadAllTimelines()
        default:
            break
        }
    }

    func consumePendingRoute() {
        if let route = settings.consumePendingRoute() { router.open(route: route) }
    }

    /// Belt-and-braces refresh while the app is open (Darwin pings can be
    /// coalesced by the system).
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.reloadLive()
            }
        }
    }

    // MARK: Actions

    func handle(url: URL) {
        router.handle(url: url)
    }

    func setGoal(_ value: Int) {
        settings.dailyGoal = value
        goal = settings.dailyGoal
        recomputeStreak()
        DarwinCenter.shared.post(DarwinName.settingsChanged)
        WidgetCenter.shared.reloadAllTimelines()
        Task { await battle.updateGoal(settings.dailyGoal) }
        Task { await LiveActivityService.shared.refresh() }
    }

    func setTracked(_ app: SourceApp, enabled: Bool) {
        var apps = settings.trackedApps
        if enabled { apps.insert(app) } else { apps.remove(app) }
        settings.trackedApps = apps
        trackedApps = apps
        DarwinCenter.shared.post(DarwinName.settingsChanged)
    }

    func setStrictPrivacy(_ enabled: Bool) {
        settings.strictPrivacyMode = enabled
        DarwinCenter.shared.post(DarwinName.settingsChanged)
    }

    func setDiagnostics(_ enabled: Bool) {
        settings.diagnosticsEnabled = enabled
        DarwinCenter.shared.post(DarwinName.settingsChanged)
    }

    func stopCounting() {
        DarwinCenter.shared.post(DarwinName.stopRequested)
    }

    func completeOnboarding() {
        settings.onboardingComplete = true
        router.showOnboarding = false
    }

    func resetAllData() {
        store.removeAll()
        DarwinCenter.shared.post(DarwinName.dataReset)
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// CSV of daily totals for "export my data".
    func exportCSV() -> URL? {
        var lines = ["date,total,instagram,youtube,tiktok,snapchat,other,watch_minutes,ads_skipped,rewatches_skipped,sessions"]
        for record in ledger.days.values.sorted(by: { $0.day < $1.day }) {
            let apps = SourceApp.allCases.map { String(record.count(for: $0)) }.joined(separator: ",")
            lines.append("\(record.day.rawValue),\(record.total),\(apps),\(Int(record.watchSeconds / 60)),\(record.adsSkipped),\(record.rewatchesSkipped),\(record.sessions)")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("doomscore-export.csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
