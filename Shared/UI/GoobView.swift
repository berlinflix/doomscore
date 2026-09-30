import SwiftUI

/// "Goob" — Doomscore's gooey mascot. Calm and round when you're fresh,
/// sweaty when you're cooked, melting with spiral eyes when your brain is gone.
/// Pure SwiftUI shapes, so it scales perfectly and works inside widgets
/// (pass `animated: false` there).
struct GoobView: View {
    var mood: Mood
    var size: CGFloat = 180
    var animated: Bool = true

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                GoobBody(mood: mood, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
            .accessibilityElement()
            .accessibilityLabel("Goob looks \(mood.title)")
        } else {
            GoobBody(mood: mood, size: size, time: 0)
                .accessibilityElement()
                .accessibilityLabel("Goob looks \(mood.title)")
        }
    }
}

private struct GoobBody: View {
    let mood: Mood
    let size: CGFloat
    let time: Double

    private var wobble: Double { 0.035 + mood.intensity * 0.07 }
    private var speed: Double { 1.1 + mood.intensity * 2.2 }
    private var melt: Double { mood == .melted ? 1 : (mood == .wellDone ? 0.35 : 0) }

    var body: some View {
        let phase = time * speed
        let bounce = sin(time * 2.4) * size * 0.012
        ZStack {
            BlobShape(phase: phase, wobble: wobble, melt: melt, meltPhase: time)
                .fill(mood.gradient)
                .shadow(color: mood.tint.opacity(0.55), radius: size * 0.14, y: size * 0.04)

            BlobShape(phase: phase, wobble: wobble, melt: melt, meltPhase: time)
                .stroke(Color.white.opacity(0.22), lineWidth: max(1, size * 0.012))

            // Glossy highlight
            Ellipse()
                .fill(Color.white.opacity(0.38))
                .frame(width: size * 0.22, height: size * 0.11)
                .rotationEffect(.degrees(-28))
                .offset(x: -size * 0.2, y: -size * 0.25)
                .blur(radius: size * 0.01)

            GoobFace(mood: mood, time: time)
                .frame(width: size * 0.56, height: size * 0.42)
                .offset(y: size * 0.02)

            if mood >= .kindaCooked && mood < .melted {
                SweatDrop()
                    .fill(Theme.cyan.opacity(0.9))
                    .frame(width: size * 0.07, height: size * 0.1)
                    .offset(x: size * 0.3, y: -size * 0.16 + CGFloat((time * 0.8).truncatingRemainder(dividingBy: 1)) * size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .offset(y: bounce)
    }
}

/// A closed, smoothly wobbling blob. `melt` adds drips along the bottom edge.
struct BlobShape: Shape {
    var phase: Double
    var wobble: Double
    var melt: Double = 0
    var meltPhase: Double = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.84
        let count = 72
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi
            var k = 1 + wobble * (0.55 * sin(3 * angle + phase * 1.7) + 0.35 * sin(5 * angle - phase * 1.1) + 0.2 * sin(2 * angle + phase * 0.6))
            let bottomness = max(0, sin(angle)) // 1 at the bottom (y grows downward)
            if melt > 0 {
                let drips = pow(bottomness, 6) * (0.5 + 0.5 * sin(7 * angle + meltPhase * 1.3))
                k += melt * 0.22 * drips
            }
            let r = radius * CGFloat(k)
            let squash = 0.95 + 0.05 * bottomness
            points.append(CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r * CGFloat(squash)))
        }
        var path = Path()
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(points[count - 1], points[0]))
        for i in 0..<count {
            let next = points[(i + 1) % count]
            path.addQuadCurve(to: mid(points[i], next), control: points[i])
        }
        path.closeSubpath()
        return path
    }
}

private struct GoobFace: View {
    let mood: Mood
    let time: Double

    private var blink: CGFloat {
        let cycle = time.truncatingRemainder(dividingBy: 4.3)
        return cycle < 0.13 ? 0.12 : 1
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let eye = w * 0.34
            ZStack {
                HStack(spacing: w * 0.12) {
                    GoobEye(mood: mood, time: time, isLeft: true)
                        .frame(width: eye, height: eye)
                    GoobEye(mood: mood, time: time, isLeft: false)
                        .frame(width: eye, height: eye)
                }
                .scaleEffect(x: 1, y: mood == .melted ? 1 : blink)
                .position(x: w / 2, y: h * 0.36)

                GoobMouth(mood: mood, time: time)
                    .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: max(2, w * 0.045), lineCap: .round, lineJoin: .round))
                    .frame(width: w * 0.34, height: h * 0.2)
                    .position(x: w / 2, y: h * 0.84)

