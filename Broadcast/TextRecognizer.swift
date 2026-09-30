import CoreGraphics
import CoreVideo
import Vision

/// On-device text recognition (Apple Vision, `.fast` path). Results are used
/// in memory to classify the screen and are discarded immediately.
final class TextRecognizer {
    private let request: VNRecognizeTextRequest
    private let minimumConfidence: Float

    init(config: DetectorConfig.OCR) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = Float(config.minimumTextHeight)
        if !config.languages.isEmpty { request.recognitionLanguages = config.languages }
        self.request = request
        self.minimumConfidence = config.minimumConfidence
    }

    func recognize(in pixelBuffer: CVPixelBuffer) -> [TextItem] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let observations = request.results else { return [] }
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minimumConfidence else { return nil }
            let box = observation.boundingBox // normalised, origin bottom-left
            return TextItem(
                text: candidate.string,
                box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
                confidence: candidate.confidence
            )
        }
    }
}
