import CoreMedia
import CoreVideo
import CryptoKit
import Foundation
import os

/// Wires ReplayKit frames → motion + OCR → ReelCounterEngine → StatsRecorder.
///
/// Threads:
///  • ReplayKit callback thread: throttles frames, builds the 48×104 luma grid
///    and (when asked) a half-res grayscale copy for OCR. Never retains frames.
///  • analysisQueue: engine, recorder, timers, diagnostics.
///  • ocrQueue: Vision text recognition (one request in flight at most).
final class DetectionPipeline {
    var onStopRequested: (() -> Void)?

    private struct FrameGate {
        var paused = false
        var ocrWanted = false
        var ocrInFlight = false
        var lastProcessed: TimeInterval = 0
        var lastFrame: TimeInterval = 0
    }

    private struct SeenFingerprints: Codable {
        var day: DayKey
        var hashes: [String]
    }

    private let analysisQueue: DispatchQueue
    private let ocrQueue = DispatchQueue(label: "app.doomscore.ocr", qos: .utility)
    private let store = SharedStore.shared
    private let settings = SharedSettings.shared

    // Immutable after init — safe to read from the callback thread.
    private let frameInterval: TimeInterval
    private let gridWidth: Int
    private let gridHeight: Int
    private let ocrConfig: DetectorConfig.OCR
    private let gate = OSAllocatedUnfairLock(initialState: FrameGate())

    // Callback thread only.
    private var grayBuffer: CVPixelBuffer?

    // ocrQueue only.
    private var recognizer: TextRecognizer?

    // analysisQueue only.
    private var config: DetectorConfig
    private let engine: ReelCounterEngine
    private var classifier: ScreenClassifier
    private let recorder: StatsRecorder
    private var timer: DispatchSourceTimer?
    private var diagnostics = DetectorDiagnostics()
    private var diagnosticsEnabled: Bool
    private var framesProcessed = 0
    private var fpsWindowStart: TimeInterval = 0
    private var fpsWindowFrames = 0
    private var lastDiagnosticsWrite: TimeInterval = 0
    private var lastHintRefresh: TimeInterval = -.infinity
    private var fingerprints = Set<String>()
    private var fingerprintsDirty = false
    private var lastFingerprintWrite: TimeInterval = 0

    private var observers: [UUID] = []

    init() {
        let config = DetectorConfig.load()
        let queue = DispatchQueue(label: "app.doomscore.analysis", qos: .userInitiated)
        self.analysisQueue = queue
        self.config = config
        self.frameInterval = 1.0 / max(config.motion.processFPS, 1)
        self.gridWidth = config.motion.gridWidth
        self.gridHeight = config.motion.gridHeight
        self.ocrConfig = config.ocr
        self.engine = ReelCounterEngine(config: config)
        self.classifier = ScreenClassifier(config: config)
        self.recorder = StatsRecorder(queue: queue, sessionGap: config.sessionGapSeconds)
        self.diagnosticsEnabled = SharedSettings.shared.diagnosticsEnabled
    }

    // MARK: Lifecycle (called by SampleHandler)

    func start() {
        analysisQueue.async { [self] in
            let salt = settings.identitySalt
            engine.strictMode = settings.strictPrivacyMode
            engine.fingerprint = { source in DetectionPipeline.hash(salt + "|" + source) }
            engine.onFingerprint = { [weak self] hash in
                self?.fingerprints.insert(hash)
                self?.fingerprintsDirty = true
            }
            recorder.onDayChanged = { [weak self] in
                guard let self else { return }
                self.engine.resetForNewDay()
                self.fingerprints.removeAll()
                self.fingerprintsDirty = true
            }
            loadFingerprints()
            refreshHint(force: true)
            recorder.start(now: Date())
            startTimer()
            Log.detector.info("broadcast started")
        }
        observeDarwin()
    }

    func pause() {
        gate.withLockUnchecked { $0.paused = true }
        analysisQueue.async { [self] in recorder.setContext(inReels: false, app: nil, now: Date()) }
    }

    func resume() {
        gate.withLockUnchecked { $0.paused = false }
    }

    func finish() {
        observers.forEach { DarwinCenter.shared.remove($0) }
        observers.removeAll()
        gate.withLockUnchecked { $0.paused = true }
        analysisQueue.sync {
            timer?.cancel()
            timer = nil
            persistFingerprints(force: true)
            recorder.finish(now: Date())
        }
        Log.detector.info("broadcast finished")
    }

    // MARK: Frames (ReplayKit callback thread)

