import Foundation
import Observation
import SwiftUI
import WidgetKit

/// App-wide state. Reads what the extensions (Screen Time monitor, broadcast)
/// write to the App Group and refreshes live when they ping (Darwin notifications).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// How reels are being counted right now.
    enum TrackingMode: Equatable {
        case off
        /// Screen Time minutes × pace — always on, no broadcast.
        case auto
        /// Screen broadcast — every reel, ads and rewatches skipped.
        case precise
    }

    let router = Router()
    let battle = BattleStore()
    let screenTime = ScreenTimeService.shared

    private(set) var ledger = Ledger()
    private(set) var live: LiveState?
    private(set) var screenSession: ScreenTimeSession?
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
    @ObservationIgnored private var screenTimeFileDate: Date?

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

    /// Precise mode (screen broadcast) is running.
    var isArmed: Bool { live?.isArmed() ?? false }

    var trackingMode: TrackingMode {
        if isArmed { return .precise }
        return screenTime.isTracking ? .auto : .off
    }

    var mood: Mood { Mood.from(count: today.total, goal: goal) }

    var sessionCount: Int {
        if isArmed { return live?.sessionCount ?? 0 }
        guard let session = screenSession, Date().timeIntervalSince(session.lastEventAt) < ScreenTimeEstimator.sessionGap else { return 0 }
        return Int(session.reels.rounded())
    }

    /// Stable per-day seed so quips don't change on every refresh.
    var daySeed: Int { Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0 }

    var installDate: Date { settings.installDate }

    // MARK: Loading

    func reload() {
        screenTime.calibrateFromPreciseDays(exact: store.exactLedger())
        screenTimeFileDate = store.modificationDate(of: .screenTime)
        ledger = store.mergedLedger()
        live = store.live
        screenSession = store.screenTime?.session
        goal = settings.dailyGoal
        trackedApps = settings.trackedApps
        automationVerified = settings.automationVerifiedAt != nil
        closeAutomationSeen = settings.closeAutomationSeenAt != nil
        recomputeStreak()
    }

    func reloadLive() {
        // The Screen Time monitor wrote something we missed a ping for.
        if store.modificationDate(of: .screenTime) != screenTimeFileDate {
            reload()
            return
        }
        let latest = store.live
        guard latest != live else { return }
        live = latest
        if let exact = latest?.today {
            let today = store.effective(exact)
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
        observers.append(center.observe(DarwinName.screenTimeChanged) {
            Task { @MainActor in AppModel.shared.reload() }
        })
    }

    // MARK: Scene lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            screenTime.ensureMonitoring()
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
        // Thresholds restart from zero with the wiped history.
        screenTime.ensureMonitoring(force: true)
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setScrollStyle(_ style: ScrollStyle) {
        settings.scrollStyle = style
        DarwinCenter.shared.post(DarwinName.settingsChanged)
    }

    /// Reels per minute used for Screen Time estimates.
    func pace(for slot: ScreenTimeSlot) -> Double { settings.pace(for: slot) }

    /// Whether precise mode has measured this user's real pace yet.
    var isPaceCalibrated: Bool { !settings.calibratedPaces.isEmpty }

    /// CSV of daily totals for "export my data".
    func exportCSV() -> URL? {
        var lines = ["date,total,estimated,instagram,youtube,tiktok,snapchat,other,screen_time_minutes,watch_minutes,ads_skipped,rewatches_skipped,sessions"]
        for record in ledger.days.values.sorted(by: { $0.day < $1.day }) {
            let apps = SourceApp.allCases.map { String(record.count(for: $0)) }.joined(separator: ",")
            lines.append("\(record.day.rawValue),\(record.total),\(record.estimatedReels),\(apps),\(record.screenMinutes),\(Int(record.watchSeconds / 60)),\(record.adsSkipped),\(record.rewatchesSkipped),\(record.sessions)")
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
