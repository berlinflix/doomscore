import CoreGraphics
import XCTest

final class MotionEstimatorTests: XCTestCase {
    func testDetectsUpwardShift() {
        let base = TestGrids.textured(width: 48, height: 104, seed: 3)
        let moved = TestGrids.shifted(base, by: 12, seed: 4)
        let sample = MotionEstimator.estimate(previous: base, current: moved, bandTop: 10, bandBottom: 91, maxShift: 48, minOverlap: 20)
        XCTAssertEqual(sample.shift, 12)
        XCTAssertGreaterThan(sample.improvement, 0.8)
    }

    func testDetectsDownwardShift() {
        let base = TestGrids.textured(width: 48, height: 104, seed: 5)
        let moved = TestGrids.shifted(base, by: -9, seed: 6)
        let sample = MotionEstimator.estimate(previous: base, current: moved, bandTop: 10, bandBottom: 91, maxShift: 48, minOverlap: 20)
        XCTAssertEqual(sample.shift, -9)
    }

    func testStaticFrameHasNoShift() {
        let base = TestGrids.textured(width: 48, height: 104, seed: 8)
        let sample = MotionEstimator.estimate(previous: base, current: base, bandTop: 10, bandBottom: 91, maxShift: 48, minOverlap: 20)
        XCTAssertEqual(sample.shift, 0)
        XCTAssertEqual(sample.diff, 0)
    }

    func testSwipeTrackerEmitsOnePageForward() {
        var tracker = SwipeTracker(config: DetectorConfig().motion)
        var time: TimeInterval = 0
        for _ in 0..<6 {
            time += 0.05
            XCTAssertNil(tracker.push(MotionSample(shift: 15, diff: 40, bestDiff: 5), gridHeight: 104, at: time))
        }
        time += 0.3
        let event = tracker.push(MotionSample(shift: 0, diff: 3, bestDiff: 3), gridHeight: 104, at: time)
        XCTAssertEqual(event?.direction, .forward)
        XCTAssertEqual(event?.pages, 1)
    }

    func testPartialDragThatBouncesBackIsIgnored() {
        var tracker = SwipeTracker(config: DetectorConfig().motion)
        var time: TimeInterval = 0
        for shift in [8, 8, 6, -6, -8, -8] {
            time += 0.05
            _ = tracker.push(MotionSample(shift: shift, diff: 30, bestDiff: 4), gridHeight: 104, at: time)
        }
        time += 0.3
        XCTAssertNil(tracker.settle(at: time, gridHeight: 104))
    }

    func testLongContinuousScrollIsNotAPagedSwipe() {
        var tracker = SwipeTracker(config: DetectorConfig().motion)
        var time: TimeInterval = 0
        var events: [SwipeEvent] = []
        for _ in 0..<80 { // 4 s of continuous scrolling (a feed or comment list)
            time += 0.05
            if let event = tracker.push(MotionSample(shift: 4, diff: 25, bestDiff: 4), gridHeight: 104, at: time) { events.append(event) }
        }
        time += 0.3
        if let event = tracker.settle(at: time, gridHeight: 104) { events.append(event) }
        XCTAssertTrue(events.allSatisfy { $0.pages <= 3 }, "feed scrolling must not turn into dozens of reels")
    }
}

final class ScreenClassifierTests: XCTestCase {
    private let classifier = ScreenClassifier(config: DetectorConfig())

    private func item(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.2, h: CGFloat = 0.02) -> TextItem {
        TextItem(text: text, box: CGRect(x: x, y: y, width: w, height: h), confidence: 0.9)
    }

    /// Roughly how Instagram Reels lays out its overlay.
    private func instagramReel(sponsored: Bool = false, handle: String = "creator.one", following: Bool = false) -> [TextItem] {
        var items = [
            item("Reels", x: 0.04, y: 0.06, w: 0.15),
            item("12.4K", x: 0.86, y: 0.52, w: 0.1),
            item("312", x: 0.87, y: 0.60, w: 0.08),
            item("1,093", x: 0.86, y: 0.68, w: 0.1),
            item(handle, x: 0.14, y: 0.80, w: 0.25),
            item("when the reel hits different at 3am", x: 0.04, y: 0.85, w: 0.6),
            item("Original audio", x: 0.1, y: 0.90, w: 0.3),
        ]
        if !following { items.append(item("Follow", x: 0.42, y: 0.80, w: 0.12)) }
        if sponsored { items.append(item("Sponsored", x: 0.14, y: 0.825, w: 0.2)) }
        return items
    }

    /// CapCut-style captions burned into the video: big, centred, a new word every second.
    private func subtitles(_ words: [String]) -> [TextItem] {
        words.enumerated().map { index, word in
            item(word, x: 0.3, y: 0.62 + CGFloat(index) * 0.07, w: 0.4, h: 0.06)
        }
    }

