// iOS 26 App Intents "supportedModes": lets the background automation intent
// bring Doomscore to the foreground only when the counter needs arming.
//
// Enabled by the DS_INTENT_MODES flag in Config/Base.xcconfig. If your Xcode
// flags anything in this file, remove that flag and regenerate the project —
// the app falls back to the Live Activity + notification nudge.

#if DS_INTENT_MODES && compiler(>=6.2)
import AppIntents

@available(iOS 26.0, *)
extension ReelsAppOpenedIntent {
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    /// Returns true if the app came forward and the arm screen is showing.
    @MainActor
    func continueToArmScreen(returnTo app: SourceApp) async -> Bool {
        guard systemContext.currentMode.canContinueInForeground else { return false }
        do {
            try await continueInForeground(alwaysConfirm: false)
        } catch {
            return false
        }
        AppModel.shared.router.sheet = .arm(auto: true, returnTo: app)
        return true
    }
}
#endif
