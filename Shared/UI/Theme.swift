import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Parses "#RRGGBB" (used for profile colours coming from the backend).
    init(hexString: String, fallback: Color = Theme.violet) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if cleaned.count == 6, let value = UInt32(cleaned, radix: 16) {
            self.init(hex: value)
        } else {
            self = fallback
        }
    }
}

/// Neon-on-midnight design tokens.
enum Theme {
    static let bg = Color(hex: 0x09090F)
    static let surface = Color(hex: 0x14141D)
    static let surfaceHigh = Color(hex: 0x1D1D2A)
    static let stroke = Color.white.opacity(0.08)
    static let text = Color(hex: 0xF4F4FA)
    static let textDim = Color(hex: 0x9C9CB2)
    static let textFaint = Color(hex: 0x5F5F74)

    static let lime = Color(hex: 0xC6FF3D)
    static let mint = Color(hex: 0x7CFFB2)
    static let cyan = Color(hex: 0x3DE0FF)
    static let violet = Color(hex: 0x8A5CFF)
    static let pink = Color(hex: 0xFF4FB3)
    static let orange = Color(hex: 0xFF8A3D)
    static let red = Color(hex: 0xFF4D5E)
    static let yellow = Color(hex: 0xFFE14D)

    static let brand = LinearGradient(colors: [lime, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let hot = LinearGradient(colors: [pink, orange], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func display(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func body(_ size: CGFloat = 16, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let profileColors: [String] = ["#C6FF3D", "#3DE0FF", "#8A5CFF", "#FF4FB3", "#FF8A3D", "#FFE14D"]
    static let profileEmojis: [String] = [
        "🫠", "💀", "🧟", "🐸", "🦉", "👽", "🤡", "😵‍💫", "🧃", "🍳", "🔥", "🧊",
        "🐒", "🦄", "🍄", "🌚", "👾", "🥶", "🤠", "🫥", "🐙", "🦖", "🍓", "⭐️",
    ]
}

extension Mood {
    var colors: [Color] {
        switch self {
        case .fresh: [Theme.cyan, Theme.lime]
        case .chill: [Theme.lime, Theme.mint]
        case .lowkey: [Theme.yellow, Theme.lime]
        case .kindaCooked: [Theme.orange, Theme.yellow]
        case .cooked: [Theme.red, Theme.orange]
        case .wellDone: [Theme.pink, Theme.red]
        case .melted: [Theme.violet, Theme.pink]
        }
    }

    var tint: Color { colors[0] }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension SourceApp {
    /// Neutral glyphs (no third-party logos).
    var symbol: String {
        switch self {
        case .instagram: "camera.aperture"
        case .youtube: "play.rectangle.fill"
        case .tiktok: "music.note"
        case .snapchat: "bolt.fill"
        case .other: "square.stack.fill"
        }
    }

    var tint: Color {
        switch self {
        case .instagram: Theme.pink
        case .youtube: Theme.red
        case .tiktok: Theme.cyan
        case .snapchat: Theme.yellow
        case .other: Theme.textDim
        }
    }
}
