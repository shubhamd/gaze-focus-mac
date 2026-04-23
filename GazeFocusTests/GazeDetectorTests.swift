import CoreVideo
import XCTest
@testable import GazeFocus

final class GazeDetectorTests: XCTestCase {

    // AC-GAZE-01: low-confidence observation yields nil.
    func testClassifyRejectsLowConfidence() {
        let below = GazeDetector.classify(
            confidence: GazeDetector.confidenceThreshold - 0.01,
            pupilX: 0.5,
            screenCount: 2
        )
        XCTAssertNil(below)
    }

    // AC-GAZE-01 boundary: exactly at threshold is accepted.
    func testClassifyAcceptsAtThreshold() {
        let result = GazeDetector.classify(
            confidence: GazeDetector.confidenceThreshold,
            pupilX: 0.5,
            screenCount: 2
        )
        XCTAssertNotNil(result)
    }

    // AC-GAZE-02: missing pupil point yields nil.
    func testClassifyReturnsNilWhenPupilMissing() {
        let result = GazeDetector.classify(
            confidence: 0.9,
            pupilX: nil,
            screenCount: 2
        )
        XCTAssertNil(result)
    }

    func testClassifyScreenCountZero() {
        XCTAssertNil(GazeDetector.classify(
            confidence: 0.9,
            pupilX: 0.5,
            screenCount: 0
        ))
    }

    func testClassifySingleScreenAlwaysIndexZero() {
        for x in stride(from: 0.0, through: 1.0, by: 0.1) {
            let r = GazeDetector.classify(confidence: 0.9, pupilX: CGFloat(x), screenCount: 1)
            XCTAssertEqual(r?.screenIndex, 0)
        }
    }

    func testClassifyTwoScreensPartition() {
        let left = GazeDetector.classify(confidence: 0.9, pupilX: 0.25, screenCount: 2)
        let right = GazeDetector.classify(confidence: 0.9, pupilX: 0.75, screenCount: 2)
        XCTAssertEqual(left?.screenIndex, 0)
        XCTAssertEqual(right?.screenIndex, 1)
    }

    func testClassifyClampsOutOfRangePupilX() {
        let low = GazeDetector.classify(confidence: 0.9, pupilX: -0.5, screenCount: 2)
        let high = GazeDetector.classify(confidence: 0.9, pupilX: 1.5, screenCount: 2)
        XCTAssertEqual(low?.rawGazeX, 0)
        XCTAssertEqual(low?.screenIndex, 0)
        XCTAssertEqual(high?.rawGazeX, 1)
        XCTAssertEqual(high?.screenIndex, 1)
    }

    // AC-GAZE-02 (integration): Vision on a blank gray frame detects no face.
    func testDetectOnBlankBufferReturnsNil() {
        let buffer = makeBlankPixelBuffer(width: 320, height: 240, grayValue: 128)
        let detector = GazeDetector()

        let expectation = expectation(description: "detection completes")
        var observed: GazeResult??
        detector.detect(in: buffer, screenCount: 2) { result in
            observed = .some(result)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        XCTAssertNotNil(observed, "completion must fire")
        XCTAssertNil(observed ?? nil, "blank frame must yield no gaze result")
    }

    // MARK: - Helpers

    private func makeBlankPixelBuffer(width: Int, height: Int, grayValue: UInt8) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        precondition(status == kCVReturnSuccess, "pixel buffer creation failed")
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
            let rowPtr = base.advanced(by: row * bpr).assumingMemoryBound(to: UInt8.self)
            for col in 0..<width {
                rowPtr[col * 4 + 0] = grayValue  // B
                rowPtr[col * 4 + 1] = grayValue  // G
                rowPtr[col * 4 + 2] = grayValue  // R
                rowPtr[col * 4 + 3] = 255        // A
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
