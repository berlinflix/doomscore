import ActivityKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var page = 0
    @State private var goal = 100.0
    @State private var notificationsGranted = false

    private let pageCount = 5

    var body: some View {
        ZStack {
            NeonBackground(colors: [Theme.violet, Theme.lime, Theme.pink])
                .opacity(0.45)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Capsule()
                            .fill(i <= page ? Theme.lime : Theme.surfaceHigh)
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                TabView(selection: $page) {
                    welcome.tag(0)
                    howItWorks.tag(1)
                    capPicker.tag(2)
                    autoStart.tag(3)
                    finish.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: page)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { goal = Double(model.goal) }
    }

    // MARK: Pages

    private var welcome: some View {
        OnboardingPage(
            title: "how cooked are you? 🍳",
            subtitle: "Doomscore counts every reel you swipe on Instagram, YouTube Shorts & TikTok. no ads. no rewatches. no cap."
        ) {
            GoobView(mood: .kindaCooked, size: 200)
        } footer: {
            Button("let's see") { next() }.buttonStyle(ChunkyButtonStyle())
        }
    }

    private var howItWorks: some View {
        OnboardingPage(
            title: "how it works",
            subtitle: "iPhone doesn't let apps read other apps, so we use the one thing it allows: screen broadcast — processed on-device, never recorded."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                bullet("hand.draw.fill", "we detect swipes, not content", "motion + a quick look at the overlay (like the “Sponsored” label)")
                bullet("lock.shield.fill", "nothing leaves your phone", "no video, no screenshots. only the daily number syncs to battles")
                bullet("iphone.radiowaves.left.and.right", "you'll see a red pill up top", "that's iOS showing the counter is on. tap it to stop anytime")
            }
        } footer: {
            Button("makes sense") { next() }.buttonStyle(ChunkyButtonStyle())
        }
    }

    private var capPicker: some View {
        let mood = Mood.from(count: Int(goal * 0.8), goal: 100)
        return OnboardingPage(
            title: "set your daily cap",
            subtitle: "your meter maxes out here. stay under it to build a chill streak 🧊"
        ) {
            VStack(spacing: 14) {
                Text("\(Int(goal))")
                    .font(Theme.display(76))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: goal))
                Text("reels / day")
                    .font(Theme.body(16, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                Slider(value: $goal, in: 10...400, step: 10)
                    .tint(mood.tint)
                    .padding(.horizontal, 10)
                Text(goal <= 50 ? "monk mode 🧘" : goal <= 150 ? "balanced king/queen 👑" : "we don't judge (we do) 💀")
                    .font(Theme.body(15, weight: .heavy))
                    .foregroundStyle(Theme.text)
            }
            .sensoryFeedback(.selection, trigger: goal)
        } footer: {
            Button("lock it in") {
                model.setGoal(Int(goal))
                next()
            }
            .buttonStyle(ChunkyButtonStyle())
        }
    }

    private var autoStart: some View {
        VStack(spacing: 0) {
            AutomationGuideView()
            HStack(spacing: 10) {
                Button("later") { next() }.buttonStyle(GhostButtonStyle())
                Button("done ✅") { next() }.buttonStyle(ChunkyButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var finish: some View {
        OnboardingPage(
            title: "last thing",
            subtitle: "turn on notifications for nudges when the counter's off + your weekly wrapped. Live Activities show your count in the Dynamic Island."
        ) {
            VStack(spacing: 14) {
                GoobView(mood: .fresh, size: 150)
                Label(notificationsGranted ? "notifications on" : "notifications off", systemImage: notificationsGranted ? "bell.badge.fill" : "bell.slash")
                    .font(Theme.body(15, weight: .heavy))
                    .foregroundStyle(notificationsGranted ? Theme.lime : Theme.textDim)
                if !ActivityAuthorizationInfo().areActivitiesEnabled {
                    Text("Live Activities are off for Doomscore — enable them in Settings to see your count in the Dynamic Island.")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .multilineTextAlignment(.center)
                }
            }
        } footer: {
            VStack(spacing: 10) {
                if !notificationsGranted {
                    Button("allow notifications") {
                        Task { notificationsGranted = await NotificationService.requestAuthorization() }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                Button("arm the counter 🚀") {
                    model.completeOnboarding()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        router.sheet = .arm(auto: false, returnTo: nil)
                    }
                }
                .buttonStyle(ChunkyButtonStyle())
            }
        }
        .task { notificationsGranted = await NotificationService.isAuthorized() }
    }

    private func bullet(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.brand))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.body(16, weight: .heavy)).foregroundStyle(Theme.text)
                Text(detail).font(Theme.body(14, weight: .semibold)).foregroundStyle(Theme.textDim)
            }
        }
    }

    private func next() {
        withAnimation { page = min(page + 1, pageCount - 1) }
    }
}

private struct OnboardingPage<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            content
            VStack(spacing: 10) {
                Text(title)
                    .font(Theme.display(32))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(Theme.body(16, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 10)
            footer
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}
