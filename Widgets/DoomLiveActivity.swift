import ActivityKit
import SwiftUI
import WidgetKit

/// Dynamic Island + Lock Screen counter (the iOS "floating bubble").
struct DoomLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoomActivityAttributes.self) { context in
            LockScreenLiveView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(Theme.lime)
                .widgetURL(url(for: context.state))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GoobView(mood: state.mood, size: 52, animated: false)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(state.todayCount)")
                            .font(Theme.display(34))
                            .foregroundStyle(state.mood.tint)
                            .contentTransition(.numericText(value: Double(state.todayCount)))
                        Text("today")
                            .font(Theme.body(11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.armed ? "counting · \(state.appName)" : "counter's off")
                        .font(Theme.body(14, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.armed {
                        VStack(spacing: 6) {
                            ProgressView(value: state.progress)
                                .tint(state.mood.tint)
                            HStack {
                                Text("this session: \(state.sessionCount)")
                                Spacer()
                                Text("\(state.mood.title) \(state.mood.emoji)")
                            }
                            .font(Theme.body(12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                        }
                    } else {
                        Text("tap to start counting 👀")
                            .font(Theme.body(14, weight: .heavy))
                            .foregroundStyle(Theme.lime)
                    }
                }
            } compactLeading: {
                Text(state.armed ? state.mood.emoji : "👀")
            } compactTrailing: {
                Text(Fmt.compact(state.todayCount))
                    .font(Theme.body(15, weight: .black))
                    .foregroundStyle(state.armed ? state.mood.tint : .white.opacity(0.5))
                    .contentTransition(.numericText(value: Double(state.todayCount)))
            } minimal: {
                Text(Fmt.compact(state.todayCount))
                    .font(Theme.body(12, weight: .black))
                    .foregroundStyle(state.mood.tint)
            }
            .widgetURL(url(for: state))
            .keylineTint(state.mood.tint)
        }
    }

    private func url(for state: DoomActivityAttributes.ContentState) -> URL? {
        URL(string: state.armed ? "doomscore://today" : "doomscore://arm?auto=1")
    }
}

private struct LockScreenLiveView: View {
    let state: DoomActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 14) {
            GoobView(mood: state.mood, size: 58, animated: false)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(state.todayCount)")
                        .font(Theme.display(34))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(state.todayCount)))
                    Text("reels today")
                        .font(Theme.body(13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                ProgressView(value: state.progress)
                    .tint(state.mood.tint)
                Text(statusLine)
                    .font(Theme.body(12, weight: .bold))
                    .foregroundStyle(state.armed ? Theme.lime : .white.opacity(0.6))
            }
        }
        .padding(16)
    }

    private var statusLine: String {
        if !state.armed { return "counter's off — tap to start 👀" }
        if isStale { return "\(state.mood.title) \(state.mood.emoji) · updating…" }
        return "\(state.appName) · session \(state.sessionCount) · \(state.mood.title) \(state.mood.emoji)"
    }
}
