import AVFoundation
import CoreMedia

/// Lean webcam pipeline: deliver pixel buffers to a closure on a background
/// queue. POC variant of the main app's CameraManager — no frame-rate gate
/// (latency over efficiency for a tracking demo), no interruption observers.
final class CameraManager: NSObject {

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.gazeoverlaypoc.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.gazeoverlaypoc.camera.video", qos: .userInitiated)
    private var configured = false

    var onFrame: ((CVPixelBuffer) -> Void)?

    func startIfPermitted() {
        sessionQueue.async { [weak self] in self?.configureAndStart() }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureAndStart() {
        if session.isRunning { return }

        if !configured {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                return
            }

            session.beginConfiguration()
            // 640x480 keeps Vision fast (~5–10ms per request on Apple Silicon)
            // while still giving the face detector enough pixels for landmarks.
            if session.canSetSessionPreset(.vga640x480) {
                session.sessionPreset = .vga640x480
            }
            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            session.commitConfiguration()

            configured = true
        }

        session.startRunning()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
