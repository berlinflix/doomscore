import DeviceActivity
import Foundation

/// What the monitor extension does with each Screen Time callback.
///
/// iOS kills DeviceActivityMonitor extensions that go over 6 MB of memory,
/// so this stays tiny: no SwiftUI/WidgetKit, no history decoding (the state
/// file only ever holds today and yesterday), the count is saved before
/// anything optional runs, and the server ping is small and infrequent.
enum ScreenTimeRuntime {
    /// A tracked app reached another minute of use.
    static func thresholdReached(_ name: String, at now: Date) {
        let settings = SharedSettings.shared
        settings.noteMonitorCallback(name, at: now)
        guard settings.screenTimeEnabled, let parsed = ScreenTimeLadder.parse(name) else {
            settings.noteMonitorOutcome("ignored (tracking off)")
            return
        }
        let store = SharedStore.shared
        // While exact mode is counting, its numbers win; Screen Time only
        // records the minutes (used to calibrate the pace).
        let live = store.live
        let preciseActive = live?.isArmed(now: now) ?? false
        let hint = store.hint
        let openedAt = (hint?.app == parsed.slot.app && hint?.isForeground(now: now) == true) ? hint?.openedAt : nil
        let event = ScreenTimeEstimator.Event(slot: parsed.slot, threshold: parsed.minutes, at: now, openedAt: openedAt)
        let pace = settings.pace(for: parsed.slot)
        let todayKey = DayKey(now)

        var outcome = ScreenTimeEstimator.Outcome.duplicate
        var session: ScreenTimeSession?
        var today: ScreenTimeDay?
        var archived: [ScreenTimeDay] = []
        var shouldSync = false
        store.update(ScreenTimeState.self, in: .screenTime, default: { ScreenTimeState() }) { state in
            outcome = ScreenTimeEstimator.apply(event, to: &state, pace: pace, preciseActive: preciseActive)
            archived = ScreenTimeEstimator.archiveOldDays(in: &state, today: todayKey)
            session = state.session
            today = state[todayKey]
            guard case .accepted(_, let started) = outcome else { return }
            // Pings go out when a visit starts and then every ~2 minutes.
            if started || now.timeIntervalSince(state.lastIngestAt ?? .distantPast) >= 110 {
                state.lastIngestAt = now
                shouldSync = true
            }
        }
        if !archived.isEmpty { store.appendScreenTimeHistory(archived) }

        switch outcome {
        case .accepted(let delta, let sessionStarted):
            settings.noteMonitorOutcome("+\(delta) min\(sessionStarted ? " (new visit)" : "")")
            DarwinCenter.shared.post(DarwinName.screenTimeChanged)
            armWatchdog(now: now)
            if shouldSync, !preciseActive {
                sync(now: now, today: today, exact: live, session: session, sessionStarted: sessionStarted, ended: false)
            }
        case .rejected(let reason):
            settings.noteMonitorOutcome("rejected: \(reason.rawValue)")
        case .duplicate:
            settings.noteMonitorOutcome("duplicate")
        }
    }

    /// No minute mark for a few minutes: the visit is over.
    static func watchdogFired(at now: Date) {
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(ScreenTimeLadder.watchdogActivity)])
        let store = SharedStore.shared
        var ended: ScreenTimeSession?
        var today: ScreenTimeDay?
        store.update(ScreenTimeState.self, in: .screenTime, default: { ScreenTimeState() }) { state in
            ended = ScreenTimeEstimator.endSession(in: &state, at: now)
            today = state[DayKey(now)]
        }
        guard let ended else { return }
        DarwinCenter.shared.post(DarwinName.screenTimeChanged)
        let live = store.live
        guard live?.isArmed(now: now) != true else { return }
        sync(now: now, today: today, exact: live, session: ended, sessionStarted: false, ended: true)
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
        try? DeviceActivityCenter().startMonitoring(DeviceActivityName(ScreenTimeLadder.watchdogActivity), during: schedule)
    }

    /// Uploads today's totals and mirrors the count to the Dynamic Island
    /// (the backend turns it into an ActivityKit push). Built from small
    /// files only — never the full history.
    private static func sync(now: Date, today: ScreenTimeDay?, exact live: LiveState?, session: ScreenTimeSession?, sessionStarted: Bool, ended: Bool) {
        let client = IngestClient.shared
        guard client.isReady else { return }
        let settings = SharedSettings.shared
        let key = DayKey(now)
        let exact = (live?.today.day == key ? live?.today : nil) ?? DayRecord(day: key)
        let shown = today.map { $0.merged(into: exact) } ?? exact
        let payload = IngestPayload.make(for: shown, live: IngestPayload.Live(
            todayCount: shown.total,
            sessionCount: Int((session?.reels ?? 0).rounded()),
            goal: settings.dailyGoal,
            armed: true,
            appName: (session?.app ?? .instagram).displayName,
            sessionStarted: sessionStarted,
            estimated: true,
            sessionStart: session?.startedAt.timeIntervalSince1970,
            streak: settings.cachedStreak,
            ended: ended
        ))
        // The extension is torn down when this callback returns, so wait for the request.
        client.sendBlocking(payload, timeout: 3.5)
    }
}
