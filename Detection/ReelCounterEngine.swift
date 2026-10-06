import Foundation

/// Outcome of the counting rules for one observed page.
enum CountDecision: Sendable, Equatable {
    enum Reason: String, Sendable { case swipe, entry, implicit, positional }

    case counted(SourceApp, Reason)
    case skippedAd(SourceApp)
    case skippedRewatch(SourceApp)

    var app: SourceApp {
        switch self {
        case .counted(let app, _), .skippedAd(let app), .skippedRewatch(let app): app
        }
    }
}

/// The counting brain. Pure logic, no frameworks — fed with motion samples
/// (≈20 Hz) and OCR readings (≈1 Hz) by the broadcast extension, fully unit
/// tested in Tests/ReelCounterEngineTests.swift.
///
/// Rules (mirrors what the Android Accessibility version does with view IDs):
///  • A paged vertical swipe inside a short-video feed = a page change.
///  • The new page is read (OCR) once it settles: ads ("Sponsored", CTA
///    buttons) are skipped, reels seen earlier today are rewatches.
///  • Swiping back is a rewatch; swiping forward again over already-seen
///    reels is a rewatch too (tracked by identity, or by position when OCR
///    can't read the overlay).
///  • An auto-replaying/looping reel never counts (no page change).
///  • Coming back to the same reel (app switch, comments closed) never counts.
final class ReelCounterEngine {
    enum Context: Equatable {
        case unknown
        case shortVideo
        case comments
        case other
    }

    private struct PendingPage {
        let direction: SwipeDirection
        let pages: Int
        let settleAt: TimeInterval
        let deadline: TimeInterval
    }

    private(set) var config: DetectorConfig
    private var tracker: SwipeTracker
    private var previousGrid: LumaGrid?

    private(set) var context: Context = .unknown
    private(set) var contextApp: SourceApp?
    private var lastShortVideoAt: TimeInterval = -.infinity
    private var consecutiveNonShort = 0

    private var pending: PendingPage?
    private var cursor = 0
    private var highWater = 0
    private(set) var currentIdentity: ReelIdentity?
    /// Set after a page was decided without OCR: the next reading only tells
    /// us what that page was — it must not be counted again.
    private var adoptNextIdentity = false
    private var lastPageChangeAt: TimeInterval = -.infinity
    private var seen: SeenReels
    private var persistedFingerprints: Set<String> = []

    private var lastOCRAt: TimeInterval = -.infinity
    private var forcedOCRAt: TimeInterval?

    /// Last full-screen cut that wasn't a swipe (new video content).
    private var lastCutAt: TimeInterval = -.infinity
    /// When the current reel's identity was last set or re-confirmed.
    private var identityConfirmedAt: TimeInterval = -.infinity
    /// A reel that looks new but hasn't been confirmed by enough readings.
    private var implicitCandidate: ReelIdentity?
    private var implicitVotes = 0

    /// App reported by the Shortcuts automation, if any.
    var hint: SourceApp?
    /// Only analyse while an automation says a reels app is open.
    var strictMode = false
    /// Hashes a reel identity for the persisted seen-set (salted by caller).
    var fingerprint: (String) -> String = { $0 }
    /// Called when a new strong identity should be persisted.
    var onFingerprint: ((String) -> Void)?

    // Diagnostics
    private(set) var swipesForward = 0
    private(set) var swipesBackward = 0
    private(set) var lastSample: MotionSample?
    private(set) var lastReadingScore = 0
    private(set) var lastDecisionNote = "—"

    init(config: DetectorConfig = DetectorConfig()) {
        self.config = config
        self.tracker = SwipeTracker(config: config.motion)
        self.seen = SeenReels(capacity: config.seenCapacity)
    }

    func update(config: DetectorConfig) {
        self.config = config
        tracker.config = config.motion
    }

    /// Restores today's (hashed) fingerprints after the extension restarts.
    func restoreFingerprints(_ hashes: Set<String>) { persistedFingerprints = hashes }

