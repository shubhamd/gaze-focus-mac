import Vision
import CoreGraphics
import CoreVideo

/// Eye-relative gaze feature, averaged across both eyes. Output is *roughly*
/// head-pose invariant for small head motions — large head rotations still
/// shift the feature and are out of POC scope.
struct GazeFeature {
    /// Pupil offset from eye-bbox center, normalized by eye width. Both axes.
    let g: CGPoint
    let confidence: Float
}

/// Pipeline stage 2: pixel buffer → 2D gaze feature via Vision face landmarks.
///
/// The main app uses only `leftPupil.normalizedPoints.first.x`. That collapses
/// gaze to a single dimension and is dominated by head pose. Here we compute
/// pupil offset *relative to its own eye-corner span* — which is what changes
/// when the eye actually rotates — and average left and right to suppress
/// per-eye noise.
final class GazeEstimator {
    static let confidenceThreshold: Float = 0.3

    private let handler = VNSequenceRequestHandler()

    func estimate(in pixelBuffer: CVPixelBuffer,
                  completion: @escaping (GazeFeature?) -> Void) {
        let request = VNDetectFaceLandmarksRequest { req, _ in
            guard let obs = req.results?.first as? VNFaceObservation,
                  obs.confidence >= Self.confidenceThreshold,
                  let landmarks = obs.landmarks,
                  let g = Self.feature(from: landmarks) else {
                completion(nil)
                return
            }
            completion(GazeFeature(g: g, confidence: obs.confidence))
        }
        do {
            try handler.perform([request], on: pixelBuffer)
        } catch {
            completion(nil)
        }
    }

    /// Pure function — eligible for unit testing if/when this graduates into
    /// the main app. Returns nil for degenerate eye geometry (closed eye,
    /// missing landmarks).
    static func feature(from landmarks: VNFaceLandmarks2D) -> CGPoint? {
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let lp = landmarks.leftPupil?.normalizedPoints.first,
              let rp = landmarks.rightPupil?.normalizedPoints.first,
              let left = eyeRelative(eye: leftEye, pupil: lp),
              let right = eyeRelative(eye: rightEye, pupil: rp) else {
            return nil
        }
        return CGPoint(
            x: (left.x + right.x) / 2,
            y: (left.y + right.y) / 2
        )
    }

    private static func eyeRelative(eye: VNFaceLandmarkRegion2D,
                                    pupil: CGPoint) -> CGPoint? {
        let pts = eye.normalizedPoints
        guard !pts.isEmpty else { return nil }

        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for p in pts {
            let x = CGFloat(p.x), y = CGFloat(p.y)
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        let width = maxX - minX
        // Eye height shrinks with blink; using width as the divisor for both
        // axes keeps the unit consistent and the vertical signal usable.
        guard width > 0.001 else { return nil }

        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        return CGPoint(
            x: (CGFloat(pupil.x) - cx) / width,
            y: (CGFloat(pupil.y) - cy) / width
        )
    }
}
