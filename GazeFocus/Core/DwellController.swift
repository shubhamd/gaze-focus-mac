import Foundation
import QuartzCore

protocol DwellClock {
    func now() -> TimeInterval
}

struct SystemDwellClock: DwellClock {
    func now() -> TimeInterval { CACurrentMediaTime() }
}

/// Poll-based dwell classifier. Every gaze tick calls update(); the controller
/// tracks the "pending" screen and fires onScreenSwitch once gaze has held on
/// it for dwellDuration seconds. No Foundation Timer is used — the caller's
/// tick cadence (15fps from M3) drives the check, which makes behavior
/// deterministic and testable with a fake clock.
final class DwellController {
    static let minDuration: TimeInterval = 0.2
    static let maxDuration: TimeInterval = 1.0

    private var _dwellDuration: TimeInterval = 0.4
    /// Clamped to [minDuration, maxDuration] on set (AC-SETTINGS-02).
    var dwellDuration: TimeInterval {
        get { _dwellDuration }
        set { _dwellDuration = max(Self.minDuration, min(Self.maxDuration, newValue)) }
    }

    var onScreenSwitch: ((Int) -> Void)?

    private let clock: DwellClock
    private var currentScreen: Int
    private var pendingScreen: Int
    private var pendingStart: TimeInterval?

    init(clock: DwellClock = SystemDwellClock(), initialScreen: Int = 0) {
        self.clock = clock
        self.currentScreen = initialScreen
        self.pendingScreen = initialScreen
    }

    /// Reseed the "current" screen without firing a callback. Used after a
    /// cursor warp done by other means (e.g., user-initiated click).
    func setCurrentScreen(_ index: Int) {
        currentScreen = index
        pendingScreen = index
        pendingStart = nil
    }

    func update(gazeScreenIndex: Int) {
        if gazeScreenIndex == currentScreen {
            pendingScreen = currentScreen
            pendingStart = nil
            return
        }
        if gazeScreenIndex != pendingScreen {
            pendingScreen = gazeScreenIndex
            pendingStart = clock.now()
            return
        }
        // Same pending screen as before — check if we've held long enough.
        if let start = pendingStart, clock.now() - start >= dwellDuration {
            currentScreen = pendingScreen
            pendingStart = nil
            onScreenSwitch?(currentScreen)
        }
    }
}