    func resetForNewDay() {
        seen.removeAll()
        persistedFingerprints.removeAll()
        cursor = 0
        highWater = 0
    }

    var isShortVideo: Bool { context == .shortVideo || context == .comments }

    /// Whether we're allowed to look at the screen at all right now.
    var analysisAllowed: Bool { !strictMode || hint != nil }

    // MARK: Motion path (every analysed frame)

    func process(grid: LumaGrid, at time: TimeInterval) -> [CountDecision] {
        defer { previousGrid = grid }
        guard analysisAllowed,
              let previous = previousGrid,
              previous.width == grid.width, previous.height == grid.height else { return [] }

        let bandTop = Int(Double(grid.height) * config.motion.bandTop)
        let bandBottom = Int(Double(grid.height) * config.motion.bandBottom)
        let maxShift = Int(Double(bandBottom - bandTop) * config.motion.maxShiftFraction)
        let sample = MotionEstimator.estimate(
            previous: previous, current: grid,
            bandTop: bandTop, bandBottom: bandBottom,
            maxShift: maxShift, minOverlap: config.motion.minOverlapRows
        )
        lastSample = sample

        // A big change that isn't a translation (e.g. a frame skipped a whole
        // swipe) — ask OCR to check whether the reel changed.
        if isShortVideo, sample.diff >= config.motion.cutThreshold, !tracker.isTranslation(sample), !tracker.isTracking {
            forcedOCRAt = time + config.ocr.settleDelay
            lastCutAt = time
        }

        guard let event = tracker.push(sample, gridHeight: grid.height, at: time) else { return [] }
        return handle(swipe: event)
    }

    // MARK: Timer path (≈2 Hz)

    func tick(at time: TimeInterval, gridHeight: Int) -> [CountDecision] {
        var out: [CountDecision] = []
        if let event = tracker.settle(at: time, gridHeight: gridHeight) {
            out += handle(swipe: event)
        }
        if let page = pending, time >= page.deadline {
            pending = nil
            out += resolve(page, reading: nil, at: time)
        }
        if context == .shortVideo || context == .comments, time - lastShortVideoAt > config.contextStickySeconds * 3 {
            context = .unknown
        }
        if time - lastShortVideoAt > config.feedResetSeconds {
            cursor = highWater
        }
        return out
    }

    // MARK: OCR scheduling

    func wantsOCR(at time: TimeInterval) -> Bool {
        guard analysisAllowed else { return false }
        if let page = pending, time >= page.settleAt, lastOCRAt < page.settleAt { return true }
        if let forced = forcedOCRAt, time >= forced, time - lastOCRAt >= 0.6 { return true }
        let interval: Double
        switch context {
        case .shortVideo, .comments: interval = config.ocr.intervalInReels
        case .unknown, .other: interval = hint != nil ? config.ocr.intervalHinted : config.ocr.intervalIdle
        }
        return time - lastOCRAt >= interval
    }

    /// Call when a frame is handed to OCR (prevents duplicate requests).
    func markOCRScheduled(at time: TimeInterval) {
        lastOCRAt = time
        forcedOCRAt = nil
    }

    // MARK: OCR path

