import Charts
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                hero
                if model.trackingMode == .off { ScreenTimeConnectCard(showsTikTok: false) }
                if model.trackingMode == .auto && model.paceSource == .guess { paceCard }
                if model.trackingMode == .auto && !model.automationVerified { autoStartCard }
                appChips
                statsGrid
                hourlyCard
                wrappedTeaser
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .sensoryFeedback(.increase, trigger: model.today.total)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.trackingMode)
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center) {
            Text("doomscore")
                .font(Theme.display(28))
                .foregroundStyle(Theme.brand)
            Spacer()
            StatusPill(mode: model.trackingMode)
            Button {
                router.sheet = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.surfaceHigh))
            }
            .accessibilityLabel("Settings")
        }
    }

    private var hero: some View {
        let today = model.today
        return VStack(spacing: 14) {
            SpeechBubble(text: model.mood.quip(seed: model.daySeed))
                .padding(.top, 6)
            GoobView(mood: model.mood, size: 190)
                .padding(.vertical, 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if today.isEstimated {
                    Text("≈")
                        .font(Theme.display(44))
                        .foregroundStyle(Theme.textFaint)
                }
                Text("\(today.total)")
                    .font(Theme.display(84))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: Double(today.total)))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: today.total)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(today.isEstimated ? "about " : "")\(today.total) reels today")
            Text("reels today · \(model.mood.title) \(model.mood.emoji)")
                .font(Theme.body(16, weight: .bold))
                .foregroundStyle(Theme.textDim)
            if today.isEstimated || today.screenMinutes > 0 {
                estimateNote(today)
            }
            VStack(spacing: 8) {
                CapBar(count: today.total, goal: model.goal)
                HStack {
                    Text(model.sessionCount > 0 ? "this session: \(model.sessionCount)" : "daily cap")
                    Spacer()
                    Text("\(today.total) / \(model.goal)")
                }
                .font(Theme.body(13, weight: .bold))
                .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 12)
    }

    /// Makes clear what's measured (minutes) and what's estimated (reels).
    private func estimateNote(_ today: DayRecord) -> some View {
        let pace = model.pace(for: .instagram)
        return HStack(spacing: 6) {
            Image(systemName: "hourglass")
            Text("\(today.screenMinutes) min of scrolling × \(String(format: "%.1f", pace))/min (\(model.paceSource == .guess ? "est." : "your pace"))")
        }
        .font(Theme.body(12, weight: .bold))
        .foregroundStyle(Theme.cyan)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.cyan.opacity(0.1)))
    }

    /// The pace test: the no-screen-recording way to make the count accurate.
    private var paceCard: some View {
        Button {
            router.sheet = .paceTest
        } label: {
            Card {
                HStack(spacing: 14) {
                    Text("⏱️").font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("dial in your pace")
                            .font(Theme.body(16, weight: .heavy))
                            .foregroundStyle(Theme.text)
                        Text("30-sec test: scroll 20 reels, we time you. makes your count way more accurate — no screen recording")
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.textFaint)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    private var autoStartCard: some View {
        Button {
            router.sheet = .setupGuide
        } label: {
            Card {
                HStack(spacing: 14) {
                    Text("⚡️").font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("instant Dynamic Island")
                            .font(Theme.body(16, weight: .heavy))
                            .foregroundStyle(Theme.text)
                        Text("30-sec Shortcuts setup: your count pops up the second you open Instagram")
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.textFaint)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    private var appChips: some View {
        let today = model.today
        let apps = SourceApp.tracked.filter { model.trackedApps.contains($0) }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(apps) { app in
                    AppChip(app: app, count: today.count(for: app))
                }
                if today.count(for: .other) > 0 {
                    AppChip(app: .other, count: today.count(for: .other))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var statsGrid: some View {
        let today = model.today
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(
                emoji: model.streak.todayAlive ? "🧊" : "🫗",
                value: "\(model.streak.current)d",
                label: model.streak.todayAlive ? "chill streak (best \(model.streak.best)d)" : "streak broke today. tomorrow's a new era",
                tint: Theme.cyan
            )
            StatTile(emoji: "⏱️", value: Fmt.duration(today.watchSeconds), label: "time scrolling", tint: Theme.text)
            if today.adsSkipped > 0 || today.rewatchesSkipped > 0 || model.trackingMode == .precise {
                StatTile(emoji: "🥷", value: "\(today.adsSkipped)", label: "ads dodged (not counted)", tint: Theme.lime)
                StatTile(emoji: "🔁", value: "\(today.rewatchesSkipped)", label: "rewatches (not counted)", tint: Theme.pink)
            } else {
                StatTile(emoji: "🔂", value: "\(today.sessions)", label: "times you opened the scroll hole", tint: Theme.lime)
                StatTile(
                    emoji: "🎚️",
                    value: String(format: "%.1f/min", model.pace(for: .instagram)),
                    label: model.paceSource == .guess ? "starting pace — take the pace test" : "your measured pace",
                    tint: Theme.pink
                )
            }
        }
    }

    private var hourlyCard: some View {
        let hours = model.today.hourly
        let peak = hours.max() ?? 0
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "today by hour", trailing: peak > 0 ? "peak \(Fmt.hour(hours.firstIndex(of: peak) ?? 0))" : nil)
                Chart {
                    ForEach(0..<24, id: \.self) { hour in
                        BarMark(x: .value("Hour", hour), y: .value("Reels", hours[hour]))
                            .foregroundStyle(hours[hour] == peak && peak > 0 ? AnyShapeStyle(Theme.hot) : AnyShapeStyle(Theme.brand))
                            .cornerRadius(4)
                    }
                }
                .chartXScale(domain: 0...23)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisValueLabel {
                            if let hour = value.as(Int.self) { Text(Fmt.hour(hour)) }
                        }
                        .foregroundStyle(Theme.textFaint)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel().foregroundStyle(Theme.textFaint)
                    }
                }
                .frame(height: 140)
            }
        }
    }

    private var wrappedTeaser: some View {
        Button {
            router.wrapped = Router.WrappedRequest(period: .week, anchor: Date())
        } label: {
            ZStack(alignment: .leading) {
                NeonBackground(animated: false)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("your week in doom 📼")
                        .font(Theme.body(20, weight: .black))
                    Text("story-style recap. screenshot-ready.")
                        .font(Theme.body(14, weight: .semibold))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(height: 110)
        }
        .buttonStyle(PressableStyle())
    }
}
