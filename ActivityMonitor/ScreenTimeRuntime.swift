import DeviceActivity
import Foundation
import WidgetKit

/// What the monitor extension does with each Screen Time callback.
enum ScreenTimeRuntime {
    private static let store = SharedStore.shared
    private static let settings = SharedSettings.shared

    /// A tracked app reached another minute of use.
    static func thresholdReached(_ name: String, at now: Date) {
        guard settings.screenTimeEnabled, let parsed = ScreenTimeLadder.parse(name) else { return }
        // While precise mode is counting, its exact numbers win; Screen Time
        // only records the minutes (used to calibrate the pace).
        let preciseActive = store.isArmed(now: now)
        let hint = store.hint
        let openedAt = (hint?.app == parsed.slot.app && hint?.isForeground(now: now) == true) ? hint?.openedAt : nil
        let event = ScreenTimeEstimator.Event(slot: parsed.slot, threshold: parsed.minutes, at: now, openedAt: openedAt)
        let pace = settings.pace(for: parsed.slot)

        var outcome = ScreenTimeEstimator.Outcome.duplicate
        var session: ScreenTimeSession?
        var shouldSync = false
        store.update(ScreenTimeState.self, in: .screenTime, default: { ScreenTimeState() }) { state in
            outcome = ScreenTimeEstimator.apply(event, to: &state, pace: pace, preciseActive: preciseActive)
            session = state.session
            guard case .accepted(_, let started) = outcome else { return }
            // Late callbacks arrive in bursts; one server ping per burst is plenty.
            if started || now.timeIntervalSince(state.lastIngestAt ?? .distantPast) >= 3 {
                state.lastIngestAt = now
                shouldSync = true
            }
        }

        switch outcome {
        case .accepted(_, let sessionStarted):
            DarwinCenter.shared.post(DarwinName.screenTimeChanged)
            armWatchdog(now: now)
            reloadWidgets(now: now, force: sessionStarted)
            if shouldSync, !preciseActive {
                sync(now: now, session: session, sessionStarted: sessionStarted, ended: false)
            }
        case .rejected(let reason):
            Log.screenTime.notice("threshold rejected: \(reason.rawValue, privacy: .public)")
        case .duplicate:
            break
        }
    }

    /// No minute mark for a few minutes: the visit is over.
    static func watchdogFired(at now: Date) {
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(ScreenTimeLadder.watchdogActivity)])
        var ended: ScreenTimeSession?
        store.update(ScreenTimeState.self, in: .screenTime, default: { ScreenTimeState() }) { state in
            ended = ScreenTimeEstimator.endSession(in: &state, at: now)
        }
        guard let ended else { return }
        DarwinCenter.shared.post(DarwinName.screenTimeChanged)
        reloadWidgets(now: now, force: true)
        guard !store.isArmed(now: now) else { return }
        sync(now: now, session: ended, sessionStarted: false, ended: true)
    }

    // MARK: Internals

    /// Re-armed on every minute mark, so it only ever starts ~3 minutes after
    /// the last one. iOS calls `intervalDidStart` once the phone is in use.
    private static func armWatchdog(now: Date) {
        let calendar = Calendar.current
        let start = now.addingTimeInterval(3 * 60)
        let end = start.addingTimeInterval(16 * 60) // schedules must span ≥ 15 min
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: start),
            intervalEnd: calendar.dateComponents(parts, from: end),
            repeats: false
        )
        do {
            try DeviceActivityCenter().startMonitoring(DeviceActivityName(ScreenTimeLadder.watchdogActivity), during: schedule)
        } catch {
            Log.screenTime.error("watchdog failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func reloadWidgets(now: Date, force: Bool) {
        // WidgetKit budgets reloads from extensions; keep them rare.
        if !force, let last = settings.screenTimeWidgetReloadAt, now.timeIntervalSince(last) < 10 * 60 { return }
        settings.screenTimeWidgetReloadAt = now
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Uploads today's totals and mirrors the count to the Dynamic Island
    /// (the backend turns it into an ActivityKit push).
    private static func sync(now: Date, session: ScreenTimeSession?, sessionStarted: Bool, ended: Bool) {
        let client = IngestClient.shared
        guard client.isReady else { return }
        let ledger = store.mergedLedger()
        let key = DayKey(now)
        let today = ledger[key] ?? DayRecord(day: key)
        let goal = settings.dailyGoal
        let streak = StatsEngine.streak(ledger: ledger, goal: goal, installDate: settings.installDate, now: now)
        let live = IngestPayload.Live(
            todayCount: today.total,
            sessionCount: Int((session?.reels ?? 0).rounded()),
            goal: goal,
            armed: true,
            appName: (session?.app ?? .instagram).displayName,
            sessionStarted: sessionStarted,
            estimated: true,
            sessionStart: session?.startedAt.timeIntervalSince1970,
            streak: streak.current,
            ended: ended
        )
        // The extension is torn down when this callback returns, so wait for the request.
        client.sendBlocking(IngestPayload.make(for: today, live: live), timeout: 3.5)
    }
}