                if mood == .fresh || mood == .chill {
                    HStack(spacing: w * 0.5) {
                        Circle().fill(Theme.pink.opacity(0.45))
                        Circle().fill(Theme.pink.opacity(0.45))
                    }
                    .frame(width: w * 0.8, height: w * 0.12)
                    .position(x: w / 2, y: h * 0.68)
                }
            }
        }
    }
}

private struct GoobEye: View {
    let mood: Mood
    let time: Double
    let isLeft: Bool

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                Circle().fill(Color.white)
                Circle().stroke(Color.black.opacity(0.18), lineWidth: s * 0.04)
                if mood == .melted {
                    SpiralShape(turns: 2.6, rotation: time * 3 * (isLeft ? 1 : -1))
                        .stroke(Color.black, style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
                        .padding(s * 0.12)
                } else {
                    let offset = pupilOffset(size: s)
                    Circle()
                        .fill(Color.black)
                        .frame(width: s * pupilScale, height: s * pupilScale)
                        .offset(offset)
                    Circle()
                        .fill(Color.white)
                        .frame(width: s * 0.16, height: s * 0.16)
                        .offset(x: offset.width - s * 0.1, y: offset.height - s * 0.12)
                }
            }
        }
    }

    private var pupilScale: CGFloat {
        switch mood {
        case .fresh, .chill: 0.56
        case .lowkey: 0.5
        case .kindaCooked: 0.44
        case .cooked: 0.36
        case .wellDone: 0.3
        case .melted: 0.3
        }
    }

    private func pupilOffset(size s: CGFloat) -> CGSize {
        switch mood {
        case .cooked, .wellDone:
            // Dizzy: pupils orbit in opposite directions.
            let angle = time * 4 * (isLeft ? 1 : -1)
            return CGSize(width: cos(angle) * s * 0.14, height: sin(angle) * s * 0.14)
        case .kindaCooked:
            return CGSize(width: sin(time * 1.6) * s * 0.1, height: s * 0.04)
        default:
            return CGSize(width: sin(time * 0.7) * s * 0.05, height: s * 0.02)
        }
    }
}

private struct GoobMouth: Shape {
    let mood: Mood
    let time: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        switch mood {
        case .fresh, .chill:
            path.move(to: CGPoint(x: 0, y: h * 0.2))
            path.addQuadCurve(to: CGPoint(x: w, y: h * 0.2), control: CGPoint(x: w / 2, y: h * 1.3))
        case .lowkey:
            path.move(to: CGPoint(x: w * 0.1, y: h * 0.45))
            path.addQuadCurve(to: CGPoint(x: w * 0.9, y: h * 0.45), control: CGPoint(x: w / 2, y: h * 0.85))
        case .kindaCooked:
            path.move(to: CGPoint(x: w * 0.12, y: h * 0.55))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.5))
        case .cooked, .wellDone:
            // Wobbly zig-zag.
            let steps = 6
            for i in 0...steps {
                let x = w * CGFloat(i) / CGFloat(steps)
                let y = h * 0.5 + CGFloat(sin(Double(i) * .pi + time * 6)) * h * 0.22
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        case .melted:
            path.addEllipse(in: CGRect(x: w * 0.25, y: 0, width: w * 0.5, height: h * (0.9 + 0.1 * CGFloat(sin(time * 3)))))
        }
        return path
    }
}

private struct SpiralShape: Shape {
    let turns: Double
    let rotation: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2
        let steps = 90
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = t * turns * 2 * .pi + rotation
            let r = maxRadius * CGFloat(t)
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

private struct SweatDrop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.7), control: CGPoint(x: rect.maxX, y: rect.midY * 0.8))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY * 0.7), radius: rect.width / 2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.midY * 0.8))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack {
            ForEach(Mood.allCases, id: \.self) { mood in
                VStack {
                    GoobView(mood: mood, size: 120)
                    Text(mood.title).foregroundStyle(.white)
                }
            }
        }
        .padding()
    }
    .background(Theme.bg)
}
