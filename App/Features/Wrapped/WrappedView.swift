import SwiftUI

/// Spotify-Wrapped-style story recap for a week / month / year.
/// Tap right = next, tap left = back, hold = pause.
struct WrappedView: View {
    let request: Router.WrappedRequest

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var progress: Double = 0
    @State private var paused = false
    @State private var shareImage: Image?

    private let slideDuration: Double = 5.5

    enum Slide: Hashable {
        case intro, total, time, distance, peak, bestDay, streak, dodged, archetype, share, empty
    }

    private var summary: PeriodSummary {
        StatsEngine.summary(for: request.period, containing: request.anchor, ledger: model.ledger, goal: model.goal, installDate: model.installDate)
    }

    var body: some View {
        let summary = self.summary
        let slides = makeSlides(summary)
        let slide = slides[min(index, slides.count - 1)]
        ZStack {
            NeonBackground(colors: palette(index))
                .animation(.easeInOut(duration: 0.6), value: index)

            // Tap zones sit under the content so the share slide's buttons stay tappable.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { go(-1, count: slides.count) }
                Color.clear.contentShape(Rectangle()).onTapGesture { go(1, count: slides.count) }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.25)
                    .onChanged { _ in paused = true }
                    .onEnded { _ in paused = false }
            )

            slideContent(slide, summary: summary)
                .id(index)
                .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
                .allowsHitTesting(slide == .share)
                .padding(.horizontal, 28)

            VStack(spacing: 14) {
                progressBars(count: slides.count)
                HStack {
                    Text("doomscore wrapped")
                        .font(Theme.body(14, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.black.opacity(0.35)))
                    }
                    .accessibilityLabel("Close recap")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .statusBarHidden()
        .task(id: index) { await runTimer(count: slides.count) }
        .task { renderShareCard(summary) }
    }

    // MARK: Slides

    private func makeSlides(_ s: PeriodSummary) -> [Slide] {
        guard s.total > 0 else { return [.intro, .empty] }
        var slides: [Slide] = [.intro, .total, .time, .distance]
        if s.peakHour != nil { slides.append(.peak) }
        if s.bestDay != nil, s.period != .day { slides.append(.bestDay) }
        slides.append(.streak)
        if s.adsSkipped + s.rewatchesSkipped > 0 { slides.append(.dodged) }
        slides += [.archetype, .share]
        return slides
    }

    private var periodName: String {
        switch request.period {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        }
    }

