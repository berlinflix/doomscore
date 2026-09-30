import SwiftUI
import WidgetKit

struct BattleEntry: TimelineEntry {
    let date: Date
    let rows: [CachedLeaderboard.Row]
    let stale: Bool
}

struct BattleProvider: TimelineProvider {
    func placeholder(in context: Context) -> BattleEntry {
        BattleEntry(date: Date(), rows: [
            .init(name: "you", emoji: "🫠", colorHex: "#C6FF3D", reels: 87, isMe: true),
            .init(name: "riya", emoji: "🐸", colorHex: "#FF4FB3", reels: 64, isMe: false),
            .init(name: "kabir", emoji: "🦉", colorHex: "#3DE0FF", reels: 12, isMe: false),
        ], stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (BattleEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BattleEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func load() -> BattleEntry {
        guard let cached = SharedStore.shared.leaderboard else {
            return BattleEntry(date: Date(), rows: [], stale: true)
        }
        var rows = cached.rows
        // Keep my own row fresh from local data.
        if cached.day == DayKey.today(), let index = rows.firstIndex(where: \.isMe) {
            rows[index].reels = max(rows[index].reels, SharedStore.shared.todayRecord().total)
        }
        let stale = cached.day != DayKey.today()
        return BattleEntry(date: Date(), rows: stale ? [] : rows.sorted { $0.reels > $1.reels }, stale: stale)
    }
}

struct BattleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoomBattle", provider: BattleProvider()) { entry in
            BattleWidgetView(entry: entry)
        }
        .configurationDisplayName("Scroll Battle")
        .description("Today's most cooked friends.")
        .supportedFamilies([.systemMedium])
    }
}

struct BattleWidgetView: View {
    let entry: BattleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("scroll battle ⚔️")
                    .font(Theme.body(14, weight: .black))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("today")
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            if entry.rows.isEmpty {
                Spacer()
                Text("open Doomscore to load today's battle")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                Spacer()
            } else {
                ForEach(Array(entry.rows.prefix(3).enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 10) {
                        Text(["🥇", "🥈", "🥉"][index])
                        Text(row.emoji)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color(hexString: row.colorHex).opacity(0.85)))
                        Text(row.isMe ? "you" : row.name)
                            .font(Theme.body(14, weight: row.isMe ? .black : .bold))
                            .foregroundStyle(row.isMe ? Theme.lime : Theme.text)
                            .lineLimit(1)
                        Spacer()
                        Text(Fmt.compact(row.reels))
                            .font(Theme.body(15, weight: .black))
                            .foregroundStyle(Theme.text)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "doomscore://battle"))
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Theme.surface, Theme.bg], startPoint: .top, endPoint: .bottom)
        }
    }
}
