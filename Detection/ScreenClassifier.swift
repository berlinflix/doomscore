import CoreGraphics
import Foundation

/// What the detector concluded from one OCR pass over the screen.
struct ScreenReading: Sendable {
    enum Kind: String, Sendable {
        case shortVideo   // a Reels / Shorts / TikTok-style full-screen feed
        case comments     // comment sheet open on top of a reel
        case other        // anything else (feed, DMs, home screen, other apps…)
    }

    var kind: Kind
    var app: SourceApp?
    var isAd: Bool
    var identity: ReelIdentity?
    var score: Int
    /// Capture time of the frame (monotonic seconds).
    var at: TimeInterval
}

/// Rule-based classifier over recognised text + layout. Every keyword and
/// zone comes from `DetectorConfig`, so it can be tuned remotely.
struct ScreenClassifier: Sendable {
    var config: DetectorConfig

    init(config: DetectorConfig) { self.config = config }

    func classify(_ items: [TextItem], hint: SourceApp?, at time: TimeInterval) -> ScreenReading {
        let z = config.zones
        let k = config.keywords

        // Subtitles and meme text burned into the video are big and change
        // every second; only the app's small overlay text describes the reel.
        let overlay = items.filter { $0.box.height <= z.maxOverlayTextHeight }
        let top = items.filter { $0.box.maxY <= z.topMaxY }
        let rail = overlay.filter {
            $0.box.minX >= z.railMinX && $0.midY >= z.railMinY && $0.midY <= z.railMaxY && $0.normalized.count <= 12
        }
        // Everything in the caption area, including the Follow button…
        let captionZone = overlay.filter {
            $0.box.minX <= z.captionMaxMinX && $0.box.maxX <= z.railMinX + 0.06
                && $0.midY >= z.captionMinY && $0.midY <= z.captionMaxY
        }
        // …and the left-aligned lines in it: username, caption, audio.
        let caption = captionZone.filter { $0.box.minX <= z.overlayMaxMinX }
        let tabBar = items.filter { $0.midY > z.tabBarMinY }

        // A comment sheet covers the reel: no counting while it's open.
        if items.contains(where: { item in k.comments.contains { item.normalized.contains($0) } }) {
            return ScreenReading(kind: .comments, app: hint, isAd: false, identity: nil, score: 0, at: time)
        }

        let railCounts = rail.filter { CountText.isCount($0.normalized) }
        let railLabels = rail.filter { k.railLabels.contains($0.normalized) }
        let column = Self.columnSize(railCounts + railLabels)

        var score = 0
        var app: SourceApp?

        let igHeader = top.contains { item in
            item.box.minX < 0.45 && k.instagramHeader.contains { item.normalized == $0 || item.normalized.hasPrefix($0 + " ") }
        }
        if igHeader { score += 2; app = .instagram }
        if top.contains(where: { item in k.tiktokHeader.contains { item.normalized.contains($0) } }) {
            score += 2
            app = app ?? .tiktok
        }
        if top.contains(where: { k.snapchatHeader.contains($0.normalized) }) {
            score += 2
            app = app ?? .snapchat
        }

        score += min(column, 3)
        if !caption.isEmpty { score += 1 }
        let hasFollow = captionZone.contains { item in k.follow.contains { item.normalized == $0 || item.normalized.hasSuffix(" " + $0) } }
        let hasSubscribe = captionZone.contains { k.subscribe.contains($0.normalized) }
        if hasFollow || hasSubscribe { score += 1 }
        let hasAudioLine = caption.contains { item in
            item.text.hasPrefix("♫") || item.text.hasPrefix("♪") || k.audioLine.contains { item.normalized.contains($0) }
        }
        if hasAudioLine { score += 1 }

        let looksLikeYouTube = hasSubscribe
            || railLabels.contains { k.youtubeRail.contains($0.normalized) }
            || tabBar.contains { k.youtubeTabBar.contains($0.normalized) }
        if looksLikeYouTube { app = app ?? .youtube }

        if let hint, hint != .other {
            score += 1
            app = app ?? hint
        }

        if items.contains(where: { item in k.feedNegative.contains { item.normalized.contains($0) } }) {
            score -= 3
        }

        // Layout sanity: a vertical action rail or a feed header must exist.
        let structural = column >= 2 || igHeader
            || (column >= 1 && (hasFollow || hasSubscribe || hasAudioLine))
            || ((hasFollow || hasSubscribe) && hasAudioLine)
        let isShortVideo = structural && !caption.isEmpty && score >= config.shortVideoScoreThreshold

        guard isShortVideo else {
            return ScreenReading(kind: .other, app: app, isAd: false, identity: nil, score: score, at: time)
        }

        let isAd = detectAd(items: overlay)
        let identity = extractIdentity(caption: caption, anchors: captionZone, railCounts: railCounts)
        return ScreenReading(kind: .shortVideo, app: app, isAd: isAd, identity: identity, score: score, at: time)
    }