    func testRecognisesInstagramReels() {
        let reading = classifier.classify(instagramReel(), hint: nil, at: 0)
        XCTAssertEqual(reading.kind, .shortVideo)
        XCTAssertEqual(reading.app, .instagram)
        XCTAssertFalse(reading.isAd)
        XCTAssertEqual(reading.identity?.handle, "creator.one")
        XCTAssertEqual(reading.identity?.likes, 12_400)
    }

    func testDetectsSponsoredReel() {
        let reading = classifier.classify(instagramReel(sponsored: true), hint: nil, at: 0)
        XCTAssertEqual(reading.kind, .shortVideo)
        XCTAssertTrue(reading.isAd)
    }

    func testDetectsCTAButtonAd() {
        var items = instagramReel(handle: "somebrand")
        items.append(item("Shop now", x: 0.05, y: 0.74, w: 0.7))
        XCTAssertTrue(classifier.classify(items, hint: nil, at: 0).isAd)
    }

    func testBurnedInSubtitlesNeverBecomeTheIdentity() {
        // Already following the creator → no Follow button to anchor on.
        let first = classifier.classify(instagramReel(following: true) + subtitles(["WAIT", "FOR IT"]), hint: nil, at: 0)
        let second = classifier.classify(instagramReel(following: true) + subtitles(["INSANE", "ENDING"]), hint: nil, at: 1)
        XCTAssertEqual(first.kind, .shortVideo)
        XCTAssertEqual(first.identity?.handle, "creator.one")
        XCTAssertEqual(first.identity?.caption, second.identity?.caption)
        if let a = first.identity, let b = second.identity {
            XCTAssertEqual(a.compare(b), .same, "changing subtitles must not look like a new reel")
        } else {
            XCTFail("identity missing")
        }
    }

    func testSubtitleWordsDontLookLikeAds() {
        let items = instagramReel() + [item("DOWNLOAD THIS NOW", x: 0.1, y: 0.7, w: 0.8, h: 0.07)]
        XCTAssertFalse(classifier.classify(items, hint: nil, at: 0).isAd)
    }

    func testRecognisesReelsWithoutLikeCounts() {
        // Creator hid likes and you already follow them: one rail number + audio line.
        let items = [
            item("312", x: 0.87, y: 0.60, w: 0.08),
            item("creator.one", x: 0.14, y: 0.80, w: 0.25),
            item("when the reel hits different at 3am", x: 0.04, y: 0.85, w: 0.6),
            item("♫ creator.one · Original audio", x: 0.1, y: 0.90, w: 0.5),
        ]
        let reading = classifier.classify(items, hint: .instagram, at: 0)
        XCTAssertEqual(reading.kind, .shortVideo)
        XCTAssertEqual(reading.identity?.handle, "creator.one")
    }

    func testCommentsSheet() {
        var items = instagramReel()
        items.append(item("Add a comment…", x: 0.1, y: 0.93, w: 0.5))
        XCTAssertEqual(classifier.classify(items, hint: .instagram, at: 0).kind, .comments)
    }

    func testHomeFeedIsNotReels() {
        let items = [
            item("Your story", x: 0.02, y: 0.16, w: 0.18),
            item("creator.one", x: 0.12, y: 0.25, w: 0.25),
            item("Liked by someone and others", x: 0.03, y: 0.72, w: 0.6),
            item("View all comments", x: 0.03, y: 0.8, w: 0.4),
        ]
        XCTAssertEqual(classifier.classify(items, hint: .instagram, at: 0).kind, .other)
    }

    func testYouTubeShorts() {
        let items = [
            item("12K", x: 0.87, y: 0.50, w: 0.08),
            item("Dislike", x: 0.85, y: 0.58, w: 0.12),
            item("345", x: 0.87, y: 0.66, w: 0.08),
            item("Share", x: 0.86, y: 0.74, w: 0.1),
            item("@channelname", x: 0.12, y: 0.82, w: 0.3),
            item("Subscribe", x: 0.45, y: 0.82, w: 0.18),
            item("this short is insane wait for it", x: 0.04, y: 0.87, w: 0.6),
        ]
        let reading = classifier.classify(items, hint: nil, at: 0)
        XCTAssertEqual(reading.kind, .shortVideo)
        XCTAssertEqual(reading.app, .youtube)
        XCTAssertEqual(reading.identity?.handle, "channelname")
    }

    func testCountText() {
        XCTAssertTrue(CountText.isCount("12.4k"))
        XCTAssertTrue(CountText.isCount("1,093"))
        XCTAssertFalse(CountText.isCount("0:15"))
        XCTAssertFalse(CountText.isCount("2d"))
        XCTAssertEqual(CountText.value("1.2m"), 1_200_000)
        XCTAssertEqual(CountText.value("1,093"), 1093)
    }

    func testIdentityComparisonToleratesLikeBump() {
        let a = ReelIdentity(handle: "creator.one", caption: nil, likes: 85)
        let b = ReelIdentity(handle: "creator.one", caption: nil, likes: 86)
        XCTAssertEqual(a.compare(b), .same)
        let c = ReelIdentity(handle: "other.person", caption: nil, likes: 85)
        XCTAssertEqual(a.compare(c), .different)
    }
}
