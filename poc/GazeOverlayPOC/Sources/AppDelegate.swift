import AppKit
import AVFoundation

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let camera = CameraManager()
    private let estimator = GazeEstimator()
    private var smoother = GazeSmoother2D()
    private var mapper: GazeMapper?
    private let overlay = OverlayWindow()
    private var calibrator: Calibrator?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        wireCamera()
        requestCameraThenStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        camera.stop()
        overlay.hide()
        calibrator?.dismiss()
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "eye",
                accessibilityDescription: "Gaze Overlay POC"
            )
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Recalibrate", action: #selector(recalibrate), keyEquivalent: "r")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func recalibrate() {
        overlay.hide()
        mapper = nil
        smoother = GazeSmoother2D()
        beginCalibration()
    }

    // MARK: - Camera + permissions

    private func requestCameraThenStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera.startIfPermitted()
            beginCalibration()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.camera.startIfPermitted()
                        self.beginCalibration()
                    } else {
                        self.cameraDeniedAlert()
                    }
                }
            }
        case .denied, .restricted:
            cameraDeniedAlert()
        @unknown default:
            cameraDeniedAlert()
        }
    }

    private func cameraDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Camera access required"
        alert.informativeText = "Grant camera access in System Settings → Privacy & Security → Camera, then relaunch."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func wireCamera() {
        camera.onFrame = { [weak self] buffer in
            self?.estimator.estimate(in: buffer) { feature in
                DispatchQueue.main.async {
                    self?.handle(feature: feature)
                }
            }
        }
    }

    // MARK: - Frame routing

    private func handle(feature: GazeFeature?) {
        guard let feature else { return }

        if let calibrator {
            calibrator.record(gaze: feature.g)
            return
        }

        guard let mapper else { return }
        let raw = mapper.map(feature.g.x, feature.g.y)
        let smoothed = smoother.smooth(raw)
        overlay.update(point: smoothed)
    }

    // MARK: - Calibration

    private func beginCalibration() {
        let c = Calibrator()
        c.onCompleted = { [weak self] samples in
            guard let self else { return }
            self.calibrator = nil
            if let fitted = GazeMapper.fit(samples: samples) {
                self.mapper = fitted
                self.smoother = GazeSmoother2D()
                self.overlay.show()
            } else {
                self.calibrationFailedAlert()
            }
        }
        c.onCancelled = { [weak self] in
            self?.calibrator = nil
            // No mapper, no overlay — user can re-trigger via the menu.
        }
        calibrator = c
        c.present()
    }

    private func calibrationFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Calibration failed"
        alert.informativeText = "Could not fit a gaze model — calibration points may have been collinear or too noisy. Try again, holding your head steady."
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            beginCalibration()
        }
    }
}
