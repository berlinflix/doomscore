import Foundation
import WidgetKit

/// Turns detector decisions into today's numbers, sessions and the live state
/// other processes read. Confined to the pipeline's analysis queue.
final class StatsRecorder {
    private struct Session {
        var startedAt: Date
        var reels: Int
        var lastActivity: Date
    }

    private let queue: DispatchQueue
    private let store: SharedStore
    private let settings: SharedSettings
    private let ingest: IngestClient
    private let sessionGap: TimeInterval

    private(set) var today: DayRecord
    private var live: LiveState
    private var goal: Int
    private var trackedApps: Set<SourceApp>
    private var session: Session?

    private var liveDirty = false
    private var ledgerDirty = false
    private var ingestDirty = false
    private var ingestInFlight = false
    private var sessionStartedPending = false
    private var lastLiveWrite = Date.distantPast
    private var lastLedgerWrite = Date.distantPast
    private var lastDarwinPost = Date.distantPast
    private var lastWidgetReload = Date.distantPast
    private var lastIngest = Date.distantPast

    /// Called on the analysis queue when the calendar day changes.
    var onDayChanged: (() -> Void)?

    init(queue: DispatchQueue, store: SharedStore = .shared, settings: SharedSettings = .shared, ingest: IngestClient = .shared, sessionGap: TimeInterval) {
        self.queue = queue
        self.store = store
        self.settings = settings
        self.ingest = ingest
        self.sessionGap = sessionGap
        let todayRecord = store.todayRecord()
        var liveState = store.live ?? LiveState(today: todayRecord)
        liveState.today = todayRecord
        self.today = todayRecord
        self.live = liveState
        self.goal = settings.dailyGoal
        self.trackedApps = settings.trackedApps
    }

    // MARK: Lifecycle

    func start(now: Date) {
        rollDayIfNeeded(now)
        live.broadcastActive = true
        live.startedAt = now
        live.inReels = false
        live.sessionCount = session?.reels ?? 0
        writeLive(now)
        DarwinCenter.shared.post(DarwinName.broadcastStarted)
        ingestDirty = true
    }

    func finish(now: Date) {
        rollDayIfNeeded(now)
        session = nil
        live.broadcastActive = false
        live.inReels = false
        live.sessionCount = 0
        live.sessionStartedAt = nil
        live.today = today
        writeLive(now)
        writeLedger(now)
        DarwinCenter.shared.post(DarwinName.broadcastFinished)
        WidgetCenter.shared.reloadAllTimelines()
        if ingest.isReady {
            ingest.sendBlocking(IngestPayload.make(for: today, live: liveInfo(armed: false)))
        }
    }

    func reloadSettings() {
        goal = settings.dailyGoal
        trackedApps = settings.trackedApps
        ingestDirty = true
    }

    /// The app wiped local data.
    func resetToday(now: Date) {
        today = DayRecord(day: DayKey(now))
        session = nil
        live.today = today
        live.sessionCount = 0
        writeLive(now)
    }

    // MARK: Events

    func apply(_ decisions: [CountDecision], now: Date) {
        guard !decisions.isEmpty else { return }
        rollDayIfNeeded(now)
        for decision in decisions {
            let app = decision.app
            guard app == .other || trackedApps.contains(app) else { continue }
            switch decision {
            case .counted:
                today.total += 1
                today.perApp[app.rawValue, default: 0] += 1
                let hour = Calendar.current.component(.hour, from: now)
                if (0..<24).contains(hour) { today.hourly[hour] += 1 }
                if today.firstReelAt == nil { today.firstReelAt = now }
                today.lastReelAt = now
                live.lastCountAt = now
                live.currentApp = app
                bumpSession(now)
            case .skippedAd:
                today.adsSkipped += 1
            case .skippedRewatch:
                today.rewatchesSkipped += 1
            }
        }
        today.updatedAt = now
        live.today = today
        liveDirty = true
        ledgerDirty = true
        ingestDirty = true
        writeLiveIfNeeded(now, urgent: true)
    }

    func addWatch(seconds: Double, app: SourceApp, now: Date) {
        guard app == .other || trackedApps.contains(app) else { return }
        rollDayIfNeeded(now)
        today.watchSeconds += seconds
        today.watchPerApp[app.rawValue, default: 0] += seconds
        today.updatedAt = now
        live.today = today
        ledgerDirty = true
    }