    func process(reading: ScreenReading) -> [CountDecision] {
        lastReadingScore = reading.score
        let wasShortVideo = context == .shortVideo
        updateContext(with: reading)

        if let page = pending, reading.at >= page.settleAt {
            pending = nil
            switch reading.kind {
            case .shortVideo:
                return resolve(page, reading: reading, at: reading.at)
            case .comments:
                return note([], "swipe inside comments")
            case .other:
                // One odd reading right after a swipe (overlay fading in, toast
                // on top…) shouldn't lose the reel while reels context is sticky.
                return context == .shortVideo ? resolve(page, reading: nil, at: reading.at) : note([], "swipe not in reels")
            }
        }
        guard context == .shortVideo, reading.kind == .shortVideo else { return [] }

        let app = reading.app ?? contextApp ?? hint ?? .other
        if adoptNextIdentity, let identity = reading.identity {
            adoptNextIdentity = false
            currentIdentity = identity
            confirmIdentity(at: reading.at)
            seen.insert(identity)
            persist(identity)
            return note([], "adopted identity")
        }
        guard let identity = reading.identity else {
            if !wasShortVideo, reading.at - lastPageChangeAt > config.resumeGuardSeconds, currentIdentity == nil {
                // Entered a feed we can't read (e.g. non-Latin overlay): count the first reel once.
                lastPageChangeAt = reading.at
                return note(reading.isAd ? [.skippedAd(app)] : [.counted(app, .entry)], "entry (no identity)")
            }
            return []
        }

        if !wasShortVideo || currentIdentity == nil {
            // Opened the feed / came back to the app. Resumed reels don't count.
            if let current = currentIdentity, identity.compare(current) != .different {
                currentIdentity = identity
                confirmIdentity(at: reading.at)
                return note([], "resume same reel")
            }
            return register(identity, isAd: reading.isAd, app: app, reason: .entry, at: reading.at)
        }

        if let current = currentIdentity,
           identity.differsStrongly(from: current),
           reading.at - lastPageChangeAt > config.implicitChangeCooldown,
           pending == nil,
           !tracker.isTracking {
            // Reel changed without a detected swipe (missed frames, auto-scroll)?
            // Only if the picture really changed — OCR misreads on a still
            // scene must never count — and several readings agree.
            guard lastCutAt > identityConfirmedAt else {
                return note([], "overlay changed, picture didn't")
            }
            if let candidate = implicitCandidate, candidate.compare(identity) == .same {
                implicitVotes += 1
            } else {
                implicitCandidate = identity
                implicitVotes = 1
            }
            guard implicitVotes >= max(config.implicitConfirmations, 1) else {
                return note([], "new reel? confirming")
            }
            return register(identity, isAd: reading.isAd, app: app, reason: .implicit, at: reading.at)
        }

        if let current = currentIdentity, identity.compare(current) == .same {
            // Same reel, maybe with more overlay text readable now.
            currentIdentity = merge(current, identity)
            confirmIdentity(at: reading.at)
        }
        return []
    }

    // MARK: Internals

    private func updateContext(with reading: ScreenReading) {
        switch reading.kind {
        case .shortVideo:
            context = .shortVideo
            contextApp = reading.app ?? contextApp
            lastShortVideoAt = reading.at
            consecutiveNonShort = 0
        case .comments:
            if isShortVideo || hint != nil {
                context = .comments
                lastShortVideoAt = reading.at
            }
            consecutiveNonShort = 0
        case .other:
            consecutiveNonShort += 1
            if consecutiveNonShort >= config.exitReadings || reading.at - lastShortVideoAt > config.contextStickySeconds {
                if context != .other { tracker.reset() }
                context = .other
            }
        }
    }

    private func swipesAllowed() -> Bool {
        switch context {
        case .shortVideo: true
        case .comments, .other: false
        case .unknown: hint != nil
        }
    }

    private func handle(swipe event: SwipeEvent) -> [CountDecision] {
        if event.direction == .forward { swipesForward += 1 } else if event.direction == .backward { swipesBackward += 1 }
        guard swipesAllowed() else { return [] }
        var out: [CountDecision] = []
        if let old = pending {
            // Rapid swipes: settle the previous page without waiting for OCR.
            out += resolve(old, reading: nil, at: event.endedAt)
        }
        pending = PendingPage(
            direction: event.direction,
            pages: event.pages,
            settleAt: event.endedAt + config.ocr.settleDelay,
            deadline: event.endedAt + config.pendingDeadline
        )
        return out
    }

