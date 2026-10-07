import SwiftUI

// MARK: - Cards

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            )
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.body(13, weight: .heavy))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(Theme.textDim)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }
}

// MARK: - Buttons

struct ChunkyButtonStyle: ButtonStyle {
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.brand)
    var foreground: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(18, weight: .heavy))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(color: Theme.lime.opacity(configuration.isPressed ? 0.1 : 0.3), radius: 18, y: 8)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(16, weight: .bold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(Theme.surfaceHigh))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Pills & chips

struct StatusPill: View {
    let mode: AppModel.TrackingMode
    @State private var pulse = false

    private var isOn: Bool { mode != .off }

    private var tint: Color {
        switch mode {
        case .off: Theme.textFaint
        case .auto: Theme.cyan
        case .precise: Theme.lime
        }
    }

    private var label: String {
        switch mode {
        case .off: "not tracking"
        case .auto: "auto"
        case .precise: "exact"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .scaleEffect(isOn && pulse ? 1.5 : 1)
                .opacity(isOn && pulse ? 0.5 : 1)
            Text(label)
                .font(Theme.body(13, weight: .heavy))
                .foregroundStyle(isOn ? tint : Theme.textDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(isOn ? tint.opacity(0.12) : Theme.surfaceHigh))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel(isOn ? "Tracking: \(label)" : "Not tracking")
    }
}

struct AppChip: View {
    let app: SourceApp
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: app.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(Circle().fill(app.tint))
            Text(app.shortLabel)
                .font(Theme.body(13, weight: .heavy))
                .foregroundStyle(Theme.textDim)
            Text(Fmt.compact(count))
                .font(Theme.body(16, weight: .black))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText(value: Double(count)))
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.surfaceHigh))
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    let emoji: String
    let value: String
    let label: String
    var tint: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.system(size: 22))
            Text(value)
                .font(Theme.display(24))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.body(12, weight: .bold))
                .foregroundStyle(Theme.textDim)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.body(15, weight: .bold))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
            )
            .overlay(alignment: .bottom) {
                Triangle()
                    .fill(Color.white)
                    .frame(width: 18, height: 10)
                    .offset(y: 9)
            }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct Avatar: View {
    let emoji: String
    let colorHex: String
    var size: CGFloat = 44

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hexString: colorHex).opacity(0.9)))
            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1.5))
    }
}

/// Animated neon mesh background (iOS 18 MeshGradient).
struct NeonBackground: View {
    var colors: [Color] = [Theme.violet, Theme.pink, Theme.cyan]
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !animated)) { timeline in
            let t = Float(timeline.date.timeIntervalSinceReferenceDate)
            let wobble: Float = animated ? 0.12 : 0
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + sin(t * 0.7) * wobble, 0.5 + cos(t * 0.5) * wobble], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    colors[0], Theme.bg, colors[1 % colors.count],
                    Theme.bg, colors[2 % colors.count], Theme.bg,
                    colors[1 % colors.count], Theme.bg, colors[0],
                ]
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Standard screen chrome: near-black background, hidden scroll bars.
    func screenBackground() -> some View {
        background(Theme.bg.ignoresSafeArea())
    }
}
