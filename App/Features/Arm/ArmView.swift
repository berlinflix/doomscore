import ReplayKit
import SwiftUI

/// Precise mode: starts the screen-broadcast extension that counts every reel
/// swipe (skipping ads and rewatches). Optional — auto mode (Screen Time)
/// works without it. iOS requires one confirmation tap in the system sheet —
/// we open that sheet automatically and bounce the user back to their reels
/// app as soon as counting is live.
struct ArmView: View {
    let auto: Bool
    let returnTo: SourceApp?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var picker = BroadcastPickerController()
    @State private var phase: Phase = .ready
    @State private var startsAtAppear = 0

    private enum Phase { case ready, waiting, live }

    var body: some View {
        ZStack {
            NeonBackground(colors: [Theme.lime, Theme.violet, Theme.cyan], animated: phase != .live)
                .opacity(0.55)
            VStack(spacing: 22) {
                Capsule().fill(Theme.textFaint).frame(width: 40, height: 5).padding(.top, 10)
                Spacer(minLength: 0)
                GoobView(mood: phase == .live ? .chill : .lowkey, size: 150)
                Text(title)
                    .font(Theme.display(32))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(Theme.body(16, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textDim)
                    .padding(.horizontal, 24)

                if phase != .live {
                    privacyCard
                }
                Spacer(minLength: 0)

                if phase == .live {
                    Button(returnTo.map { "back to \($0.displayName)" } ?? "let's go") { finish() }
                        .buttonStyle(ChunkyButtonStyle())
                } else {
                    Button {
                        phase = .waiting
                        picker.trigger()
                    } label: {
                        Label("start exact mode", systemImage: "record.circle.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle())
                    Text("then tap **Start Broadcast** · stop anytime from the red status pill")
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .multilineTextAlignment(.center)
                }

                // The real system picker, kept tiny and invisible; we tap it programmatically.
                BroadcastPickerHost(controller: picker)
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            startsAtAppear = model.broadcastStarts
            if model.isArmed {
                phase = .live
            } else if auto {
                phase = .waiting
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { picker.trigger() }
            }
        }
        .onChange(of: model.broadcastStarts) { _, newValue in
            guard newValue > startsAtAppear else { return }
            goLive()
        }
        .onChange(of: model.isArmed) { _, armed in
            if armed { goLive() }
        }
        .sensoryFeedback(.success, trigger: phase == .live)
    }

    private var title: String {
        switch phase {
        case .ready: "exact mode 🎯"
        case .waiting: "tap Start Broadcast 👇"
        case .live: "exact mode is on ✅"
        }
    }

    private var subtitle: String {
        switch phase {
        case .ready: "counts every single reel — skips ads + rewatches — and teaches auto mode your real pace. totally optional."
        case .waiting: "that's iOS's standard screen-broadcast sheet. iOS words it scary; we only look for swipes."
        case .live: returnTo.map { "sending you back to \($0.displayName)…" } ?? "go scroll. we'll keep exact count."
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("analysed on your phone, never recorded or uploaded", systemImage: "lock.fill")
            Label("only the daily number syncs to your battles", systemImage: "number")
            Label("stop anytime: tap the red pill up top", systemImage: "hand.tap.fill")
            Label("don't want this? auto mode needs none of it", systemImage: "hourglass")
        }
        .font(Theme.body(14, weight: .bold))
        .foregroundStyle(Theme.text)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface.opacity(0.85)))
    }

    private func goLive() {
        guard phase != .live else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { phase = .live }
        Task { await LiveActivityService.shared.showCounting(app: returnTo, armed: true) }
        if returnTo != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { finish() }
        }
    }

    private func finish() {
        dismiss()
        if let url = returnTo?.launchURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { openURL(url) }
        }
    }
}

/// Holds the system broadcast picker so SwiftUI buttons can trigger it.
@MainActor
final class BroadcastPickerController {
    let view: RPSystemBroadcastPickerView

    init() {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = AppEnvironment.broadcastExtensionID
        picker.showsMicrophoneButton = false
        view = picker
    }

    /// Opens the system "Start Broadcast" sheet (same as tapping the picker).
    func trigger() {
        guard let button = Self.findButton(in: view) else { return }
        button.sendActions(for: .allTouchEvents)
    }

    private static func findButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }
}

struct BroadcastPickerHost: UIViewRepresentable {
    let controller: BroadcastPickerController

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        container.addSubview(controller.view)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