    func ingest(_ sampleBuffer: CMSampleBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        let interval = frameInterval
        let decision: (process: Bool, ocr: Bool) = gate.withLockUnchecked { gate in
            gate.lastFrame = now
            guard !gate.paused, now - gate.lastProcessed >= interval else { return (false, false) }
            gate.lastProcessed = now
            let ocr = gate.ocrWanted && !gate.ocrInFlight
            if ocr {
                gate.ocrWanted = false
                gate.ocrInFlight = true
            }
            return (true, ocr)
        }
        guard decision.process else { return }

        guard FrameSampler.isPortraitUp(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let grid = FrameSampler.lumaGrid(from: pixelBuffer, width: gridWidth, height: gridHeight) else {
            if decision.ocr { gate.withLockUnchecked { $0.ocrInFlight = false } }
            return
        }

        let ocrImage = decision.ocr ? prepareOCRImage(from: pixelBuffer) : nil
        analysisQueue.async { [weak self] in self?.analyze(grid, at: now) }

        if let ocrImage {
            ocrQueue.async { [weak self] in self?.runOCR(on: ocrImage, capturedAt: now) }
        } else if decision.ocr {
            gate.withLockUnchecked { $0.ocrInFlight = false }
        }
    }

    private func prepareOCRImage(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let factor = max(ocrConfig.downscale, 1)
        let width = CVPixelBufferGetWidth(pixelBuffer) / factor
        let height = CVPixelBufferGetHeight(pixelBuffer) / factor
        guard width > 0, height > 0 else { return nil }
        if let existing = grayBuffer,
           CVPixelBufferGetWidth(existing) == width, CVPixelBufferGetHeight(existing) == height {
            // reuse
        } else {
            grayBuffer = FrameSampler.makeGrayBuffer(width: width, height: height)
        }
        guard let gray = grayBuffer, FrameSampler.downscaleLuma(from: pixelBuffer, into: gray) else { return nil }
        return gray
    }

    // MARK: OCR (ocrQueue)

    private func runOCR(on image: CVPixelBuffer, capturedAt time: TimeInterval) {
        defer { gate.withLockUnchecked { $0.ocrInFlight = false } }
        let availableMB = Double(os_proc_available_memory()) / 1_048_576
        if availableMB > 0, availableMB < ocrConfig.minAvailableMemoryMB {
            Log.detector.warning("skipping OCR: low memory")
            return
        }
        if recognizer == nil { recognizer = TextRecognizer(config: ocrConfig) }
        let started = ProcessInfo.processInfo.systemUptime
        let items = recognizer?.recognize(in: image) ?? []
        let millis = (ProcessInfo.processInfo.systemUptime - started) * 1000
        analysisQueue.async { [weak self] in
            self?.handleText(items, capturedAt: time, millis: millis, memoryMB: availableMB)
        }
    }

    // MARK: Analysis (analysisQueue)

    private func analyze(_ grid: LumaGrid, at time: TimeInterval) {
        framesProcessed += 1
        fpsWindowFrames += 1
        if time - fpsWindowStart >= 2 {
            diagnostics.processedFPS = Double(fpsWindowFrames) / max(time - fpsWindowStart, 0.001)
            fpsWindowStart = time
            fpsWindowFrames = 0
        }
        commit(engine.process(grid: grid, at: time))
        scheduleOCRIfNeeded(at: time)
    }

    private func handleText(_ items: [TextItem], capturedAt time: TimeInterval, millis: Double, memoryMB: Double) {
        refreshHint(force: false)
        let reading = classifier.classify(items, hint: engine.hint, at: time)
        commit(engine.process(reading: reading))
        recorder.setContext(inReels: engine.isShortVideo, app: engine.contextApp ?? engine.hint, now: Date())
        diagnostics.ocrRuns += 1
        diagnostics.lastOCRMillis = millis
        diagnostics.availableMemoryMB = memoryMB
    }

    private func scheduleOCRIfNeeded(at time: TimeInterval) {
        guard engine.wantsOCR(at: time) else { return }
        engine.markOCRScheduled(at: time)
        gate.withLockUnchecked { $0.ocrWanted = true }
    }

    private func commit(_ decisions: [CountDecision]) {
        guard !decisions.isEmpty else { return }
        recorder.apply(decisions, now: Date())
        for decision in decisions {
            switch decision {
            case .counted: diagnostics.counted += 1
            case .skippedAd: diagnostics.adsSkipped += 1
            case .skippedRewatch: diagnostics.rewatchesSkipped += 1
            }
        }
        guard diagnosticsEnabled else { return }
        let stamp = DetectionPipeline.timeFormatter.string(from: Date())
        for decision in decisions {
            let line: String
            switch decision {
            case .counted(let app, let reason): line = "\(stamp) ✅ counted · \(app.shortLabel) · \(reason.rawValue)"
            case .skippedAd(let app): line = "\(stamp) 🥷 ad skipped · \(app.shortLabel)"
            case .skippedRewatch(let app): line = "\(stamp) 🔁 rewatch · \(app.shortLabel)"
            }
            diagnostics.recentEvents.insert(line, at: 0)
        }
        if diagnostics.recentEvents.count > 25 { diagnostics.recentEvents.removeLast(diagnostics.recentEvents.count - 25) }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: analysisQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.onTick() }
        timer.resume()
        self.timer = timer
    }

