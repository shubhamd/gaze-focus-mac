import Vision
import CoreGraphics

struct GazeResult {
    let screenIndex: Int
    let confidence: Float
    let rawGazeX: CGFloat
}

final class GazeDetector {
    static let confidenceThreshold: Float = 0.7

    private let requestHandler = VNSequenceRequestHandler()

    /// Runs Vision face-landmark detection on a frame and yields a GazeResult
    /// or nil. Completion fires on the caller's thread (typically the camera
    /// background queue). Nil is returned when there is no face, when the
    /// observation's confidence is below threshold, or when no pupil point is
    /// available.
    func detect(in pixelBuffer: CVPixelBuffer,
                screenCount: Int,
                completion: @escaping (GazeResult?) -> Void) {
        let request = VNDetectFaceLandmarksRequest { req, _ in
            guard let obs = req.results?.first as? VNFaceObservation else {
                completion(nil)
                return
            }
            let pupilX = obs.landmarks?.leftPupil?.normalizedPoints.first?.x
            completion(Self.classify(
                confidence: obs.confidence,
                pupilX: pupilX.map { CGFloat($0) },
                screenCount: screenCount
            ))
        }

        do {
            try requestHandler.perform([request], on: pixelBuffer)
        } catch {
            completion(nil)
        }
    }

    /// Pure classifier — unit-tested directly (AC-GAZE-01, AC-GAZE-02).
    static func classify(confidence: Float,
                         pupilX: CGFloat?,
                         screenCount: Int) -> GazeResult? {
        guard confidence >= confidenceThreshold else { return nil }
        guard let rawX = pupilX else { return nil }
        guard screenCount >= 1 else { return nil }
        let clamped = max(0, min(1, rawX))
        let screenIndex = min(Int(clamped * CGFloat(screenCount)), screenCount - 1)
        return GazeResult(
            screenIndex: screenIndex,
            confidence: confidence,
            rawGazeX: clamped
        )
    }
}
