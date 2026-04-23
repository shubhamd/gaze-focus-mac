import AppKit
import Foundation

/// Orchestrates the 5-dot calibration flow:
///  1. Flips the tracking coordinator into .calibrating mode so raw gaze
///     samples flow to us instead of driving cursor warps.
///  2. Presents the overlay and advances through 5 dots.
///  3. For each dot, collects ~30 gaze-X samples and stores the median.
///  4. Builds a CalibrationProfile (2-screen MVP: boundary = dot 3 median),
///     persists it, and hands it back to TrackingCoordinator.
final class CalibrationManager {

    private unowned let coordinator: TrackingCoordinator
    private let viewController = CalibrationViewController()
    private var perDotSamples: [[CGFloat]] = []
    private var advanceTimer: Timer?
    private var isRunning = false

    var onCompleted: ((CalibrationProfile) -> Void)?
    var onCancelled: (() -> Void)?

    init(coordinator: TrackingCoordinator) {
        self.coordinator = coordinator
        viewController.onDotAppeared = { [weak self] index in
            self?.startCollectingForDot(index)
        }
        viewController.onCancel = { [weak self] in
            self?.handleCancel()
        }
        viewController.onFinished = { [weak self] in
            self?.handleFinished()
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        perDotSamples = Array(repeating: [], count: CalibrationViewController.normalizedDotPositions.count)

        coordinator.mode = .calibrating(onSample: { [weak self] rawX in
            self?.recordSample(rawX)
        })

        viewController.present()
        // Small delay before first dot so the overlay finishes drawing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.viewController.advance()
        }
    }

    // MARK: - Sample flow

    private func recordSample(_ rawX: CGFloat) {
        let idx = currentDotIndex()
        guard idx >= 0, idx < perDotSamples.count else { return }
        perDotSamples[idx].append(rawX)
    }

    private var _currentDotIndex: Int = -1
    private func currentDotIndex() -> Int { _currentDotIndex }

    private func startCollectingForDot(_ index: Int) {
        _currentDotIndex = index
        advanceTimer?.invalidate()
        advanceTimer = Timer.scheduledTimer(
            withTimeInterval: CalibrationViewController.dotHoldDuration,
            repeats: false
        ) { [weak self] _ in
            self?.viewController.advance()
        }
    }

    // MARK: - Completion paths

    private func handleFinished() {
        defer { teardown() }

        // Need a median for at least dot 3 (the center) to build a 2-screen boundary.
        guard let centerMedian = median(of: perDotSamples[safe: 2] ?? []) else {
            onCancelled?()
            return
        }

        let profile = CalibrationProfile(
            screenBoundaryGazeX: [centerMedian],
            createdAt: Date(),
            monitorConfig: CalibrationProfile.currentMonitorConfigHash()
        )
        profile.save()
        coordinator.profile = profile
        onCompleted?(profile)
    }

    private func handleCancel() {
        teardown()
        onCancelled?()
    }

    private func teardown() {
        advanceTimer?.invalidate()
        advanceTimer = nil
        viewController.dismiss()
        coordinator.mode = .tracking
        isRunning = false
    }

    // MARK: - Math

    private func median(of values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let n = sorted.count
        if n % 2 == 0 {
            return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        } else {
            return sorted[n / 2]
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
