import ActivityKit
import SwiftUI
import WidgetKit

/// Dynamic Island + Lock Screen counter (the iOS "floating bubble").
///
/// Compact: a cap ring with Goob's mood on the left, the live count on the
/// right. Expanded: Goob, a big gradient count, the cap meter and three chips
/// — a session timer that iOS ticks by itself, reels this session, and the
/// chill streak.
struct DoomLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoomActivityAttributes.self) { context in
            LockScreenLiveView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color(hex: 0x0B0A14).opacity(0.94))
                .activitySystemActionForegroundColor(Theme.lime)
                .widgetURL(Self.url)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GoobView(mood: state.mood, size: 50, animated: false)
                        .opacity(stale ? 0.6 : 1)
                        .padding(.leading, 4)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BigCount(state: state, size: 36)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    StatusLine(state: state, isStale: stale)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: state, isStale: stale)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }
            } compactLeading: {
                CapRing(state: state, lineWidth: 2.6) {
                    Text(state.armed ? state.mood.emoji : "👀")
                        .font(.system(size: 10))
                }
                .frame(width: 22, height: 22)
                .opacity(stale ? 0.55 : 1)
            } compactTrailing: {
                CompactCount(state: state, isStale: stale)
            } minimal: {
                CapRing(state: state, lineWidth: 2.2) {
                    Text(Fmt.compact(state.todayCount))
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(2.5)
                }
                .frame(width: 22, height: 22)
            }
            .widgetURL(Self.url)
            .keylineTint(state.mood.tint)
        }
    }

    private static let url = URL(string: "doomscore://today")
}

// MARK: - Lock Screen

private struct LockScreenLiveView: View {
    let state: DoomActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                GoobView(mood: state.mood, size: 56, animated: false)
                    .opacity(isStale ? 0.65 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        if state.estimated {
                            Text("≈")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Text("\(state.todayCount)")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: Double(state.todayCount)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("reels today")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Text("\(state.mood.title) \(state.mood.emoji)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(state.mood.gradient)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                ModePill(state: state, isStale: isStale)
            }

            if state.armed {
                CapMeter(state: state)
                    .frame(height: 8)
                HStack(spacing: 0) {
                    Label { SessionTimer(start: state.sessionStartDate) } icon: { Image(systemName: "timer") }
                    Spacer(minLength: 6)
                    Text("+\(state.sessionCount) this sesh")
                    Spacer(minLength: 6)
                    Text("🧊 \(state.streak)d")
                    Spacer(minLength: 6)
                    Text("\(Fmt.compact(state.todayCount))/\(Fmt.compact(state.goal)) cap")
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            } else {
                Text("tracking's off — tap to turn it on 👀")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.lime)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [state.mood.tint.opacity(isStale ? 0.06 : 0.16), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
}

// MARK: - Dynamic Island pieces

private struct CompactCount: View {
    let state: DoomActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0.5) {
            if state.estimated {
                Text("~")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(Fmt.compact(state.todayCount))
                .font(.system(size: 15, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(state.armed && !isStale ? state.mood.tint : .white.opacity(0.55))
                .contentTransition(.numericText(value: Double(state.todayCount)))
        }
        .lineLimit(1)
    }
}

private struct BigCount: View {
    let state: DoomActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        VStack(alignment: .trailing, spacing: -3) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if state.estimated {
                    Text("≈")
                        .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text("\(state.todayCount)")
                    .font(.system(size: size, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(state.mood.gradient)
                    .contentTransition(.numericText(value: Double(state.todayCount)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text("reels today")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct StatusLine: View {
    let state: DoomActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
    }

    private var text: String {
        if !state.armed { return "tracking off" }
        if isStale { return "paused · \(state.appName)" }
        return "\(state.estimated ? "auto" : "live") · \(state.appName)"
    }

    private var dot: Color {
        if !state.armed { return .white.opacity(0.35) }
        return isStale ? Theme.yellow : Theme.lime
    }
}

private struct ExpandedBottom: View {
    let state: DoomActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if state.armed {
            VStack(spacing: 9) {
                CapMeter(state: state)
                    .frame(height: 8)
                HStack(spacing: 6) {
                    Chip(symbol: "timer") { SessionTimer(start: state.sessionStartDate) }
                    Chip(symbol: "plus.circle.fill") { Text("\(state.sessionCount) this sesh") }
                    Chip(symbol: "snowflake") { Text("\(state.streak)d streak") }
                }
            }
            .opacity(isStale ? 0.6 : 1)
        } else {
            Text("tap to turn tracking on 👀")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.lime)
        }
    }
}

// MARK: - Shared bits

/// Ring around the daily cap, mood-coloured.
private struct CapRing<Content: View>: View {
    let state: DoomActivityAttributes.ContentState
    var lineWidth: CGFloat = 3
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.03, state.progress))
                .stroke(
                    state.isOverCap ? AnyShapeStyle(Theme.red) : AnyShapeStyle(state.mood.gradient),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            content
        }
    }
}

/// Continuous bar toward the daily cap; turns hot past it.
private struct CapMeter: View {
    let state: DoomActivityAttributes.ContentState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: state.isOverCap ? [Theme.pink, Theme.red] : Array(state.mood.colors.reversed()),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.height, geo.size.width * state.progress))
            }
        }
    }
}

private struct Chip<Content: View>: View {
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white.opacity(0.6))
            content
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.white.opacity(0.09)))
    }
}

/// Counts up from the start of the visit — rendered by iOS every second,
/// no updates needed.
private struct SessionTimer: View {
    let start: Date?

    var body: some View {
        if let start {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 46, alignment: .leading)
        } else {
            Text("now")
        }
    }
}

private struct ModePill: View {
    let state: DoomActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .kerning(0.8)
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
    }

    private var label: String {
        if !state.armed { return "OFF" }
        if isStale { return "PAUSED" }
        return state.estimated ? "AUTO" : "LIVE"
    }

    private var fill: AnyShapeStyle {
        if !state.armed || isStale { return AnyShapeStyle(Color.white.opacity(0.5)) }
        return state.estimated ? AnyShapeStyle(Theme.cyan) : AnyShapeStyle(Theme.brand)
    }
}
