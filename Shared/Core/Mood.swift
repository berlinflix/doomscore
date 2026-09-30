import Foundation

/// How cooked you are today, relative to your daily cap.
enum Mood: Int, CaseIterable, Sendable, Comparable {
    case fresh, chill, lowkey, kindaCooked, cooked, wellDone, melted

    static func from(count: Int, goal: Int) -> Mood {
        guard count > 0 else { return .fresh }
        let ratio = Double(count) / Double(max(goal, 1))
        switch ratio {
        case ..<0.2: return .chill
        case ..<0.45: return .lowkey
        case ..<0.75: return .kindaCooked
        case ..<1.0: return .cooked
        case ..<1.6: return .wellDone
        default: return .melted
        }
    }

    static func < (lhs: Mood, rhs: Mood) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .fresh: "fresh"
        case .chill: "just vibing"
        case .lowkey: "lowkey scrolling"
        case .kindaCooked: "kinda cooked"
        case .cooked: "cooked"
        case .wellDone: "well done"
        case .melted: "brain melted"
        }
    }

    var emoji: String {
        switch self {
        case .fresh: "🧊"
        case .chill: "😌"
        case .lowkey: "👀"
        case .kindaCooked: "🍳"
        case .cooked: "🔥"
        case .wellDone: "💀"
        case .melted: "🫠"
        }
    }

    private var quips: [String] {
        switch self {
        case .fresh:
            ["clean slate. main character energy ✨", "0 reels. who even are you", "touch grass speedrun any%"]
        case .chill:
            ["a lil scroll never hurt nobody", "still in your self-control era", "ok we're vibing"]
        case .lowkey:
            ["lowkey scrolling, highkey fine", "the algorithm is starting to know you", "blink twice if you're ok"]
        case .kindaCooked:
            ["bestie… put the phone down (you won't)", "getting a little toasty 🍳", "the reels are winning ngl"]
        case .cooked:
            ["you're cooked. like actually.", "chat, is this real 💀", "your thumb needs a vacation"]
        case .wellDone:
            ["past your cap. not mad, just disappointed", "certified doomscroller moment", "your screen time filed a complaint"]
        case .melted:
            ["brain.exe has stopped responding 🫠", "ok this is a cry for help", "your fyp knows you better than your mom"]
        }
    }

    /// A quip that stays stable for a given seed (e.g. the day number) so the
    /// text doesn't flicker on every refresh.
    func quip(seed: Int) -> String {
        let list = quips
        return list[abs(seed) % list.count]
    }

    /// 0…1 intensity used for animation speed / wobble.
    var intensity: Double { Double(rawValue) / Double(Mood.allCases.count - 1) }
}
