import AppKit

/// Single owner of the runtime pipeline: camera → gaze detection → smoothing
/// → dwell classifier → cursor warp. Vision runs off-main (inside GazeDetector
/// via the camera background queue); smoothing, dwell, and warp all run on
/// the main thread so they share a consistent, serialized view of state.
final class TrackingCoordinator {

    /// Pipeline mode. .tracking runs the full smoother → dwell → cursor warp
    /// path; .calibrating redirects every raw gaze sample to the provided
    /// closure and suppresses dwell/warp.
    enum Mode {
        case tracking
        case calibrating(onSample: (CGFloat) -> Void)
    }

    private let cameraManager: CameraManager
    private let gazeDetector: GazeDetector
    private let screenProvider: ScreenProvider
    private let dwell: DwellController
    private var smoother = GazeSmoother()

    /// Calibration profile loaded from UserDefaults. Updated after a
    /// successful calibration run; nil means "use the naive midpoint split."
    var profile: CalibrationProfile? = CalibrationProfile.load()

    var mode: Mode = .tracking

    private(set) var isTracking = false

    /// Fires on the main thread after every gaze frame, regardless of dwell.
    /// Used by the diagnostics overlay and DEBUG logging.
    var onGazeUpdate: ((GazeResult?) -> Void)?

    /// Fires on the main thread when the dwell classifier commits a switch.
    /// Downstream of cursor warp (which has already happened by the time
    /// this fires).
    var onScreenSwitch: ((Int) -> Void)?

    var onInterruption: ((CameraInterruptionState) -> Void)?

    init(cameraManager: CameraManager = CameraManager(),
         gazeDetector: GazeDetector = GazeDetector(),
         screenProvider: ScreenProvider = SystemScreenProvider(),
         dwell: DwellController = DwellController()) {
        self.cameraManager = cameraManager
        self.gazeDetector = gazeDetector
        self.screenProvider = screenProvider
        self.dwell = dwell
        wire()
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true
        cameraManager.startIfPermitted()
    }

    func stop() {
        guard isTracking else { return }
        isTracking = false
        cameraManager.stop()
    }

    // MARK: - Wiring

    private func wire() {
        cameraManager.onFrame = { [weak self] buffer in
            self?.handleFrame(buffer)
        }
        cameraManager.onInterruption = { [weak self] state in
            DispatchQueue.main.async { self?.onInterruption?(state) }
        }
        dwell.onScreenSwitch = { [weak self] index in
            self?.handleScreenSwitch(index)
        }
    }

    private func handleFrame(_ buffer: CVPixelBuffer) {
        let screenCount = max(1, screenProvider.displays.count)
        gazeDetector.detect(in: buffer, screenCount: screenCount) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleGazeResult(result, screenCount: screenCount)
            }
        }
    }

    private func handleGazeResult(_ result: GazeResult?, screenCount: Int) {
        onGazeUpdate?(result)
        guard let r = result else { return }

        switch mode {
        case .tracking:
            let smoothedX = smoother.smooth(r.rawGazeX)
            let idx = CalibrationProfile.classifyScreen(
                smoothedX: smoothedX,
                screenCount: screenCount,
                profile: profile
            )
            dwell.update(gazeScreenIndex: idx)

        case .calibrating(let onSample):
            onSample(r.rawGazeX)
        }
    }

    private func handleScreenSwitch(_ index: Int) {
        let displays = CursorEngine.sorted(screenProvider.displays)
        guard index >= 0, index < displays.count else { return }
        CursorEngine.warpCursor(to: displays[index])
        onScreenSwitch?(index)
    }
}