    // MARK: Ads

    func detectAd(items: [TextItem]) -> Bool {
        let z = config.zones
        let k = config.keywords
        let zone = items.filter {
            $0.midY >= z.adMinY && $0.box.minX <= 0.85 && $0.box.height <= z.maxOverlayTextHeight
        }
        for item in zone {
            let text = item.normalized
            for label in k.adLabels {
                if label.count <= 2 {
                    // Very short labels ("ad") must be the whole line.
                    if text == label { return true }
                } else if text == label || text.hasPrefix(label + " ") || text.hasSuffix(" " + label)
                            || text.contains("· " + label) || text.contains("• " + label) {
                    return true
                }
            }
            // CTA bars ("Shop now ›") are left-aligned buttons, not words in a subtitle.
            if item.box.minX <= 0.3, k.ctaPhrases.contains(where: { text.hasPrefix($0) }) { return true }
        }
        return false
    }

    // MARK: Identity

    /// `caption`: left-aligned overlay lines. `anchors`: the whole caption
    /// area (the Follow/Subscribe button sits right of the username).
    func extractIdentity(caption: [TextItem], anchors: [TextItem]? = nil, railCounts: [TextItem]) -> ReelIdentity? {
        let k = config.keywords
        let lines = caption.sorted { $0.box.minY < $1.box.minY }
        let zone = anchors ?? caption

        func isNoise(_ text: String) -> Bool {
            k.captionNoise.contains { text == $0 || text.hasPrefix($0 + " ") }
                || k.adLabels.contains(text)
                || text.hasPrefix("♫") || text.hasPrefix("♪")
                || CountText.isCount(text)
        }

        var handle: String?
        // 1) The text immediately left of a Follow/Subscribe button.
        if let anchor = zone.first(where: { k.follow.contains($0.normalized) || k.subscribe.contains($0.normalized) }) {
            handle = zone
                .filter { $0 != anchor && abs($0.midY - anchor.midY) < 0.02 && $0.box.maxX <= anchor.box.minX + 0.02 }
                .max { $0.box.maxX < $1.box.maxX }
                .flatMap { Self.cleanHandle($0.normalized, noise: isNoise) }
        }
        // 2) Otherwise the top-most left-aligned line that looks like a username.
        if handle == nil {
            handle = lines.lazy.compactMap { Self.cleanHandle($0.normalized, noise: isNoise) }.first
        }

        let captionLine = lines.first { item in
            let text = item.normalized
            return text.count >= 8 && text.contains(" ") && !isNoise(text)
                && Self.cleanHandle(text, noise: isNoise) == nil
                && !k.audioLine.contains { text.contains($0) }
        }
        let caption = captionLine.map { String($0.normalized.filter { $0.isLetter || $0.isNumber || $0 == " " }.prefix(28)) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let likes = railCounts.sorted { $0.box.minY < $1.box.minY }.lazy.compactMap { CountText.value($0.normalized) }.first

        let identity = ReelIdentity(handle: handle, caption: caption, likes: likes)
        return identity.isEmpty ? nil : identity
    }

    static func cleanHandle(_ text: String, noise: (String) -> Bool) -> String? {
        var t = text
        if let separator = t.firstIndex(where: { $0 == "•" || $0 == "·" }) {
            t = String(t[..<separator])
        }
        t = t.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("@") { t.removeFirst() }
        guard (3...30).contains(t.count),
              t.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "." || $0 == "_" }),
              t.contains(where: { $0.isLetter }),
              !noise(t) else { return nil }
        return t
    }

    /// Number of items stacked vertically in one narrow column.
    static func columnSize(_ items: [TextItem]) -> Int {
        guard !items.isEmpty else { return 0 }
        let xs = items.map(\.midX).sorted()
        let median = xs[xs.count / 2]
        let aligned = items.filter { abs($0.midX - median) < 0.07 }.map(\.midY).sorted()
        var count = 0
        var lastY: CGFloat = -1
        for y in aligned where y - lastY > 0.03 {
            count += 1
            lastY = y
        }
        return count
    }
}
