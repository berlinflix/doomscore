import Foundation

/// A tiny grayscale thumbnail of the screen (default 48×104) used for motion
/// estimation. Built from the luma plane of each ReplayKit frame.
struct LumaGrid: Sendable, Equatable {
    let width: Int
    let height: Int
    var values: [UInt8]

    init(width: Int, height: Int, values: [UInt8]) {
        precondition(values.count == width * height, "LumaGrid size mismatch")
        self.width = width
        self.height = height
        self.values = values
    }

    init(width: Int, height: Int, fill: UInt8 = 0) {
        self.init(width: width, height: height, values: Array(repeating: fill, count: width * height))
    }

    subscript(x: Int, y: Int) -> UInt8 {
        get { values[y * width + x] }
        set { values[y * width + x] = newValue }
    }
}

/// Result of comparing two consecutive grids.
struct MotionSample: Sendable, Equatable {
    /// Vertical shift in grid rows. Positive = content moved UP (next reel).
    let shift: Int
    /// Mean absolute luma difference with no shift (0–255).
    let diff: Double
    /// Mean absolute difference at the best shift.
    let bestDiff: Double

    /// How much of the frame difference is explained by a pure translation.
    var improvement: Double { diff > 0 ? 1 - bestDiff / diff : 0 }
}

enum MotionEstimator {
    /// Exhaustive vertical block matching inside `[bandTop, bandBottom)`.
    /// Finds `s` minimising |current[y] − previous[y + s]|.
    static func estimate(previous: LumaGrid, current: LumaGrid, bandTop: Int, bandBottom: Int, maxShift: Int, minOverlap: Int) -> MotionSample {
        guard previous.width == current.width, previous.height == current.height,
              bandTop >= 0, bandBottom <= current.height, bandBottom - bandTop > minOverlap else {
            return MotionSample(shift: 0, diff: 0, bestDiff: 0)
        }
        let width = current.width
        return current.values.withUnsafeBufferPointer { cur in
            previous.values.withUnsafeBufferPointer { prev in
                func meanAbsDiff(_ shift: Int) -> Double? {
                    let y0 = max(bandTop, bandTop - shift)
                    let y1 = min(bandBottom, bandBottom - shift)
                    let rows = y1 - y0
                    guard rows >= minOverlap else { return nil }
                    var total = 0
                    for y in y0..<y1 {
                        let c = y * width
                        let p = (y + shift) * width
                        for x in 0..<width {
                            let d = Int(cur[c + x]) - Int(prev[p + x])
                            total += d < 0 ? -d : d
                        }
                    }
                    return Double(total) / Double(rows * width)
                }

                let zero = meanAbsDiff(0) ?? 0
                var best = zero
                var bestShift = 0
                for shift in -maxShift...maxShift where shift != 0 {
                    guard let d = meanAbsDiff(shift) else { continue }
                    // Prefer smaller shifts on near-ties to avoid aliasing jumps.
                    if d < best - 0.01 || (abs(d - best) <= 0.01 && abs(shift) < abs(bestShift)) {
                        best = d
                        bestShift = shift
                    }
                }
                return MotionSample(shift: bestShift, diff: zero, bestDiff: best)
            }
        }
    }
}

enum SwipeDirection: String, Sendable, Equatable {
    case forward   // content moved up → next reel
    case backward  // content moved down → previous reel
    case unknown
}

struct SwipeEvent: Sendable, Equatable {
    let direction: SwipeDirection
    let pages: Int
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    /// Signed travel as a fraction of the screen height.
    let travel: Double
}

/// Accumulates per-frame translations into paged swipe gestures.
/// Reels/Shorts/TikTok feeds snap exactly one page per swipe, which lets us
/// reject partial drags (bounce back) and free-scrolling lists (feeds,
/// comments) that move by arbitrary amounts or for too long.
struct SwipeTracker: Sendable {
    var config: DetectorConfig.Motion
    private(set) var isTracking = false
    private var accumulated = 0.0
    private var startedAt: TimeInterval = 0
    private var lastMotionAt: TimeInterval = 0

    init(config: DetectorConfig.Motion) { self.config = config }

    mutating func reset() {
        isTracking = false
        accumulated = 0
    }

    func isTranslation(_ sample: MotionSample) -> Bool {
        sample.shift != 0
            && abs(sample.shift) >= config.minShiftRows
            && sample.improvement >= config.minImprovement
            && sample.diff >= config.noiseFloor
    }

    /// Feed one motion sample. Returns a completed swipe once content settles.
    mutating func push(_ sample: MotionSample, gridHeight: Int, at time: TimeInterval) -> SwipeEvent? {
        if isTranslation(sample) {
            if !isTracking {
                isTracking = true
                startedAt = time
                accumulated = 0
            }
            accumulated += Double(sample.shift)
            lastMotionAt = time
            if time - startedAt > config.maxGestureDuration { reset() }
            return nil
        }
        return settle(at: time, gridHeight: gridHeight)
    }

    /// Closes a gesture when frames stop arriving (static screen).
    mutating func settle(at time: TimeInterval, gridHeight: Int) -> SwipeEvent? {
        guard isTracking, time - lastMotionAt >= config.settleDelay else { return nil }
        let travel = accumulated / Double(max(gridHeight, 1))
        let started = startedAt
        reset()
        let pages = abs(travel) / config.pageFraction
        guard pages >= config.minPageFraction, pages <= config.maxPagesPerGesture else { return nil }
        let count = max(1, Int((pages + 0.35).rounded(.down)))
        return SwipeEvent(
            direction: travel > 0 ? .forward : .backward,
            pages: count,
            startedAt: started,
            endedAt: time,
            travel: travel
        )
    }
}
