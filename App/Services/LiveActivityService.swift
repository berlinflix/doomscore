import ActivityKit
import Foundation

/// The iOS stand-in for Android's floating counter bubble: a Live Activity in
/// the Dynamic Island and on the Lock Screen.
///
/// • Started locally by the "Reels App Opened" automation intent (a
///   LiveActivityIntent may start activities from the background) or when
///   the user arms the counter.
/// • Updated remotely: the broadcast extension reports counts to your backend,
///   which pushes ActivityKit updates to the token registered here. (App
///   extensions can't update Live Activities directly.)
/// • Push-to-start tokens let the backend start one even if the app never
///   ran (e.g. counter armed from Control Center).
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var observed = Set<String>()
    private var updateTokens: [String: String] = [:]
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
        let content = ActivityContent(state: makeState(armed: armed, app: app), staleDate: Date().addingTimeInterval(30 * 60))
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
        let armed = SharedStore.shared.isArmed()
        await activity.update(ActivityContent(state: makeState(armed: armed, app: nil), staleDate: Date().addingTimeInterval(30 * 60)))
    }

    /// Reels app closed: show the final count for a few minutes, then go away.
    func endSession() async {
        for activity in Activity<DoomActivityAttributes>.activities {
            let final = makeState(armed: SharedStore.shared.isArmed(), app: nil)
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(8 * 60)))
            if let token = updateTokens.removeValue(forKey: activity.id) {
                await IngestClient.shared.unregisterActivityToken(token)
            }
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
                try? await IngestClient.shared.registerActivityToken(token, kind: .update)
            }
        }
    }

    private func makeState(armed: Bool, app: SourceApp?) -> DoomActivityAttributes.ContentState {
        let store = SharedStore.shared
        let live = store.live
        let today = store.todayRecord()
        let session = (live?.isArmed() == true) ? (live?.sessionCount ?? 0) : 0
        return DoomActivityAttributes.ContentState(
            todayCount: today.total,
            sessionCount: session,
            goal: SharedSettings.shared.dailyGoal,
            armed: armed,
            appName: (app ?? live?.currentApp ?? today.topApp ?? .instagram).displayName,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