    func setContext(inReels: Bool, app: SourceApp?, now: Date) {
        if live.inReels != inReels || (inReels && app != nil && live.currentApp != app) {
            live.inReels = inReels
            if inReels, let app { live.currentApp = app }
            liveDirty = true
        }
        if inReels, var current = session {
            current.lastActivity = now
            session = current
        }
    }

    // MARK: Timer

    func tick(now: Date) {
        rollDayIfNeeded(now)

        if let current = session, now.timeIntervalSince(current.lastActivity) > sessionGap {
            session = nil
            live.sessionCount = 0
            live.sessionStartedAt = nil
            liveDirty = true
            ingestDirty = true
            writeLedger(now)
            reloadWidgets(now, force: true)
        }

        // Heartbeat so readers can tell a live extension from a crashed one.
        if now.timeIntervalSince(lastLiveWrite) >= 5 { liveDirty = true }
        writeLiveIfNeeded(now, urgent: false)

        if ledgerDirty, now.timeIntervalSince(lastLedgerWrite) >= 10 { writeLedger(now) }
        if ledgerDirty || liveDirty { reloadWidgets(now, force: false) }
        sendIngestIfNeeded(now)
    }

    // MARK: Internals

    private func bumpSession(_ now: Date) {
        var current: Session
        if let existing = session, now.timeIntervalSince(existing.lastActivity) <= sessionGap {
            current = existing
            current.reels += 1
            current.lastActivity = now
        } else {
            current = Session(startedAt: now, reels: 1, lastActivity: now)
            today.sessions += 1
            sessionStartedPending = true
            live.sessionStartedAt = now
        }
        session = current
        today.longestSession = max(today.longestSession, current.reels)
        live.sessionCount = current.reels
    }

    private func rollDayIfNeeded(_ now: Date) {
        let key = DayKey(now)
        guard key != today.day else { return }
        let finished = today
        writeLedger(now) // persist the finished day first
        if ingest.isReady {
            let client = ingest
            let payload = IngestPayload.make(for: finished, live: nil)
            Task.detached { try? await client.send(payload) }
        }
        today = DayRecord(day: key)
        session = nil
        live.today = today
        live.sessionCount = 0
        live.sessionStartedAt = nil
        writeLive(now)
        onDayChanged?()
        reloadWidgets(now, force: true)
        ingestDirty = true
    }

    private func writeLiveIfNeeded(_ now: Date, urgent: Bool) {
        guard liveDirty else { return }
        if urgent, now.timeIntervalSince(lastLiveWrite) < 0.25 { return } // coalesced into the next tick
        writeLive(now)
    }

    private func writeLive(_ now: Date) {
        live.heartbeat = now
        live.today = today
        store.write(live, to: .live)
        lastLiveWrite = now
        liveDirty = false
        if now.timeIntervalSince(lastDarwinPost) >= 0.4 {
            DarwinCenter.shared.post(DarwinName.liveChanged)
            lastDarwinPost = now
        }
    }

    private func writeLedger(_ now: Date) {
        let record = today
        store.update(Ledger.self, in: .ledger, default: { Ledger() }) { ledger in
            ledger[record.day] = record
        }
        lastLedgerWrite = now
        ledgerDirty = false
    }

    private func reloadWidgets(_ now: Date, force: Bool) {
        // WidgetKit budgets reloads from extensions; keep them rare.
        guard force || now.timeIntervalSince(lastWidgetReload) >= 15 * 60 else { return }
        lastWidgetReload = now
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func liveInfo(armed: Bool) -> IngestPayload.Live {
        IngestPayload.Live(
            todayCount: today.total,
            sessionCount: session?.reels ?? 0,
            goal: goal,
            armed: armed,
            appName: (live.currentApp ?? today.topApp ?? .instagram).displayName,
            sessionStarted: sessionStartedPending
        )
    }

    private func sendIngestIfNeeded(_ now: Date) {
        guard ingestDirty, !ingestInFlight, ingest.isReady, now.timeIntervalSince(lastIngest) >= 4 else { return }
        ingestDirty = false
        ingestInFlight = true
        lastIngest = now
        let payload = IngestPayload.make(for: today, live: liveInfo(armed: true))
        sessionStartedPending = false
        let client = ingest
        let queue = self.queue
        Task.detached { [weak self] in
            var succeeded = true
            do { try await client.send(payload) } catch { succeeded = false }
            queue.async {
                guard let self else { return }
                self.ingestInFlight = false
                if !succeeded { self.ingestDirty = true }
            }
        }
    }
}
