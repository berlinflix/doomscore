import SwiftUI

// Small views used by both the app and the widget extension.

/// Segmented "battery" bar toward the daily cap.
struct CapBar: View {
    let count: Int
    let goal: Int
    var segments = 12
    var height: CGFloat = 14

    var body: some View {
        let ratio = goal > 0 ? Double(count) / Double(goal) : 0
        let lit = min(segments, Int((ratio * Double(segments)).rounded(.up)))
        HStack(spacing: 4) {
            ForEach(0..<segments, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? AnyShapeStyle(segmentColor(index)) : AnyShapeStyle(Theme.surfaceHigh))
                    .frame(height: height)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: lit)
        .accessibilityElement()
        .accessibilityLabel("\(count) of \(goal) daily cap")
    }

    private func segmentColor(_ index: Int) -> Color {
        let t = Double(index) / Double(max(segments - 1, 1))
        switch t {
        case ..<0.4: return Theme.lime
        case ..<0.7: return Theme.yellow
        case ..<0.9: return Theme.orange
        default: return Theme.red
        }
    }
}
