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
                if !model.isArmed { armCard }
                if !model.automationVerified { autoStartCard }
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
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.isArmed)
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center) {
            Text("doomscore")
                .font(Theme.display(28))
                .foregroundStyle(Theme.brand)
            Spacer()
            StatusPill(isArmed: model.isArmed)
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
            Text("\(today.total)")
                .font(Theme.display(84))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText(value: Double(today.total)))
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: today.total)
                .accessibilityLabel("\(today.total) reels today")
            Text("reels today · \(model.mood.title) \(model.mood.emoji)")
                .font(Theme.body(16, weight: .bold))
                .foregroundStyle(Theme.textDim)
            VStack(spacing: 8) {
                CapBar(count: today.total, goal: model.goal)
                HStack {
                    Text(model.isArmed && model.sessionCount > 0 ? "this session: \(model.sessionCount)" : "daily cap")
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

    private var armCard: some View {
        Button {
            router.sheet = .arm(auto: false, returnTo: nil)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "record.circle")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
                    .symbolEffect(.pulse, options: .repeating)
                VStack(alignment: .leading, spacing: 2) {
                    Text("arm the counter")
                        .font(Theme.body(17, weight: .black))
                    Text("one tap, then go scroll. we'll handle the rest.")
                        .font(Theme.body(13, weight: .semibold))
                        .opacity(0.75)
                }
                .foregroundStyle(.black)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .black)).foregroundStyle(.black)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.brand))
        }
        .buttonStyle(PressableStyle())
        .transition(.scale.combined(with: .opacity))
    }

    private var autoStartCard: some View {
        Button {
            router.sheet = .setupGuide
        } label: {
            Card {
                HStack(spacing: 14) {
                    Text("⚡️").font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("auto-start when you open reels")
                            .font(Theme.body(16, weight: .heavy))
                            .foregroundStyle(Theme.text)
                        Text("30-sec Shortcuts setup so you never forget to count")
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
            StatTile(emoji: "⏱️", value: Fmt.duration(today.watchSeconds), label: "time in reels", tint: Theme.text)
            StatTile(emoji: "🥷", value: "\(today.adsSkipped)", label: "ads dodged (not counted)", tint: Theme.lime)
            StatTile(emoji: "🔁", value: "\(today.rewatchesSkipped)", label: "rewatches (not counted)", tint: Theme.pink)
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
                    Text("wrapped-style recap. screenshot-ready.")
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
