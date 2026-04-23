import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var trackingCoordinator: TrackingCoordinator!
    private var calibrationManager: CalibrationManager!
    private var onboardingController: OnboardingWindowController?
    private let diagnosticsOverlay = DiagnosticsOverlay()
    private var globalKeyMonitor: Any?
    private var permissionsTimer: Timer?
    private var lastKnownPermissions: (camera: Bool, accessibility: Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController()
        menuBar.onTogglePause = { [weak self] in self?.toggleTrackingPause() }
        menuBar.onRecalibrate = { [weak self] in self?.openRecalibration() }

        trackingCoordinator = TrackingCoordinator()
        calibrationManager = CalibrationManager(coordinator: trackingCoordinator)
        trackingCoordinator.onGazeUpdate = { [weak self] result in
            guard let r = result else { return }
            self?.diagnosticsOverlay.update(normalizedX: r.rawGazeX)
            #if DEBUG
            if DiagnosticsOverlay.isEnabled {
                print(String(format: "gaze screen=%d x=%.3f conf=%.2f",
                             r.screenIndex, Double(r.rawGazeX), Double(r.confidence)))
            }
            #endif
        }
        trackingCoordinator.onInterruption = { [weak self] state in
            switch state {
            case .interrupted:
                self?.applyState(.permissionMissing)
            case .resumed:
                self?.lastKnownPermissions = nil
                self?.syncMenuBarWithPermissions()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        installGlobalPauseShortcut()
        startPermissionsPolling()
        syncDisplayCount()

        if !OnboardingWindowController.hasCompleted {
            presentOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        permissionsTimer?.invalidate()
        permissionsTimer = nil
        NotificationCenter.default.removeObserver(self)
        trackingCoordinator?.stop()
        diagnosticsOverlay.hide()
    }

    private func presentOnboarding() {
        let controller = OnboardingWindowController(
            trackingCoordinator: trackingCoordinator,
            calibrationManager: calibrationManager
        )
        controller.onFinished = { [weak self] in
            self?.onboardingController = nil
            self?.lastKnownPermissions = nil
            self?.syncMenuBarWithPermissions()
        }
        onboardingController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installGlobalPauseShortcut() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers == [.command, .option],
                  event.charactersIgnoringModifiers?.lowercased() == "g" else { return }
            self?.toggleTrackingPause()
        }
    }

    private func toggleTrackingPause() {
        switch menuBar.state {
        case .active:
            applyState(.paused)
        case .paused:
            applyState(.active)
        case .permissionMissing, .singleDisplay:
            break
        }
    }

    /// Single entry point for every state transition. Keeps menu bar icon,
    /// tracking pipeline, and diagnostics overlay in sync.
    private func applyState(_ newState: TrackingState) {
        let previous = menuBar.state
        menuBar.setState(newState)

        if newState == .active && previous != .active {
            diagnosticsOverlay.showIfEnabled()
            trackingCoordinator.start()
        } else if newState != .active && previous == .active {
            trackingCoordinator.stop()
            diagnosticsOverlay.hide()
        }
    }

    // MARK: - Permissions

    private func startPermissionsPolling() {
        syncMenuBarWithPermissions()
        permissionsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.syncMenuBarWithPermissions()
        }
    }

    private func syncMenuBarWithPermissions() {
        // If we're locked into .singleDisplay, the screen-change observer
        // is the only thing that can clear it.
        if menuBar.state == .singleDisplay { return }

        let current = (
            camera: PermissionsManager.hasCameraPermission,
            accessibility: PermissionsManager.hasAccessibility
        )
        if let last = lastKnownPermissions, last == current { return }
        lastKnownPermissions = current

        let satisfied = current.camera && current.accessibility
        switch (satisfied, menuBar.state) {
        case (false, _):
            applyState(.permissionMissing)
        case (true, .permissionMissing):
            applyState(.active)
        case (true, _):
            break
        }
    }

    // MARK: - Display count

    @objc private func screenParametersChanged() {
        syncDisplayCount()
    }

    private func syncDisplayCount() {
        let count = NSScreen.screens.count
        if count < 2 {
            applyState(.singleDisplay)
        } else if menuBar.state == .singleDisplay {
            // Drop the lock and let the permissions sync bring us back to .active.
            menuBar.setState(.permissionMissing)
            lastKnownPermissions = nil
            syncMenuBarWithPermissions()
        }
    }

    // MARK: - Menu actions

    private func openRecalibration() {
        calibrationManager.start()
    }
}