    private func onTick() {
        let time = ProcessInfo.processInfo.systemUptime
        let now = Date()
        commit(engine.tick(at: time, gridHeight: gridHeight))

        let lastFrame = gate.withLockUnchecked { $0.lastFrame }
        let screenActive = time - lastFrame < 3
        let inReels = engine.isShortVideo && screenActive
        if inReels {
            recorder.addWatch(seconds: 0.5, app: engine.contextApp ?? engine.hint ?? .other, now: now)
        }
        recorder.setContext(inReels: inReels, app: engine.contextApp ?? engine.hint, now: now)
        recorder.tick(now: now)

        scheduleOCRIfNeeded(at: time)
        if time - lastHintRefresh > 15 { refreshHint(force: true) }
        persistFingerprints(force: false)
        writeDiagnosticsIfNeeded(at: time)
    }

    // MARK: Hints, settings, persistence

    private func refreshHint(force: Bool) {
        let time = ProcessInfo.processInfo.systemUptime
        guard force || time - lastHintRefresh > 5 else { return }
        lastHintRefresh = time
        let hint = store.hint
        engine.hint = (hint?.isForeground() == true) ? hint?.app : nil
    }

    private func reloadSettings() {
        engine.strictMode = settings.strictPrivacyMode
        diagnosticsEnabled = settings.diagnosticsEnabled
        let latest = DetectorConfig.load()
        if latest != config {
            config = latest
            engine.update(config: latest)
            classifier = ScreenClassifier(config: latest)
        }
        recorder.reloadSettings()
    }

    private func observeDarwin() {
        let center = DarwinCenter.shared
        observers.append(center.observe(DarwinName.settingsChanged) { [weak self] in
            self?.analysisQueue.async { self?.reloadSettings() }
        })
        observers.append(center.observe(DarwinName.hintChanged) { [weak self] in
            self?.analysisQueue.async { self?.refreshHint(force: true) }
        })
        observers.append(center.observe(DarwinName.dataReset) { [weak self] in
            self?.analysisQueue.async {
                guard let self else { return }
                self.recorder.resetToday(now: Date())
                self.engine.resetForNewDay()
                self.fingerprints.removeAll()
                self.fingerprintsDirty = true
            }
        })
        observers.append(center.observe(DarwinName.stopRequested) { [weak self] in
            DispatchQueue.main.async { self?.onStopRequested?() }
        })
    }

    private func loadFingerprints() {
        if let saved = store.read(SeenFingerprints.self, from: .seenReels), saved.day == DayKey.today() {
            fingerprints = Set(saved.hashes)
        } else {
            fingerprints = []
        }
        engine.restoreFingerprints(fingerprints)
    }

    private func persistFingerprints(force: Bool) {
        let time = ProcessInfo.processInfo.systemUptime
        guard fingerprintsDirty, force || time - lastFingerprintWrite > 20 else { return }
        store.write(SeenFingerprints(day: DayKey.today(), hashes: Array(fingerprints.prefix(1000))), to: .seenReels)
        fingerprintsDirty = false
        lastFingerprintWrite = time
    }

    private func writeDiagnosticsIfNeeded(at time: TimeInterval) {
        guard diagnosticsEnabled, time - lastDiagnosticsWrite >= 1.5 else { return }
        lastDiagnosticsWrite = time
        diagnostics.updatedAt = Date()
        diagnostics.framesProcessed = framesProcessed
        diagnostics.swipesForward = engine.swipesForward
        diagnostics.swipesBackward = engine.swipesBackward
        diagnostics.context = "\(engine.context)"
        diagnostics.contextApp = engine.contextApp?.rawValue
        diagnostics.lastScore = engine.lastReadingScore
        diagnostics.lastDecision = engine.lastDecisionNote
        store.write(diagnostics, to: .diagnostics)
    }

    // MARK: Helpers

    /// Salted, truncated SHA-256 — reel identities are never stored in clear.
    static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
