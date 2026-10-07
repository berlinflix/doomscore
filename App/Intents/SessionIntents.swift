import AppIntents
import Foundation

enum ReelsAppOption: String, AppEnum {
    case instagram, youtube, tiktok, snapchat

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Reels App"
    static var caseDisplayRepresentations: [ReelsAppOption: DisplayRepresentation] = [
        .instagram: "Instagram",
        .youtube: "YouTube",
        .tiktok: "TikTok",
        .snapchat: "Snapchat",
    ]

    var sourceApp: SourceApp { SourceApp(rawValue: rawValue) ?? .other }
}

/// Run by the optional Shortcuts automation "When Instagram is opened → Run
/// Immediately". Runs in the background (no app launch):
///  1. records which reels app is in front (session timer + precise mode),
///  2. pops the Dynamic Island counter up instantly (a LiveActivityIntent may
///     start Live Activities from the background) — without the automation
///     it appears after the first minute, via push,
///  3. if nothing is tracking: a quiet "connect Screen Time" reminder. Exact
///     mode (screen broadcast) is only offered to people who switched that
///     on in Settings → exact mode.
struct ReelsAppOpenedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Reels App Opened"
    static var description = IntentDescription("Use in a Shortcuts automation when a reels app opens. Doomscore shows your live count in the Dynamic Island right away.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "App", default: .instagram)
    var app: ReelsAppOption

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$app) opened")
    }

    init() {}

    init(app: ReelsAppOption) {
        self.app = app
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let source = app.sourceApp
        let settings = SharedSettings.shared
        let store = SharedStore.shared
        let now = Date()

        store.write(ForegroundHint(app: source, openedAt: now, closedAt: nil), to: .hint)
        if settings.automationVerifiedAt == nil { settings.automationVerifiedAt = now }
        DarwinCenter.shared.post(DarwinName.hintChanged)

        guard settings.trackedApps.contains(source) else { return .result() }

        let precise = store.isArmed(now: now)
        let screenTime = ScreenTimeService.shared
        screenTime.refreshStatus()
        let auto = screenTime.isTracking && ScreenTimeSlot.allCases.contains { $0.app == source && screenTime.hasApp(for: $0) }
        await LiveActivityService.shared.showCounting(app: source, armed: precise || auto)
        await LiveActivityService.shared.waitForTokenRegistration()
        if precise { return .result() }

        // Exact mode (screen broadcast) is only ever offered to people who
        // switched it on in Settings → exact mode.
        guard settings.preciseAutoPrompt else {
            if !auto { await NotificationService.sendTrackingNudge(for: source) }
            return .result()
        }

        #if DS_INTENT_MODES && compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if await continueToArmScreen(returnTo: source) { return .result() }
        }
        #endif

        await NotificationService.sendExactModeNudge(for: source)
        return .result()
    }
}

/// Optional second automation: "When Instagram is closed".
struct ReelsAppClosedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Reels App Closed"
    static var description = IntentDescription("Use in a Shortcuts automation when a reels app closes. Wraps up the live counter and saves battery.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "App", default: .instagram)
    var app: ReelsAppOption

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$app) closed")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let source = app.sourceApp
        let now = Date()
        let settings = SharedSettings.shared
        SharedStore.shared.update(ForegroundHint.self, in: .hint, default: { ForegroundHint(app: source, openedAt: now, closedAt: now) }) { hint in
            if hint.app == source { hint.closedAt = now }
        }
        if settings.closeAutomationSeenAt == nil { settings.closeAutomationSeenAt = now }
        DarwinCenter.shared.post(DarwinName.hintChanged)
        ScreenTimeService.shared.endSessionNow()
        await LiveActivityService.shared.endSession()
        return .result()
    }
}

/// "Hey Siri, how cooked am I?"
struct TodayCountIntent: AppIntent {
    static var title: LocalizedStringResource = "How Cooked Am I?"
    static var description = IntentDescription("Tells you how many reels you've scrolled today.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let record = SharedStore.shared.todayRecord()
        let today = record.total
        let mood = Mood.from(count: today, goal: SharedSettings.shared.dailyGoal)
        let text = "\(record.isEstimated ? "About " : "")\(today) reels today. \(mood.title) \(mood.emoji)"
        return .result(value: today, dialog: IntentDialog(stringLiteral: text))
    }
}
