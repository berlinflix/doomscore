import CoreGraphics
import XCTest

/// Drives the counting engine with synthetic readings/swipes — the same inputs
/// the broadcast extension produces from real frames.
final class ReelCounterEngineTests: XCTestCase {
    private var engine: ReelCounterEngine!
    private var clock: TimeInterval = 100

    override func setUp() {
        super.setUp()
        engine = ReelCounterEngine(config: DetectorConfig())
        clock = 100
    }

    // MARK: Helpers

    private func reading(handle: String?, caption: String? = nil, likes: Double? = nil, ad: Bool = false, kind: ScreenReading.Kind = .shortVideo, at time: TimeInterval? = nil) -> ScreenReading {
        let identity = ReelIdentity(handle: handle, caption: caption, likes: likes)
        return ScreenReading(kind: kind, app: .instagram, isAd: ad, identity: identity.isEmpty ? nil : identity, score: 5, at: time ?? clock)
    }

    /// Simulates a paged swipe through the motion path (content moves by ~one page).
    @discardableResult
    private func swipe(forward: Bool = true) -> [CountDecision] {
        let config = DetectorConfig()
        let height = config.motion.gridHeight
        let width = config.motion.gridWidth
        var decisions: [CountDecision] = []
        var grid = TestGrids.textured(width: width, height: height, seed: Int(clock * 10))
        decisions += engine.process(grid: grid, at: clock)
        // 6 frames × 15 rows ≈ 90 rows ≈ one page
        for _ in 0..<6 {
            clock += 0.05
            grid = TestGrids.shifted(grid, by: forward ? 15 : -15, seed: Int(clock * 1000))
            decisions += engine.process(grid: grid, at: clock)
        }
        // settle
        clock += 0.3
        decisions += engine.tick(at: clock, gridHeight: height)
        return decisions
    }

    private func counted(_ decisions: [CountDecision]) -> Int {
        decisions.filter { if case .counted = $0 { true } else { false } }.count
    }

    private func enterReels(handle: String = "creator.one") -> [CountDecision] {
        engine.process(reading: reading(handle: handle, caption: "first reel caption here"))
    }

    // MARK: Tests

    func testFirstReelOnEntryCounts() {
        XCTAssertEqual(counted(enterReels()), 1)
    }

    func testResumedReelDoesNotCountTwice() {
        _ = enterReels()
        clock += 5
        _ = engine.process(reading: reading(handle: nil, kind: .other))
        _ = engine.process(reading: reading(handle: nil, kind: .other))
        clock += 30
        let decisions = engine.process(reading: reading(handle: "creator.one", caption: "first reel caption here"))
        XCTAssertEqual(counted(decisions), 0, "coming back to the same reel is a resume")
    }

    func testForwardSwipeWithNewIdentityCounts() {
        _ = enterReels()
        clock += 3
        swipe(forward: true)
        clock += 0.4
        let decisions = engine.process(reading: reading(handle: "creator.two", caption: "a totally different caption"))
        XCTAssertEqual(counted(decisions), 1)
    }

    func testAdsAreSkipped() {
        _ = enterReels()
        clock += 3
        swipe(forward: true)
        clock += 0.4
        let decisions = engine.process(reading: reading(handle: "brandname", caption: "shop the new drop today", ad: true))
        XCTAssertEqual(counted(decisions), 0)
        XCTAssertTrue(decisions.contains(.skippedAd(.instagram)))
    }

    func testBackSwipeAndReturnAreRewatches() {
        _ = enterReels(handle: "creator.one")
        clock += 3
        swipe(forward: true)
        clock += 0.4
        XCTAssertEqual(counted(engine.process(reading: reading(handle: "creator.two", caption: "second reel caption text"))), 1)

        clock += 3
        let back = swipe(forward: false)
        clock += 0.4
        let backDecisions = back + engine.process(reading: reading(handle: "creator.one", caption: "first reel caption here"))
        XCTAssertEqual(counted(backDecisions), 0, "swiping back is a rewatch")

        clock += 3
        swipe(forward: true)
        clock += 0.4
        let again = engine.process(reading: reading(handle: "creator.two", caption: "second reel caption text"))
        XCTAssertEqual(counted(again), 0, "swiping forward onto an already-seen reel is a rewatch")
    }

    func testPositionalFallbackWithoutOCR() {
        _ = enterReels()
        clock += 3
        swipe(forward: true)
        // No OCR arrives — the pending page resolves at its deadline.
        clock += 2.5
        let decisions = engine.tick(at: clock, gridHeight: DetectorConfig().motion.gridHeight)
        XCTAssertEqual(counted(decisions), 1)

        // The next reading only reveals which reel that was — no double count.
        clock += 0.5
        let adopt = engine.process(reading: reading(handle: "creator.two", caption: "some other caption"))
        XCTAssertEqual(counted(adopt), 0)
    }

    func testCommentsSheetBlocksSwipes() {
        _ = enterReels()
        clock += 2
        _ = engine.process(reading: reading(handle: nil, kind: .comments))
        clock += 1
        let decisions = swipe(forward: true)
        XCTAssertEqual(counted(decisions), 0)
    }

    func testImplicitChangeCountsWhenSwipeWasMissed() {
        _ = enterReels(handle: "creator.one")
        clock += 5
        let decisions = engine.process(reading: reading(handle: "someone.else", caption: "brand new video caption"))
        XCTAssertEqual(counted(decisions), 1)
    }

    func testSameOverlayAfterFalseSwipeIsIgnored() {
        _ = enterReels(handle: "creator.one")
        clock += 3
        swipe(forward: true) // e.g. a vertical camera pan inside the video
        clock += 0.4
        let decisions = engine.process(reading: reading(handle: "creator.one", caption: "first reel caption here"))
        XCTAssertEqual(counted(decisions), 0)
        XCTAssertTrue(decisions.isEmpty)
    }

    func testStrictModeWithoutHintDoesNothing() {
        engine.strictMode = true
        engine.hint = nil
        XCTAssertFalse(engine.wantsOCR(at: clock + 10))
        XCTAssertEqual(counted(swipe(forward: true)), 0)
    }
}

/// Synthetic luma grids with enough texture for block matching.
enum TestGrids {
    static func textured(width: Int, height: Int, seed: Int) -> LumaGrid {
        var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed) &+ 1)
        var values = [UInt8](repeating: 0, count: width * height)
        for i in values.indices { values[i] = UInt8.random(in: 0...255, using: &generator) }
        return LumaGrid(width: width, height: height, values: values)
    }

    /// Moves content up by `rows` (positive) and fills the gap with fresh texture.
    static func shifted(_ grid: LumaGrid, by rows: Int, seed: Int) -> LumaGrid {
        var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed) &+ 7)
        var out = LumaGrid(width: grid.width, height: grid.height)
        for y in 0..<grid.height {
            let source = y + rows
            for x in 0..<grid.width {
                if source >= 0 && source < grid.height {
                    out[x, y] = grid[x, source]
                } else {
                    out[x, y] = UInt8.random(in: 0...255, using: &generator)
                }
            }
        }
        return out
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
