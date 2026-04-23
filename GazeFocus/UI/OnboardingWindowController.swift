import AppKit

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    static let defaultsKey = "hasCompletedOnboarding"

    private let rootVC = OnboardingViewController()
    private weak var trackingCoordinator: TrackingCoordinator?
    private weak var calibrationManager: CalibrationManager?

    var onFinished: (() -> Void)?

    init(trackingCoordinator: TrackingCoordinator, calibrationManager: CalibrationManager) {
        self.trackingCoordinator = trackingCoordinator
        self.calibrationManager = calibrationManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to GazeFocus"
        window.isReleasedWhenClosed = false
        window.contentViewController = rootVC
        window.center()
        super.init(window: window)

        window.delegate = self

        rootVC.onStartCalibration = { [weak self] in
            self?.startCalibrationFromOnboarding()
        }

        calibrationManager.onCompleted = { [weak self] _ in
            self?.finishOnboarding()
        }
        calibrationManager.onCancelled = { [weak self] in
            // Return the user to the onboarding window so they can retry.
            self?.showWindow(nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    // MARK: - Flow

    private func startCalibrationFromOnboarding() {
        guard let calibrationManager else { return }
        window?.orderOut(nil)
        calibrationManager.start()
    }

    private func finishOnboarding() {
        Self.markCompleted()
        window?.close()
        onFinished?()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Allow close only after onboarding is complete. Before that, the
        // user must finish the flow (they can still Quit from the menu bar).
        return Self.hasCompleted
    }
}
