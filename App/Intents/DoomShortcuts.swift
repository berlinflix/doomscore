import AppIntents

/// Actions that show up in Shortcuts, Spotlight and Siri with zero setup.
struct DoomShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReelsAppOpenedIntent(),
            phrases: ["\(.applicationName) reels app opened"],
            shortTitle: "Reels App Opened",
            systemImageName: "play.rectangle.on.rectangle"
        )
        AppShortcut(
            intent: ReelsAppClosedIntent(),
            phrases: ["\(.applicationName) reels app closed"],
            shortTitle: "Reels App Closed",
            systemImageName: "pause.rectangle"
        )
        AppShortcut(
            intent: ArmCounterIntent(),
            phrases: ["Start counting reels with \(.applicationName)", "Arm \(.applicationName)"],
            shortTitle: "Start Counting",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: TodayCountIntent(),
            phrases: ["How cooked am I in \(.applicationName)", "How many reels today in \(.applicationName)"],
            shortTitle: "How Cooked Am I",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
    }
}
