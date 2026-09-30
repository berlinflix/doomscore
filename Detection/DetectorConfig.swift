import Foundation

/// Every tunable number and keyword the detector uses. Ships with sane
/// defaults and can be replaced at runtime by a JSON file in the App Group
/// (pushed from `DS_REMOTE_CONFIG_URL`) — so when Instagram changes its UI you
/// can fix detection without an App Store release.
struct DetectorConfig: Codable, Sendable, Equatable {
    static let currentVersion = 1

    struct Motion: Codable, Sendable, Equatable {
        /// Luma grid used for motion estimation (portrait aspect ≈ 1:2.17).
        var gridWidth = 48
        var gridHeight = 104
        /// Frames analysed per second (ReplayKit delivers up to 30–60).
        var processFPS = 20.0
        /// Rows outside this band (status bar/header, tab bar) are ignored.
        var bandTop = 0.10
        var bandBottom = 0.88
        /// Largest shift searched, as a fraction of the band height.
        var maxShiftFraction = 0.6
        var minOverlapRows = 20
        /// A frame pair counts as a translation when the best shift explains at
        /// least this much of the zero-shift difference…
        var minImprovement = 0.38
        /// …and the frames differ by at least this mean luma delta.
        var noiseFloor = 2.5
        var minShiftRows = 2
        /// Content must be still this long before a gesture is closed.
        var settleDelay = 0.22
        /// Longer continuous motion is a feed/scroll view, not a paged swipe.
        var maxGestureDuration = 2.2
        /// Height of one reel page as a fraction of the screen.
        var pageFraction = 0.86
        var minPageFraction = 0.55
        var maxPagesPerGesture = 3.4
        /// Unexplained full-screen change that triggers an early OCR check.
        var cutThreshold = 28.0
    }

    struct OCR: Codable, Sendable, Equatable {
        var downscale = 2
        var minimumTextHeight = 0.011
        var languages = ["en-US"]
        var minimumConfidence: Float = 0.3
        /// Wait after a swipe settles before reading the new reel's overlay.
        var settleDelay = 0.30
        var intervalInReels = 1.0
        var intervalHinted = 1.2
        var intervalIdle = 3.0
        /// Skip OCR when the extension is close to its 50 MB memory ceiling.
        var minAvailableMemoryMB = 14.0
    }

    struct Zones: Codable, Sendable, Equatable {
        // Normalised coordinates, origin top-left.
        var topMaxY = 0.14
        var railMinX = 0.80
        var railMinY = 0.40
        var railMaxY = 0.92
        var captionMaxMinX = 0.70
        var captionMinY = 0.60
        var captionMaxY = 0.935
        var tabBarMinY = 0.935
        var adMinY = 0.52
    }

    struct Keywords: Codable, Sendable, Equatable {
        var instagramHeader = ["reels"]
        var tiktokHeader = ["for you"]
        var snapchatHeader = ["spotlight"]
        var youtubeRail = ["dislike", "remix"]
        var youtubeTabBar = ["shorts", "subscriptions"]
        var railLabels = ["like", "likes", "dislike", "share", "remix", "comments", "save", "send"]
        var follow = ["follow", "follow back"]
        var subscribe = ["subscribe", "subscribed"]
        var comments = ["add a comment", "add comment", "leave a comment", "comments are turned off", "add a reply"]
        var feedNegative = ["your story", "suggested for you", "edit profile", "view all comments", "liked by"]
        var adLabels = [
            "sponsored", "ad", "gesponsert", "sponsorisé", "sponsorise", "patrocinado", "sponsorizzato",
            "sponsorowane", "реклама", "sponsorlu", "gesponsord", "sponsrad", "sponset", "sponsoreret",
            "sponsoroitu", "広告", "광고", "赞助内容", "贊助",
        ]
        var ctaPhrases = [
            "learn more", "shop now", "install now", "install app", "download", "sign up", "book now",
            "apply now", "get offer", "order now", "send message", "contact us", "get quote", "watch more",
            "listen now", "play game", "get directions", "call now", "buy tickets", "see menu", "donate now",
            "get showtimes", "get access", "start order", "use app", "open link", "visit site", "visit website",
        ]
        /// Lines in the caption area that are never a username or caption.
        var captionNoise = ["more", "original audio", "paid partnership", "see translation", "follow", "subscribe", "sponsored"]
    }

    var version = DetectorConfig.currentVersion
    var motion = Motion()
    var ocr = OCR()
    var zones = Zones()
    var keywords = Keywords()

    /// Minimum layout score for a screen to be classified as a short-video feed.
    var shortVideoScoreThreshold = 3
    /// Consecutive non-reels readings needed to leave the reels context.
    var exitReadings = 2
    /// Reels context survives this long without a confirming reading.
    var contextStickySeconds = 6.0
    /// A swipe's page decision is forced (without OCR) after this long.
    var pendingDeadline = 1.8
    /// Minimum gap between two implicit (OCR-only) page changes.
    var implicitChangeCooldown = 0.9
    /// Coming back to the same feed within this window is a resume, not a new reel.
    var resumeGuardSeconds = 90.0
    /// Reset the "furthest reel seen" cursor after this long outside reels.
    var feedResetSeconds = 60.0
    /// Gap that ends a scrolling session.
    var sessionGapSeconds = 180.0
    /// Number of recent reel identities remembered for rewatch detection.
    var seenCapacity = 400

    /// Loads the override from the App Group, falling back to defaults.
    static func load(from store: SharedStore = .shared) -> DetectorConfig {
        guard let config = store.read(DetectorConfig.self, from: .detectorConfig),
              config.version == currentVersion else { return DetectorConfig() }
        return config
    }
}
