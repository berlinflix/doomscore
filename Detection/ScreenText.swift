import CoreGraphics
import Foundation

/// One recognised line of on-screen text. Lives only in memory for a few
/// milliseconds — never persisted, never logged, never uploaded.
struct TextItem: Sendable, Equatable {
    let text: String
    let normalized: String
    /// Normalised bounding box, origin top-left.
    let box: CGRect
    let confidence: Float

    init(text: String, box: CGRect, confidence: Float) {
        self.text = text
        self.normalized = TextItem.normalize(text)
        self.box = box
        self.confidence = confidence
    }

    var midX: CGFloat { box.midX }
    var midY: CGFloat { box.midY }

    static func normalize(_ string: String) -> String {
        let lowered = string.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let collapsed = lowered.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Helpers for the like/comment counters in the action rail ("12.4K", "1,093").
enum CountText {
    private static let suffixes: Set<Character> = ["k", "m", "b", "万", "亿", "천", "만"]

    static func isCount(_ normalized: String) -> Bool {
        let s = normalized.replacingOccurrences(of: " ", with: "")
        guard let first = s.first, first.isNumber, s.count <= 8 else { return false }
        var sawSuffix = false
        for (index, ch) in s.enumerated() {
            if ch.isNumber, !sawSuffix { continue }
            if (ch == "." || ch == ","), !sawSuffix, index > 0 { continue }
            if suffixes.contains(ch), !sawSuffix, index == s.count - 1 { sawSuffix = true; continue }
            return false
        }
        return true
    }

    /// Parses "12.4k" → 12400, "1,234" → 1234, "85" → 85.
    static func value(_ normalized: String) -> Double? {
        var s = normalized.replacingOccurrences(of: " ", with: "")
        guard isCount(s), let last = s.last else { return nil }
        var multiplier = 1.0
        switch last {
        case "k", "천": multiplier = 1_000
        case "m": multiplier = 1_000_000
        case "b": multiplier = 1_000_000_000
        case "万", "만": multiplier = 10_000
        case "亿": multiplier = 100_000_000
        default: break
        }
        if multiplier != 1 {
            s.removeLast()
            s = s.replacingOccurrences(of: ",", with: ".")
        } else {
            s = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
        }
        guard let number = Double(s) else { return nil }
        return number * multiplier
    }

    /// Two rail counters describe the same reel if they're within ~3 %.
    /// (Liking a reel bumps the count by one, so exact equality is too strict.)
    static func close(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= max(2, 0.03 * max(a, b))
    }
}

enum Similarity {
    /// 1 − normalised Levenshtein distance.
    static func ratio(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var previous = Array(0...y.count)
        var current = Array(repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }
}

/// What makes one reel distinguishable from another, read from the overlay:
/// creator handle, first caption words and the top rail counter.
struct ReelIdentity: Hashable, Sendable {
    var handle: String?
    var caption: String?
    var likes: Double?

    var isEmpty: Bool { handle == nil && caption == nil && likes == nil }

    /// Enough signal to be trusted for rewatch detection.
    var isStrong: Bool { handle != nil || caption != nil }

    enum Match: Equatable { case same, different, unknown }

    func compare(_ other: ReelIdentity) -> Match {
        if let a = handle, let b = other.handle {
            guard Similarity.ratio(a, b) >= 0.8 else { return .different }
            if let c1 = caption, let c2 = other.caption { return Similarity.ratio(c1, c2) >= 0.6 ? .same : .different }
            if let l1 = likes, let l2 = other.likes { return CountText.close(l1, l2) ? .same : .different }
            return .same
        }
        if let c1 = caption, let c2 = other.caption {
            guard Similarity.ratio(c1, c2) >= 0.6 else { return .different }
            if let l1 = likes, let l2 = other.likes { return CountText.close(l1, l2) ? .same : .different }
            return .same
        }
        if let l1 = likes, let l2 = other.likes {
            return CountText.close(l1, l2) ? .unknown : .different
        }
        return .unknown
    }

    /// Different creator or clearly different caption — strong enough to infer
    /// a page change even when no swipe was seen.
    func differsStrongly(from other: ReelIdentity) -> Bool {
        if let a = handle, let b = other.handle, Similarity.ratio(a, b) < 0.75 { return true }
        if let c1 = caption, let c2 = other.caption, Similarity.ratio(c1, c2) < 0.45 {
            // Only trust a caption change if the handle didn't say "same creator".
            if let a = handle, let b = other.handle, Similarity.ratio(a, b) >= 0.8 { return false }
            return true
        }
        return false
    }

    /// Exact-match fingerprint source for the persisted (hashed) seen-set.
    var fingerprintSource: String? {
        guard isStrong else { return nil }
        return "\(handle ?? "")|\(caption ?? "")"
    }
}

/// Recently seen reels, for "don't count rewatches".
struct SeenReels: Sendable {
    private(set) var entries: [ReelIdentity] = []
    let capacity: Int

    init(capacity: Int) { self.capacity = max(capacity, 10) }

    func contains(_ identity: ReelIdentity) -> Bool {
        guard identity.isStrong else { return false }
        return entries.contains { $0.isStrong && $0.compare(identity) == .same }
    }

    mutating func insert(_ identity: ReelIdentity) {
        guard !identity.isEmpty else { return }
        if let index = entries.firstIndex(where: { $0.compare(identity) == .same }) {
            entries.remove(at: index)
        }
        entries.append(identity)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    mutating func removeAll() { entries.removeAll() }
}
