import Foundation

/// Small preferences shared across the app and its extensions (App Group suite).
final class SharedSettings: @unchecked Sendable {
    static let shared = SharedSettings()

    let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppEnvironment.appGroupID) ?? .standard
    }

    private enum Key: String {
        case dailyGoal, trackedApps, onboardingComplete, automationVerifiedAt, installDate
        case nudgesEnabled, lastNudgeAt, strictPrivacyMode, diagnosticsEnabled, pendingRoute
        case identitySalt, deviceRegisteredAt, closeAutomationSeenAt
    }

    /// Daily cap ("goal") — the number where the mood meter maxes out.
    var dailyGoal: Int {
        get {
            let value = defaults.integer(forKey: Key.dailyGoal.rawValue)
            return value > 0 ? value : 100
        }
        set { defaults.set(min(max(newValue, 5), 2000), forKey: Key.dailyGoal.rawValue) }
    }

    var trackedApps: Set<SourceApp> {
        get {
            guard let raw = defaults.stringArray(forKey: Key.trackedApps.rawValue) else { return Set(SourceApp.tracked) }
            return Set(raw.compactMap(SourceApp.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.trackedApps.rawValue) }
    }

    var onboardingComplete: Bool {
        get { defaults.bool(forKey: Key.onboardingComplete.rawValue) }
        set { defaults.set(newValue, forKey: Key.onboardingComplete.rawValue) }
    }

    /// First time the "Reels App Opened" automation actually ran.
    var automationVerifiedAt: Date? {
        get { defaults.object(forKey: Key.automationVerifiedAt.rawValue) as? Date }
        set { defaults.set(newValue, forKey: Key.automationVerifiedAt.rawValue) }
    }

    /// First time the optional "Reels App Closed" automation ran.
    var closeAutomationSeenAt: Date? {
        get { defaults.object(forKey: Key.closeAutomationSeenAt.rawValue) as? Date }
        set { defaults.set(newValue, forKey: Key.closeAutomationSeenAt.rawValue) }
    }

    var installDate: Date {
        if let date = defaults.object(forKey: Key.installDate.rawValue) as? Date { return date }
        let now = Date()
        defaults.set(now, forKey: Key.installDate.rawValue)
        return now
    }

    /// Nudge notification when a reels app opens while the counter is off.
    var nudgesEnabled: Bool {
        get { defaults.object(forKey: Key.nudgesEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.nudgesEnabled.rawValue) }
    }

    var lastNudgeAt: Date? {
        get { defaults.object(forKey: Key.lastNudgeAt.rawValue) as? Date }
        set { defaults.set(newValue, forKey: Key.lastNudgeAt.rawValue) }
    }

    /// When on, the detector only reads the screen while a Shortcuts
    /// automation reports that a reels app is in the foreground.
    var strictPrivacyMode: Bool {
        get { defaults.bool(forKey: Key.strictPrivacyMode.rawValue) }
        set { defaults.set(newValue, forKey: Key.strictPrivacyMode.rawValue) }
    }

    var diagnosticsEnabled: Bool {
        get { defaults.bool(forKey: Key.diagnosticsEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.diagnosticsEnabled.rawValue) }
    }

    /// Route requested by an extension/intent that runs outside the app
    /// process (e.g. the Control Center button). Consumed on next launch.
    var pendingRoute: String? {
        get { defaults.string(forKey: Key.pendingRoute.rawValue) }
        set { defaults.set(newValue, forKey: Key.pendingRoute.rawValue) }
    }

    func consumePendingRoute() -> String? {
        let route = pendingRoute
        pendingRoute = nil
        return route
    }

    /// Per-install random salt used when persisting reel fingerprints.
    var identitySalt: String {
        if let salt = defaults.string(forKey: Key.identitySalt.rawValue) { return salt }
        let salt = UUID().uuidString
        defaults.set(salt, forKey: Key.identitySalt.rawValue)
        return salt
    }

    var deviceRegisteredAt: Date? {
        get { defaults.object(forKey: Key.deviceRegisteredAt.rawValue) as? Date }
        set { defaults.set(newValue, forKey: Key.deviceRegisteredAt.rawValue) }
    }
}