    private func resolve(_ page: PendingPage, reading: ScreenReading?, at time: TimeInterval) -> [CountDecision] {
        lastPageChangeAt = time
        let app = reading?.app ?? contextApp ?? hint ?? .other

        guard let reading else {
            // OCR was too slow / unavailable — fall back to position tracking.
            guard context == .shortVideo else { return note([], "swipe outside reels") }
            switch page.direction {
            case .backward:
                cursor -= page.pages
                currentIdentity = nil
                adoptNextIdentity = true
                return note([.skippedRewatch(app)], "back swipe (no ocr)")
            case .forward:
                return note(positional(page.pages, app: app), "forward (no ocr)")
            case .unknown:
                return []
            }
        }

        guard reading.kind == .shortVideo else { return note([], "swipe not in reels") }

        adoptNextIdentity = false
        if page.direction == .backward {
            cursor -= page.pages
            if let identity = reading.identity {
                currentIdentity = identity
                confirmIdentity(at: time)
                seen.insert(identity)
            } else {
                currentIdentity = nil
                adoptNextIdentity = true
            }
            return note([.skippedRewatch(app)], "back swipe")
        }

        var out: [CountDecision] = []
        if page.pages > 1 { out += positional(page.pages - 1, app: app) }

        guard let identity = reading.identity else {
            if reading.isAd {
                cursor += 1
                highWater = max(highWater, cursor)
                return note(out + [.skippedAd(app)], "ad (no identity)")
            }
            return note(out + positional(1, app: app), "forward (no identity)")
        }

        if let current = currentIdentity {
            let match = identity.compare(current)
            // Same overlay after the "swipe" → it was a camera pan or a partial
            // drag, not a new reel.
            if match == .same || (page.direction == .unknown && match == .unknown) {
                confirmIdentity(at: time)
                return note(out, "no page change")
            }
        }
        cursor += 1
        return out + register(identity, isAd: reading.isAd, app: app, reason: .swipe, at: time)
    }

    /// Final decision for a page whose identity we know.
    private func register(_ identity: ReelIdentity, isAd: Bool, app: SourceApp, reason: CountDecision.Reason, at time: TimeInterval) -> [CountDecision] {
        lastPageChangeAt = time
        adoptNextIdentity = false
        confirmIdentity(at: time)
        defer { currentIdentity = identity }

        if isAd {
            seen.insert(identity)
            highWater = max(highWater, cursor)
            return note([.skippedAd(app)], "ad (\(reason.rawValue))")
        }
        if seen.contains(identity) || isPersisted(identity) {
            return note(reason == .entry ? [] : [.skippedRewatch(app)], "rewatch (\(reason.rawValue))")
        }
        seen.insert(identity)
        persist(identity)
        // A new reel means we're at the frontier of the feed.
        highWater = max(highWater, cursor)
        cursor = highWater
        return note([.counted(app, reason)], "counted (\(reason.rawValue))")
    }

    /// Counting by position when the overlay can't be read.
    private func positional(_ pages: Int, app: SourceApp) -> [CountDecision] {
        var out: [CountDecision] = []
        for _ in 0..<max(pages, 0) {
            cursor += 1
            if cursor > highWater {
                highWater = cursor
                out.append(.counted(app, .positional))
            } else {
                out.append(.skippedRewatch(app))
            }
        }
        currentIdentity = nil
        adoptNextIdentity = true
        return out
    }

    /// The current identity is trustworthy as of `time`; any pending
    /// "new reel?" suspicion is dropped.
    private func confirmIdentity(at time: TimeInterval) {
        identityConfirmedAt = time
        implicitCandidate = nil
        implicitVotes = 0
    }

    private func merge(_ a: ReelIdentity, _ b: ReelIdentity) -> ReelIdentity {
        ReelIdentity(handle: a.handle ?? b.handle, caption: a.caption ?? b.caption, likes: a.likes ?? b.likes)
    }

    private func isPersisted(_ identity: ReelIdentity) -> Bool {
        guard let source = identity.fingerprintSource else { return false }
        return persistedFingerprints.contains(fingerprint(source))
    }

    private func persist(_ identity: ReelIdentity) {
        guard let source = identity.fingerprintSource else { return }
        let hash = fingerprint(source)
        if persistedFingerprints.insert(hash).inserted { onFingerprint?(hash) }
    }

    private func note(_ decisions: [CountDecision], _ text: String) -> [CountDecision] {
        lastDecisionNote = text
        return decisions
    }
}
