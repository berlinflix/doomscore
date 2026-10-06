import SwiftUI

/// Optional one-time Shortcuts automation. Auto mode (Screen Time) already
/// counts without it; the automation makes the Dynamic Island appear the
/// instant a reels app opens (instead of after the first minute) and close
/// when it closes. With precise mode it can also bring up the one-tap arm
/// screen (iOS 26+) or a nudge (older iOS).
struct AutomationGuideView: View {
    var showsDoneButton = false

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let steps: [(symbol: String, title: String, detail: String)] = [
        ("square.stack.3d.up.fill", "Open Shortcuts → Automation", "Tap the Automation tab at the bottom, then +."),
        ("app.badge.fill", "Choose “App”", "Select Instagram (add YouTube / TikTok too if you want). Keep “Is Opened” ticked."),
        ("bolt.fill", "Pick “Run Immediately”", "Turn OFF “Notify When Run” so it's invisible. Tap Next."),
        ("magnifyingglass", "Add “Reels App Opened”", "Search Doomscore → pick “Reels App Opened” → set the app → Done."),
        ("plus.square.on.square", "Recommended: “Is Closed” too", "Make a second automation with “Is Closed” → “Reels App Closed”. The island closes the moment you leave."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("instant island ⚡️")
                        .font(Theme.display(32))
                        .foregroundStyle(Theme.text)
                    Text("optional. your count already updates on its own — this makes the Dynamic Island pop up the second you open Instagram. 30 seconds, once.")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                }

                statusCard

                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(Theme.body(16, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(index == 4 ? AnyShapeStyle(Theme.surfaceHigh) : AnyShapeStyle(Theme.brand)))
                        VStack(alignment: .leading, spacing: 4) {
                            Label(step.title, systemImage: step.symbol)
                                .font(Theme.body(16, weight: .heavy))
                                .foregroundStyle(Theme.text)
                            Text(step.detail)
                                .font(Theme.body(14, weight: .semibold))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                }

                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("open Shortcuts", systemImage: "arrow.up.forward.app.fill")
                }
                .buttonStyle(ChunkyButtonStyle())

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("pro tip: precise mode from Control Center 🎛️")
                            .font(Theme.body(15, weight: .heavy))
                            .foregroundStyle(Theme.text)
                        Text("Add the “Count Reels” control, or long-press Screen Recording → pick Doomscore → Start Broadcast. Starts precise mode without opening the app.")
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                    }
                }

                if showsDoneButton {
                    Button("done") { dismiss() }
                        .buttonStyle(GhostButtonStyle())
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
    }

    private var statusCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: model.automationVerified ? "checkmark.seal.fill" : "hourglass")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(model.automationVerified ? Theme.lime : Theme.textDim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.automationVerified ? "instant island works ✅" : "waiting for the first run…")
                        .font(Theme.body(16, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    Text(model.automationVerified
                         ? (model.closeAutomationSeen ? "open + close automations both detected" : "open a reels app anytime — we'll be there")
                         : "open Instagram once after setting it up, then come back")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }
}
