import DeviceActivity
import FamilyControls
import Foundation
import Observation

/// Auto mode: Apple's Screen Time API tells Doomscore how many minutes
/// Instagram / TikTok were open — never what was on them. Runs all day with
/// no screen broadcast and no taps; counts are estimates (minutes × pace).
@MainActor
@Observable
final class ScreenTimeService {
    static let shared = ScreenTimeService()

    enum Status: Equatable { case notDetermined, denied, approved }

    private(set) var status: Status = .notDetermined
    private(set) var selections: [ScreenTimeSlot: FamilyActivitySelection] = [:]
    private(set) var lastError: String?
    /// Mirrors `SharedSettings.screenTimeEnabled` so views update.
    private(set) var enabled = false

    private let store = SharedStore.shared
    private let settings = SharedSettings.shared

    private init() {
        selections = Self.loadSelections()
        enabled = settings.screenTimeEnabled
        refreshStatus()
    }

    var isAuthorized: Bool { status == .approved }

    func hasApp(for slot: ScreenTimeSlot) -> Bool {
        !(selections[slot]?.applicationTokens.isEmpty ?? true)
    }

    /// Counting in the background right now.
    var isTracking: Bool { isAuthorized && enabled && ScreenTimeSlot.allCases.contains { hasApp(for: $0) } }

    // MARK: Authorization

    func refreshStatus() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined: status = .notDetermined
        case .denied: status = .denied
        default: status = .approved // .approved, and .approvedWithDataAccess on iOS 26.4+
        }
    }

    /// Face ID sheet the first time; instant afterwards.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "Screen Time access wasn't granted. You can try again anytime."
            Log.screenTime.error("authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
        return isAuthorized
    }

    // MARK: App picks

    /// Saves the picker result for a slot. Only apps count — a whole category
    /// would mix in time from apps that aren't reels feeds.
    func setSelection(_ selection: FamilyActivitySelection, for slot: ScreenTimeSlot) {
        var appsOnly = FamilyActivitySelection()
        appsOnly.applicationTokens = selection.applicationTokens
        if appsOnly.applicationTokens.isEmpty {
            selections[slot] = nil
            DeviceActivityCenter().stopMonitoring([Self.activityName(slot)])
        } else {
            selections[slot] = appsOnly
        }
        Self.saveSelections(selections)
        if enabled, selections[slot] != nil { startMonitoring(slot) }
    }

    // MARK: Monitoring

    func enable() {
        settings.screenTimeEnabled = true
        enabled = true
        ensureMonitoring(force: true)
        DarwinCenter.shared.post(DarwinName.settingsChanged)
    }

    func disable() {
        settings.screenTimeEnabled = false
        enabled = false
        DeviceActivityCenter().stopMonitoring(ScreenTimeSlot.allCases.map(Self.activityName) + [Self.watchdogName])
        DarwinCenter.shared.post(DarwinName.settingsChanged)
    }

    /// Re-registers monitoring when iOS dropped it, after a burst of premature
    /// thresholds (an iOS bug that also uses up the real ones), or when the
    /// threshold ladder changed. Cheap — call on every launch.
    func ensureMonitoring(force: Bool = false) {
        refreshStatus()
        guard isAuthorized, enabled else { return }
        let state = store.screenTime ?? ScreenTimeState()
        let active = Set(DeviceActivityCenter().activities.map(\.rawValue))
        for slot in ScreenTimeSlot.allCases where hasApp(for: slot) {
            let registration = state.registrations[slot.rawValue]
            let stale = registration?.ladderVersion != ScreenTimeLadder.version
                || state.needsRearmSince != nil
                || !active.contains(Self.activityName(slot).rawValue)
            if force || stale { startMonitoring(slot) }
        }
    }

    private func startMonitoring(_ slot: ScreenTimeSlot) {
        guard let selection = selections[slot], !selection.applicationTokens.isEmpty else { return }
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for minutes in ScreenTimeLadder.thresholds {
            events[DeviceActivityEvent.Name(ScreenTimeLadder.eventName(slot: slot, minutes: minutes))] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                threshold: DateComponents(hour: minutes / 60, minute: minutes % 60),
                includesPastActivity: false
            )
        }
        // Record the baseline first: thresholds count from this moment today.
        let now = Date()
        store.update(ScreenTimeState.self, in: .screenTime, default: { ScreenTimeState() }) { state in
            ScreenTimeEstimator.register(slot, at: now, in: &state)
        }
        do {
            try DeviceActivityCenter().startMonitoring(Self.activityName(slot), during: Self.dailySchedule, events: events)
            lastError = nil
            Log.screenTime.info("monitoring \(slot.rawValue, privacy: .public)")
        } catch {
            lastError = "Couldn't start Screen Time tracking (\(error.localizedDescription))."
            Log.screenTime.error("startMonitoring failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Pace calibration

    /// Learns the user's real pace from finished days where precise mode
    /// counted alongside Screen Time.
    func calibrateFromPreciseDays(exact: Ledger) {
        guard let state = store.screenTime else { return }
        let today = DayKey.today()
        var paces = settings.calibratedPaces
        var through = state.calibratedThrough
        var changed = false
        for slot in ScreenTimeSlot.allCases {
            let app = slot.app.rawValue
            let done = through[app].flatMap(DayKey.init(rawValue:))
            let days = state.days.values
                .filter { day in day.day < today && (done.map { day.day > $0 } ?? true) }
                .sorted { $0.day < $1.day }
            for day in days {
                let covered = day.coveredMinutes[app] ?? 0
                let reels = exact[day.day]?.count(for: slot.app) ?? 0
                if let pace = ScreenTimeEstimator.calibratedPace(previous: paces[app], exactReels: reels, coveredMinutes: covered) {
                    paces[app] = pace
                }
                through[app] = day.day.rawValue
                changed = true
            }
        }
        guard changed else { return }
        settings.calibratedPaces = paces
        store.update(ScreenTimeState.self, in: .screenTime, default: { ScreenTimeState() }) { $0.calibratedThrough = through }
    }

    /// The visit was closed by the "Reels App Closed" automation.
    func endSessionNow() {
        store.update(ScreenTimeState.self, in: .screenTime, default: { ScreenTimeState() }) { state in
            ScreenTimeEstimator.endSession(in: &state, at: Date(), idleFor: 0)
        }
    }

    // MARK: Names, schedule, persistence

    static func activityName(_ slot: ScreenTimeSlot) -> DeviceActivityName {
        DeviceActivityName(ScreenTimeLadder.activityName(for: slot))
    }

    static let watchdogName = DeviceActivityName(ScreenTimeLadder.watchdogActivity)

    /// Every day, all day (the system keys usage to the device's time zone).
    static var dailySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
    }

    private static func loadSelections() -> [ScreenTimeSlot: FamilyActivitySelection] {
        let stored = SharedStore.shared.read([String: FamilyActivitySelection].self, from: .screenTimeSelections) ?? [:]
        var result: [ScreenTimeSlot: FamilyActivitySelection] = [:]
        for (key, value) in stored {
            if let slot = ScreenTimeSlot(rawValue: key) { result[slot] = value }
        }
        return result
    }

    private static func saveSelections(_ selections: [ScreenTimeSlot: FamilyActivitySelection]) {
        var stored: [String: FamilyActivitySelection] = [:]
        for (slot, value) in selections { stored[slot.rawValue] = value }
        SharedStore.shared.write(stored, to: .screenTimeSelections)
    }
}
