import SwiftUI

/// 9:16 story card rendered to an image for sharing (Instagram Stories, etc.).
struct ShareCardView: View {
    let summary: PeriodSummary
    let periodTitle: String
    let goal: Int

    private var mood: Mood { Mood.from(count: Int(summary.averagePerDay.rounded()), goal: goal) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.violet, Theme.bg, Theme.pink.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("doomscore")
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.brand)
                    Spacer()
                    Text(periodTitle.lowercased())
                        .font(Theme.body(13, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    GoobView(mood: mood, size: 150, animated: false)
                    Spacer()
                }
                Text("\(summary.total)")
                    .font(Theme.display(88))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("reels scrolled · \(mood.title) \(mood.emoji)")
                    .font(Theme.body(17, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.9))

                VStack(spacing: 10) {
                    row("⏱️", "time in reels", Fmt.duration(summary.watchSeconds))
                    row("📏", "content scrolled", String(format: "%.0f m", summary.thumbMeters))
                    if let peak = summary.peakHour { row("🦉", "doom hour", Fmt.hour(peak)) }
                    row("🧊", "chill streak", "\(summary.longestChillStreak)d")
                    row("🥷", "ads dodged", "\(summary.adsSkipped)")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.35)))

                HStack(spacing: 10) {
                    Text(summary.archetype.emoji).font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("scroll personality")
                            .font(Theme.body(12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(summary.archetype.title)
                            .font(Theme.body(19, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 0)
                Text("battle me on doomscore ⚔️")
                    .font(Theme.body(13, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(26)
        }
        .frame(width: 360, height: 640)
    }

    private func row(_ emoji: String, _ label: String, _ value: String) -> some View {
        HStack {
            Text(emoji)
            Text(label)
                .font(Theme.body(15, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(value)
                .font(Theme.body(16, weight: .black))
                .foregroundStyle(.white)
        }
    }
}
