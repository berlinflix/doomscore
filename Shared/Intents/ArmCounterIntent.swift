import AppIntents

/// Opens Doomscore on the "arm the counter" screen. Used by the Control Center
/// button, Siri/Shortcuts, and the widgets. Compiled into the app and the
/// widget extension, so it communicates through the App Group instead of
/// touching app state directly.
struct ArmCounterIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Counting Reels"
    static var description = IntentDescription("Opens Doomscore ready to start the reel counter.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedSettings.shared.pendingRoute = "arm"
        return .result()
    }
}
