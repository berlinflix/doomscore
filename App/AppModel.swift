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
    //
    // All file I/O and number crunching happens off the main thread; the main
    // actor only swaps in finished snapshots, so scrolling and animations
    // never wait on disk or on the extensions.

    private struct Snapshot: Sendable {
        var ledger: Ledger
        var live: LiveState?
        var screenSession: ScreenTimeSession?
        var screenTimeFileDate: Date?
        var streak: StreakInfo
    }

    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var probing = false

    func reload() {
        goal = settings.dailyGoal
        trackedApps = settings.trackedApps
        automationVerified = settings.automationVerifiedAt != nil
        closeAutomationSeen = settings.closeAutomationSeenAt != nil
        loadGeneration += 1
        let generation = loadGeneration
        let goal = self.goal
        Task.detached(priority: .userInitiated) {
            let snapshot = AppModel.loadSnapshot(goal: goal)
            await MainActor.run { AppModel.shared.apply(snapshot, generation: generation) }
        }
    }

    nonisolated private static func loadSnapshot(goal: Int) -> Snapshot {
        let store = SharedStore.shared
        let settings = SharedSettings.shared
        ScreenTimeService.calibrateFromExactDays()
        let fileDate = store.modificationDate(of: .screenTime)
        let ledger = store.mergedLedger()
        let streak = StatsEngine.streak(ledger: ledger, goal: goal, installDate: settings.installDate)
        // The Screen Time extension sends this with island updates.
        settings.cachedStreak = streak.current
        return Snapshot(
            ledger: ledger,
            live: store.live,
            screenSession: store.screenTime?.session,
            screenTimeFileDate: fileDate,
            streak: streak
        )
    }

    private func apply(_ snapshot: Snapshot, generation: Int) {
        guard generation == loadGeneration else { return } // a newer load is on its way
        ledger = snapshot.ledger
        live = snapshot.live
        screenSession = snapshot.screenSession
        screenTimeFileDate = snapshot.screenTimeFileDate
        streak = snapshot.streak
    }

    /// Cheap check (two small reads, off the main thread) for changes the
    /// extensions made; does a full reload only when something changed.
    func reloadLive() {
        guard !probing else { return }
        probing = true
        let knownFileDate = screenTimeFileDate
        let knownLive = live
        Task.detached(priority: .utility) {
            let store = SharedStore.shared
            let fileDate = store.modificationDate(of: .screenTime)
            let latest = store.live
            await MainActor.run {
                let model = AppModel.shared
                model.probing = false
                if fileDate != knownFileDate || latest != knownLive { model.reload() }
            }
        }
    }

    private func recomputeStreak() {
        let ledger = self.ledger
        let goal = self.goal
        Task.detached(priority: .utility) {
            let streak = StatsEngine.streak(ledger: ledger, goal: goal, installDate: SharedSettings.shared.installDate)
            SharedSettings.shared.cachedStreak = streak.current
            await MainActor.run { AppModel.shared.streak = streak }
        }
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

    enum PaceSource: Equatable {
        case exactMode, paceTest, guess

        var label: String {
            switch self {
            case .exactMode: "measured by exact mode"
            case .paceTest: "your pace test"
            case .guess: "starting guess"
            }
        }
    }

    /// Bumped when the pace changes so views showing it refresh.
    private(set) var paceVersion = 0

    var paceSource: PaceSource {
        _ = paceVersion
        if !settings.calibratedPaces.isEmpty { return .exactMode }
        return settings.reelSpeed == nil ? .guess : .paceTest
    }

    /// Saves the pace test result (reels per minute while swiping).
    func setReelSpeed(_ speed: Double) {
        settings.reelSpeed = speed
        paceVersion += 1
        DarwinCenter.shared.post(DarwinName.settingsChanged)
    }

    func resetPace() {
        settings.reelSpeed = nil
        settings.calibratedPaces = [:]
        paceVersion += 1
        DarwinCenter.shared.post(DarwinName.settingsChanged)
    }

    func setRecapsEnabled(_ enabled: Bool) {
        settings.recapsEnabled = enabled
        if enabled {
            Task { if await NotificationService.isAuthorized() { NotificationService.scheduleRecaps() } }
        } else {
            NotificationService.cancelRecaps()
        }
    }

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
