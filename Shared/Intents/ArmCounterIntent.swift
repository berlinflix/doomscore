import AppIntents

/// Opens Doomscore on today's count. Used by the Control Center button,
/// Siri/Shortcuts, and the widgets. Compiled into the app and the widget
/// extension, so it communicates through the App Group instead of touching
/// app state directly. (It never starts a screen broadcast.)
struct ArmCounterIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Doomscore"
    static var description = IntentDescription("Shows how many reels you've scrolled today.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedSettings.shared.pendingRoute = "today"
        return .result()
    }
}
