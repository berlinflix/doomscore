import SwiftUI

/// Measures how fast you swipe reels — no screen recording. Open Instagram,
/// scroll ~20 reels at your normal speed, come back, say how many. Doomscore
/// times the trip and uses the result to turn Screen Time minutes into reels.
struct PaceTestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var step: Step = .intro
    @State private var startedAt: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var reels = 20
    @State private var speed: Double?
    @State private var problem: String?

    private enum Step { case intro, away, count, done }

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(Theme.textFaint).frame(width: 40, height: 5).padding(.top, 10)
            Spacer(minLength: 0)
            switch step {
            case .intro: intro
            case .away: away
            case .count: count
            case .done: done
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .screenBackground()
        .onChange(of: scenePhase) { _, phase in
            // Back from Instagram: stop the clock.
            guard phase == .active, step == .away, let startedAt else { return }
            elapsed = Date().timeIntervalSince(startedAt)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = .count }
        }
        .sensoryFeedback(.success, trigger: step == .done)
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Text("⏱️").font(.system(size: 64))
            Text("pace test")
                .font(Theme.display(32))
                .foregroundStyle(Theme.text)
            Text("open Reels, scroll about 20 reels at your normal speed, then come straight back here. we just time the trip — nothing is recorded.")
                .font(Theme.body(16, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textDim)
            Button {
                startedAt = Date()
                step = .away
                if let url = SourceApp.instagram.launchURL { openURL(url) }
            } label: {
                Label("start — open Instagram", systemImage: "play.fill")
            }
            .buttonStyle(ChunkyButtonStyle())
            Button("not now") { dismiss() }
                .buttonStyle(GhostButtonStyle())
        }
    }

    private var away: some View {
        VStack(spacing: 14) {
            Text("👀").font(.system(size: 64))
            Text("go scroll ~20 reels")
                .font(Theme.display(28))
                .foregroundStyle(Theme.text)
            Text("come back to Doomscore when you're done — the clock stops when you return.")
                .font(Theme.body(15, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textDim)
        }
    }

    private var count: some View {
        VStack(spacing: 16) {
            Text("you were gone \(Fmt.duration(elapsed))")
                .font(Theme.display(26))
                .foregroundStyle(Theme.text)
            Text("how many reels did you scroll?")
                .font(Theme.body(16, weight: .bold))
                .foregroundStyle(Theme.textDim)
            Text("\(reels)")
                .font(Theme.display(72))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText(value: Double(reels)))
            Stepper("reels", value: $reels, in: 5...200)
                .labelsHidden()
                .sensoryFeedback(.selection, trigger: reels)
            if let problem {
                Text(problem)
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.orange)
                    .multilineTextAlignment(.center)
            }
            Button("save my pace") { save() }
                .buttonStyle(ChunkyButtonStyle())
            Button("try again") {
                problem = nil
                step = .intro
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Text("🔥").font(.system(size: 64))
            Text(String(format: "%.1f reels a minute", speed ?? 0))
                .font(Theme.display(30))
                .foregroundStyle(Theme.text)
            Text("that's your swipe speed. Doomscore uses it from now on to turn your Screen Time minutes into reels.")
                .font(Theme.body(15, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textDim)
            Button("done") { dismiss() }
                .buttonStyle(ChunkyButtonStyle())
        }
    }

    private func save() {
        guard let measured = PaceTest.reelSpeed(reels: reels, elapsed: elapsed) else {
            problem = "that doesn't add up — scroll for at least 20 seconds and count the reels, then try again."
            return
        }
        model.setReelSpeed(measured)
        speed = measured
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = .done }
    }
}
