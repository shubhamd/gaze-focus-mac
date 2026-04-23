import AVFoundation
import XCTest
@testable import GazeFocus

private struct DeniedAuth: CameraAuthorizationProviding {
    var isAuthorized: Bool { false }
}

private struct GrantedAuth: CameraAuthorizationProviding {
    var isAuthorized: Bool { true }
}

final class CameraManagerTests: XCTestCase {

    // AC-CAM-01: must not start the session without camera permission.
    func testDeniedAuthDoesNotStartSession() {
        let manager = CameraManager(auth: DeniedAuth())
        manager.startIfPermitted()

        // startIfPermitted returns immediately when denied (no dispatch),
        // so isRunning must be false synchronously.
        XCTAssertFalse(manager.isRunning)
    }

    // AC-CAM-02: effective frame delivery rate stays at or below the target
    // over a 2-second window. Skips on hosts without a camera.
    func testEffectiveFrameRateIsCapped() throws {
        guard AVCaptureDevice.default(for: .video) != nil else {
            throw XCTSkip("No camera available in this environment")
        }

        let manager = CameraManager(auth: GrantedAuth())
        let frameCount = Atomic<Int>(0)
        manager.onFrame = { _ in frameCount.increment() }
        manager.startIfPermitted()

        // Wait for session to start, up to 5s.
        let started = expectation(description: "session running")
        let deadline = Date().addingTimeInterval(5)
        DispatchQueue.global().async {
            while !manager.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            started.fulfill()
        }
        wait(for: [started], timeout: 6)
        defer { manager.stop() }

        guard manager.isRunning else {
            throw XCTSkip("Camera did not start within 5s — likely blocked by system permission prompt.")
        }

        // Discard any frames emitted during warm-up.
        Thread.sleep(forTimeInterval: 0.5)
        frameCount.reset()

        // Count frames over 2 seconds.
        Thread.sleep(forTimeInterval: 2.0)
        let count = frameCount.value

        #if DEBUG
        print("CameraManager diagnostics:\n\(manager.debugDiagnostics)")
        print("Frames delivered in 2s: \(count)")
        #endif

        // 15fps × 2s = 30 frames expected. Allow +2 for jitter / slack window.
        XCTAssertLessThanOrEqual(count, 32,
            "expected ≤ 32 frames in 2s (15fps cap + tolerance), got \(count)")
        // Sanity: we should actually be receiving frames.
        XCTAssertGreaterThan(count, 10,
            "expected > 10 frames in 2s — camera may not be delivering")
    }
}

/// Minimal thread-safe counter for test use.
private final class Atomic<T> {
    private var _value: T
    private let lock = NSLock()

    init(_ initial: T) { _value = initial }

    var value: T {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
}

private extension Atomic where T == Int {
    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
    func reset() {
        lock.lock(); defer { lock.unlock() }
        _value = 0
    }
}
