import ActivityKit
import Foundation

/// The iOS stand-in for Android's floating counter bubble: a Live Activity in
/// the Dynamic Island and on the Lock Screen.
///
/// • Started locally by the "Reels App Opened" automation intent (a
///   LiveActivityIntent may start activities from the background), when
///   precise mode starts, or remotely with a push-to-start token when the
///   Screen Time monitor sees a new visit.
/// • Updated remotely: the extensions report counts to your backend, which
///   pushes ActivityKit updates to the token registered here. (App
///   extensions can't update Live Activities directly.)
/// • Ended by the "Reels App Closed" automation, or by the backend when the
///   Screen Time monitor notices the visit is over.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var observed = Set<String>()
    private var updateTokens: [String: String] = [:]
    /// Activities whose update token the backend has confirmed.
    private var registered = Set<String>()
    private var startToken: String?
    private var observingStarted = false

    private init() {}

    var current: Activity<DoomActivityAttributes>? {
        Activity<DoomActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
    }

    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func startObserving() {
        guard !observingStarted else { return }
        observingStarted = true
        for activity in Activity<DoomActivityAttributes>.activities { observe(activity) }
        Task { [weak self] in
            for await activity in Activity<DoomActivityAttributes>.activityUpdates {
                self?.observe(activity)
            }
        }
        Task { [weak self] in
            for await data in Activity<DoomActivityAttributes>.pushToStartTokenUpdates {
                let token = Self.hex(data)
                self?.startToken = token
                try? await IngestClient.shared.registerActivityToken(token, kind: .start)
            }
        }
    }

    /// Shows (or refreshes) the counter in the Dynamic Island.
    func showCounting(app: SourceApp?, armed: Bool) async {
        guard isEnabled else { return }
        let state = makeState(armed: armed, app: app)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(state.estimated ? 5 * 60 : 30 * 60))
        if let activity = current {
            await activity.update(content)
            return
        }
        do {
            let activity = try Activity.request(
                attributes: DoomActivityAttributes(sessionStartEpoch: Date().timeIntervalSince1970),
                content: content,
                pushType: AppEnvironment.isBackendConfigured ? .token : nil
            )
            observe(activity)
        } catch {
            Log.activity.error("request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Refreshes an existing activity from the latest shared state.
    func refresh() async {
        guard let activity = current else { return }
        let state = makeState(armed: isCounting, app: nil)
        await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(state.estimated ? 5 * 60 : 30 * 60)))
    }

    /// Reels app closed: show the final count for a few minutes, then go away.
    func endSession() async {
        for activity in Activity<DoomActivityAttributes>.activities {
            let final = makeState(armed: isCounting, app: nil)
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(4 * 60)))
            if let token = updateTokens.removeValue(forKey: activity.id) {
                await IngestClient.shared.unregisterActivityToken(token)
            }
        }
    }

    /// Background intents can be suspended as soon as they return. Give a
    /// freshly started activity's push token a moment to reach the backend —
    /// otherwise the backend would push-to-start a second island.
    func waitForTokenRegistration(timeout: TimeInterval = 2.5) async {
        guard IngestClient.shared.isReady, let id = current?.id else { return }
        let deadline = Date().addingTimeInterval(timeout)
        while !registered.contains(id), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    func reuploadTokens() async {
        for token in updateTokens.values { try? await IngestClient.shared.registerActivityToken(token, kind: .update) }
        if let startToken { try? await IngestClient.shared.registerActivityToken(startToken, kind: .start) }
    }

    // MARK: Internals

    private func observe(_ activity: Activity<DoomActivityAttributes>) {
        guard observed.insert(activity.id).inserted else { return }
        let id = activity.id
        Task { [weak self] in
            for await data in activity.pushTokenUpdates {
                let token = Self.hex(data)
                self?.updateTokens[id] = token
                if (try? await IngestClient.shared.registerActivityToken(token, kind: .update)) != nil {
                    self?.registered.insert(id)
                }
            }
        }
    }

    /// Precise mode is running or Screen Time is tracking.
    private var isCounting: Bool {
        SharedStore.shared.isArmed() || ScreenTimeService.shared.isTracking
    }

    private func makeState(armed: Bool, app: SourceApp?) -> DoomActivityAttributes.ContentState {
        let store = SharedStore.shared
        let settings = SharedSettings.shared
        let now = Date()
        let live = store.live
        let ledger = store.mergedLedger()
        let today = ledger[DayKey(now)] ?? DayRecord(day: DayKey(now))
        let precise = live?.isArmed(now: now) == true

        var session = 0
        var start: Date?
        if precise {
            session = live?.sessionCount ?? 0
            start = live?.sessionStartedAt ?? live?.startedAt
        } else if let visit = store.screenTime?.session, now.timeIntervalSince(visit.lastEventAt) < ScreenTimeEstimator.sessionGap {
            session = Int(visit.reels.rounded())
            start = visit.startedAt
        } else if let hint = store.hint, hint.isForeground(now: now), now.timeIntervalSince(hint.openedAt) < 15 * 60 {
            start = hint.openedAt // just opened (automation) — no minute mark yet
        }

        let goal = settings.dailyGoal
        let streak = StatsEngine.streak(ledger: ledger, goal: goal, installDate: settings.installDate, now: now)
        return DoomActivityAttributes.ContentState(
            todayCount: today.total,
            sessionCount: session,
            goal: goal,
            armed: armed,
            appName: (app ?? live?.currentApp ?? today.topApp ?? .instagram).displayName,
            updatedAt: now.timeIntervalSince1970,
            estimated: !precise && (today.isEstimated || ScreenTimeService.shared.isTracking),
            sessionStart: start?.timeIntervalSince1970 ?? 0,
            streak: streak.current
        )
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
