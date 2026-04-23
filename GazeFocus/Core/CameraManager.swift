import AVFoundation
import CoreMedia
import QuartzCore

protocol CameraAuthorizationProviding {
    var isAuthorized: Bool { get }
}

struct SystemCameraAuthorization: CameraAuthorizationProviding {
    var isAuthorized: Bool { PermissionsManager.hasCameraPermission }
}

enum CameraInterruptionState {
    case interrupted
    case resumed
}

final class CameraManager: NSObject {
    static let targetFrameRate: Int32 = 15

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.gazefocus.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.gazefocus.camera.video", qos: .userInitiated)
    private let auth: CameraAuthorizationProviding
    private var currentDevice: AVCaptureDevice?
    private var didConfigure = false

    // Software frame-rate gate. We attempt a hardware cap first, but some
    // macOS builds silently refuse sub-30fps on the built-in FaceTime camera,
    // so we also enforce the rate here to satisfy AC-CAM-02 on every host.
    private let minFrameInterval: CFTimeInterval = 1.0 / Double(targetFrameRate)
    private var lastEmittedFrameTime: CFTimeInterval = 0

    var onFrame: ((CVPixelBuffer) -> Void)?
    var onInterruption: ((CameraInterruptionState) -> Void)?

    init(auth: CameraAuthorizationProviding = SystemCameraAuthorization()) {
        self.auth = auth
        super.init()
        registerInterruptionObservers()
    }

    var isRunning: Bool { session.isRunning }

    var configuredFrameDurationSeconds: Double? {
        guard let device = currentDevice else { return nil }
        let t = device.activeVideoMinFrameDuration
        guard t.isValid, t.timescale != 0 else { return nil }
        return Double(t.value) / Double(t.timescale)
    }

    #if DEBUG
    /// Human-readable diagnostics about the active capture state.
    /// Used by tests and the M4 debug overlay.
    var debugDiagnostics: String {
        guard let device = currentDevice else { return "no device" }
        let af = device.activeFormat
        let dims = CMVideoFormatDescriptionGetDimensions(af.formatDescription)
        let ranges = af.videoSupportedFrameRateRanges
            .map { "[\($0.minFrameRate)-\($0.maxFrameRate) minDur=\($0.minFrameDuration.seconds)s maxDur=\($0.maxFrameDuration.seconds)s]" }
            .joined(separator: ",")
        let minT = device.activeVideoMinFrameDuration
        let maxT = device.activeVideoMaxFrameDuration
        return """
        device: \(device.localizedName) (\(device.modelID))
        uniqueID: \(device.uniqueID)
        activeFormat: \(dims.width)x\(dims.height) ranges=\(ranges)
        minFrameDuration: \(minT.seconds)s (\(minT.value)/\(minT.timescale))
        maxFrameDuration: \(maxT.seconds)s (\(maxT.value)/\(maxT.timescale))
        isRunning: \(session.isRunning)
        """
    }
    #endif

    func startIfPermitted() {
        guard auth.isAuthorized else { return }
        sessionQueue.async { [weak self] in
            self?.configureAndStart()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureAndStart() {
        if session.isRunning { return }

        if !didConfigure {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                return
            }

            session.beginConfiguration()

            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            currentDevice = device

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            session.commitConfiguration()

            // Device-level config (activeFormat + frame duration) runs OUTSIDE
            // session.beginConfiguration so the active format change takes effect
            // before we clamp the frame duration against it.
            applyFormatAndFrameRate(on: device)
            didConfigure = true
        }

        session.startRunning()
    }

    /// Picks the smallest-resolution format that supports the target fps and
    /// pins the device to that format at exactly targetFrameRate. `.low` session
    /// preset is deliberately not used — it tends to pick a 30fps-only format
    /// whose frame-duration range silently clamps our 15fps request.
    private func applyFormatAndFrameRate(on device: AVCaptureDevice) {
        let targetFps = Double(Self.targetFrameRate)
        let format = smallestFormat(supporting: targetFps, in: device.formats)
        do {
            try device.lockForConfiguration()
            if let format {
                device.activeFormat = format
            }
            let frameTime = CMTimeMake(value: 1, timescale: Self.targetFrameRate)
            // Order matters: AVCaptureDevice enforces min ≤ max on every setter,
            // so we widen max first. Otherwise setting min to a value greater
            // than the existing max is silently rejected.
            device.activeVideoMaxFrameDuration = frameTime
            device.activeVideoMinFrameDuration = frameTime
            device.unlockForConfiguration()
        } catch {
            // Non-fatal: device keeps its default active format and rate.
        }
    }

    private func smallestFormat(
        supporting fps: Double,
        in formats: [AVCaptureDevice.Format]
    ) -> AVCaptureDevice.Format? {
        let candidates = formats.filter { format in
            format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= fps && fps <= $0.maxFrameRate
            }
        }
        return candidates.min { lhs, rhs in
            let l = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let r = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(l.width) * Int(l.height) < Int(r.width) * Int(r.height)
        }
    }

    private func registerInterruptionObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(wasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        nc.addObserver(
            self,
            selector: #selector(interruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
    }

    @objc private func wasInterrupted(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.onInterruption?(.interrupted)
        }
    }

    @objc private func interruptionEnded(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.onInterruption?(.resumed)
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let now = CACurrentMediaTime()
        // Subtract a small slack so we don't drop the Nth frame when it
        // arrives a hair early (jitter from the camera clock).
        if now - lastEmittedFrameTime < minFrameInterval - 0.005 {
            return
        }
        lastEmittedFrameTime = now

        onFrame?(pixelBuffer)
    }
}