    @ViewBuilder
    private func slideContent(_ slide: Slide, summary s: PeriodSummary) -> some View {
        switch slide {
        case .intro:
            StorySlide(kicker: Fmt.periodTitle(request.period, interval: s.interval), title: "your \(periodName) in doom 📼") {
                GoobView(mood: Mood.from(count: Int(s.averagePerDay.rounded()), goal: model.goal), size: 170)
            }
        case .total:
            StorySlide(kicker: "you scrolled", title: "reels this \(periodName)") {
                VStack(spacing: 10) {
                    CountUpText(value: s.total)
                    if let change = s.changeVsPrevious {
                        Text(change > 0 ? "\(Fmt.percent(change)) vs last \(periodName). the algorithm is winning 😭" : "\(Fmt.percent(change)) vs last \(periodName). growth arc fr 🌱")
                            .font(Theme.body(17, weight: .bold))
                            .multilineTextAlignment(.center)
                    } else {
                        Text("≈ \(Int(s.averagePerDay.rounded())) a day")
                            .font(Theme.body(18, weight: .bold))
                    }
                }
            }
        case .time:
            StorySlide(kicker: "time spent watching", title: Fmt.duration(s.watchSeconds)) {
                Text(StatsEngine.movieComparison(seconds: s.watchSeconds))
                    .font(Theme.body(20, weight: .heavy))
                    .multilineTextAlignment(.center)
            }
        case .distance:
            StorySlide(kicker: "your thumb pushed", title: String(format: "%.0f meters", s.thumbMeters)) {
                Text(StatsEngine.distanceComparison(meters: s.thumbMeters))
                    .font(Theme.body(20, weight: .heavy))
                    .multilineTextAlignment(.center)
            }
        case .peak:
            StorySlide(kicker: "your doom hour", title: s.peakHour.map(Fmt.hour) ?? "—") {
                if let weekday = s.busiestWeekday, request.period != .day {
                    Text("and \(Fmt.weekday(weekday))s hit different 📆")
                        .font(Theme.body(20, weight: .heavy))
                        .multilineTextAlignment(.center)
                }
            }
        case .bestDay:
            StorySlide(kicker: "the most unhinged day", title: s.bestDay.map { Fmt.dayTitle($0.day) } ?? "—") {
                Text("\(s.bestDay?.count ?? 0) reels in one day 💀")
                    .font(Theme.body(22, weight: .heavy))
            }
        case .streak:
            StorySlide(kicker: "longest chill streak 🧊", title: "\(s.longestChillStreak) \(s.longestChillStreak == 1 ? "day" : "days")") {
                Text(s.longestChillStreak > 0 ? "days you stayed under your cap of \(model.goal). proud of u" : "no days under your cap… next \(periodName) is your redemption arc")
                    .font(Theme.body(19, weight: .bold))
                    .multilineTextAlignment(.center)
            }
        case .dodged:
            StorySlide(kicker: "we didn't count", title: "\(s.adsSkipped) ads 🥷") {
                Text("+ \(s.rewatchesSkipped) rewatches. only real reels count here.")
                    .font(Theme.body(19, weight: .bold))
                    .multilineTextAlignment(.center)
            }
        case .archetype:
            StorySlide(kicker: "your scroll personality", title: s.archetype.title) {
                VStack(spacing: 14) {
                    Text(s.archetype.emoji).font(.system(size: 96))
                    Text(s.archetype.blurb)
                        .font(Theme.body(18, weight: .bold))
                        .multilineTextAlignment(.center)
                }
            }
        case .share:
            VStack(spacing: 18) {
                if let shareImage {
                    shareImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(radius: 20)
                    ShareLink(item: shareImage, preview: SharePreview("my doomscore wrapped", image: shareImage)) {
                        Label("share to your story", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ChunkyButtonStyle())
                } else {
                    ProgressView().tint(.white)
                }
                Button("done") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.top, 60)
        case .empty:
            StorySlide(kicker: "nothing to wrap yet", title: "clean slate 🧼") {
                Text("arm the counter and scroll a bit — your recap builds itself.")
                    .font(Theme.body(19, weight: .bold))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func progressBars(count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white)
                                .frame(width: geo.size.width * (i < index ? 1 : (i == index ? progress : 0)))
                        }
                }
                .frame(height: 3.5)
            }
        }
        .padding(.top, 6)
    }

    private func palette(_ i: Int) -> [Color] {
        let palettes: [[Color]] = [
            [Theme.violet, Theme.pink, Theme.cyan],
            [Theme.lime, Theme.cyan, Theme.violet],
            [Theme.pink, Theme.orange, Theme.violet],
            [Theme.cyan, Theme.violet, Theme.lime],
            [Theme.orange, Theme.pink, Theme.yellow],
        ]
        return palettes[i % palettes.count]
    }

    // MARK: Navigation

    private func go(_ delta: Int, count: Int) {
        let next = index + delta
        guard next >= 0 else { progress = 0; return }
        guard next < count else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index = next }
    }

    private func runTimer(count: Int) async {
        progress = 0
        guard index < count - 1 else { progress = 1; return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            if paused { continue }
            progress += 0.05 / slideDuration
            if progress >= 1 {
                go(1, count: count)
                return
            }
        }
    }

    @MainActor
    private func renderShareCard(_ summary: PeriodSummary) {
        let card = ShareCardView(summary: summary, periodTitle: Fmt.periodTitle(request.period, interval: summary.interval), goal: model.goal)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let uiImage = renderer.uiImage { shareImage = Image(uiImage: uiImage) }
    }
}

/// Shared layout for text-heavy story slides.
private struct StorySlide<Accessory: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(kicker)
                .font(Theme.body(18, weight: .heavy))
                .textCase(.lowercase)
                .opacity(0.85)
            Text(title)
                .font(Theme.display(46))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(3)
            accessory
            Spacer()
            Spacer()
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 10)
    }
}

/// Big number that rolls up on appear.
private struct CountUpText: View {
    let value: Int
    @State private var shown = 0

    var body: some View {
        Text("\(shown)")
            .font(Theme.display(96))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear {
                withAnimation(.spring(response: 1.2, dampingFraction: 0.9)) { shown = value }
            }
    }
}
