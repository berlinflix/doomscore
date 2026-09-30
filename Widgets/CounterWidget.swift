import SwiftUI
import WidgetKit

// MARK: - Timeline

struct CounterEntry: TimelineEntry {
    let date: Date
    let today: DayRecord
    let goal: Int
    let streak: Int
    let armed: Bool

    var mood: Mood { Mood.from(count: today.total, goal: goal) }

    static var placeholder: CounterEntry {
        var record = DayRecord(day: DayKey.today())
        record.total = 42
        record.perApp = ["instagram": 42]
        record.hourly = [0, 0, 0, 0, 0, 0, 0, 1, 3, 2, 0, 0, 4, 6, 2, 0, 0, 1, 5, 8, 6, 3, 1, 0]
        return CounterEntry(date: Date(), today: record, goal: 100, streak: 3, armed: true)
    }
}

struct CounterProvider: TimelineProvider {
    func placeholder(in context: Context) -> CounterEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (CounterEntry) -> Void) {
        completion(context.isPreview ? .placeholder : load(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CounterEntry>) -> Void) {
        let now = Date()
        let entry = load(at: now)
        // Reset exactly at midnight, otherwise refresh every 30 min
        // (the extension also pokes WidgetKit when sessions end).
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let midnightEntry = CounterEntry(date: midnight, today: DayRecord(day: DayKey(midnight)), goal: entry.goal, streak: entry.streak, armed: false)
        let refresh = min(midnight, now.addingTimeInterval(30 * 60))
        completion(Timeline(entries: [entry, midnightEntry], policy: .after(refresh)))
    }

    private func load(at date: Date) -> CounterEntry {
        let store = SharedStore.shared
        let settings = SharedSettings.shared
        let ledger = store.mergedLedger()
        let key = DayKey(date)
        let streak = StatsEngine.streak(ledger: ledger, goal: settings.dailyGoal, installDate: settings.installDate, now: date)
        return CounterEntry(
            date: date,
            today: ledger[key] ?? DayRecord(day: key),
            goal: settings.dailyGoal,
            streak: streak.current,
            armed: store.isArmed(now: date)
        )
    }
}

// MARK: - Widget

struct CounterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoomCounter", provider: CounterProvider()) { entry in
            CounterWidgetView(entry: entry)
        }
        .configurationDisplayName("Reel Counter")
        .description("Today's reels, your cap and how cooked you are.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CounterWidgetView: View {
    let entry: CounterEntry
    @Environment(\.widgetFamily) private var family

    private var tapURL: URL? {
        URL(string: entry.armed ? "doomscore://today" : "doomscore://arm")
    }

    var body: some View {
        content
            .widgetURL(tapURL)
            .containerBackground(for: .widget) {
                ZStack {
                    Theme.bg
                    LinearGradient(colors: [entry.mood.tint.opacity(0.28), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(entry.today.total)")
                        .font(Theme.display(40))
                        .foregroundStyle(Theme.text)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: Double(entry.today.total)))
                    Text("reels today")
                        .font(Theme.body(12, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 0)
                GoobView(mood: entry.mood, size: 46, animated: false)
                    .offset(x: 6, y: -6)
            }
            Spacer(minLength: 6)
            CapBar(count: entry.today.total, goal: entry.goal, segments: 10, height: 9)
            Text("\(entry.today.total)/\(entry.goal) cap")
                .font(Theme.body(10, weight: .bold))
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 4)
            Spacer(minLength: 6)
            Text("\(entry.mood.title) \(entry.mood.emoji)")
                .font(Theme.body(12, weight: .heavy))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(entry.mood.gradient))
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            small
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(entry.armed ? "counting" : "off", systemImage: entry.armed ? "record.circle.fill" : "record.circle")
                        .font(Theme.body(11, weight: .heavy))
                        .foregroundStyle(entry.armed ? Theme.lime : Theme.textFaint)
                    Spacer()
                    Text("🧊 \(entry.streak)d")
                        .font(Theme.body(11, weight: .heavy))
                        .foregroundStyle(Theme.cyan)
                }
                HourlyBars(hours: entry.today.hourly)
                    .frame(maxHeight: .infinity)
                HStack {
                    if let top = entry.today.topApp {
                        Text("top: \(top.displayName)")
                    }
                    Spacer()
                    Text(Fmt.duration(entry.today.watchSeconds))
                }
                .font(Theme.body(10, weight: .bold))
                .foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var circular: some View {
        Gauge(value: Double(min(entry.today.total, entry.goal)), in: 0...Double(max(entry.goal, 1))) {
            Text("reels")
        } currentValueLabel: {
            Text(Fmt.compact(entry.today.total))
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(entry.today.total) reels \(entry.mood.emoji)")
                .font(.system(.headline, design: .rounded).weight(.heavy))
            ProgressView(value: Double(min(entry.today.total, entry.goal)), total: Double(max(entry.goal, 1)))
            Text(entry.armed ? "counting · \(entry.mood.title)" : "\(entry.mood.title) · tap to arm")
                .font(.system(.caption, design: .rounded))
        }
        .widgetAccentable()
    }

    private var inline: some View {
        Text("\(entry.mood.emoji) \(entry.today.total) reels today")
    }
}

/// 24 tiny bars for the medium widget.
struct HourlyBars: View {
    let hours: [Int]

    var body: some View {
        let peak = max(hours.max() ?? 0, 1)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    let value = hour < hours.count ? hours[hour] : 0
                    Capsule()
                        .fill(value == peak && value > 0 ? AnyShapeStyle(Theme.hot) : AnyShapeStyle(Theme.brand))
                        .frame(height: max(3, geo.size.height * CGFloat(value) / CGFloat(peak)))
                        .opacity(value == 0 ? 0.25 : 1)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
