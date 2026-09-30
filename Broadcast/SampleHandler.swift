import ReplayKit

/// Entry point of the Broadcast Upload Extension. iOS runs this process while
/// the user's screen broadcast is active (started from Doomscore's arm screen
/// or Control Center → Screen Recording → Doomscore). Frames never leave the
/// device: they're reduced to motion + text signals in memory and dropped.
final class SampleHandler: RPBroadcastSampleHandler {
    private lazy var pipeline: DetectionPipeline = {
        let pipeline = DetectionPipeline()
        pipeline.onStopRequested = { [weak self] in
            let error = NSError(
                domain: "app.doomscore",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Counting paused ✌️ Open Doomscore to start again."]
            )
            self?.finishBroadcastWithError(error)
        }
        return pipeline
    }()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        pipeline.start()
    }

    override func broadcastPaused() {
        pipeline.pause()
    }

    override func broadcastResumed() {
        pipeline.resume()
    }

    override func broadcastFinished() {
        pipeline.finish()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Audio is ignored entirely.
        guard sampleBufferType == .video else { return }
        pipeline.ingest(sampleBuffer)
    }
}
