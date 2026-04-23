import XCTest
@testable import GazeFocus

private final class FakeClock: DwellClock {
    var t: TimeInterval = 0
    func now() -> TimeInterval { t }
    func advance(_ seconds: TimeInterval) { t += seconds }
}

final class DwellControllerTests: XCTestCase {

    // AC-DWELL-01
    func testNoSwitchBelowDwellDuration() {
        let clock = FakeClock()
        let c = DwellController(clock: clock, initialScreen: 0)
        c.dwellDuration = 0.4
        var switches: [Int] = []
        c.onScreenSwitch = { switches.append($0) }

        c.update(gazeScreenIndex: 1)         // t=0, pending starts
        clock.advance(0.200); c.update(gazeScreenIndex: 1)
        clock.advance(0.180); c.update(gazeScreenIndex: 1)  // t=0.380 < 0.4
        c.update(gazeScreenIndex: 0)         // gaze back to current, cancel

        XCTAssertEqual(switches, [])
    }

    // AC-DWELL-02
    func testSwitchFiresAtDwellDuration() {
        let clock = FakeClock()
        let c = DwellController(clock: clock, initialScreen: 0)
        c.dwellDuration = 0.4
        var switches: [Int] = []
        c.onScreenSwitch = { switches.append($0) }

        c.update(gazeScreenIndex: 1)         // t=0 starts pending
        clock.advance(0.450); c.update(gazeScreenIndex: 1)
        clock.advance(0.100); c.update(gazeScreenIndex: 1)  // still on screen 1 after switch

        XCTAssertEqual(switches, [1], "switch should fire exactly once")
    }

    // AC-DWELL-03
    func testDwellResetsWhenGazeReturnsToCurrent() {
        let clock = FakeClock()
        let c = DwellController(clock: clock, initialScreen: 0)
        c.dwellDuration = 0.4
        var switches: [Int] = []
        c.onScreenSwitch = { switches.append($0) }

        c.update(gazeScreenIndex: 1)         // t=0 pending starts
        clock.advance(0.200); c.update(gazeScreenIndex: 1)
        clock.advance(0.000); c.update(gazeScreenIndex: 0)   // gaze home, cancel
        clock.advance(0.100); c.update(gazeScreenIndex: 0)
        clock.advance(0.000); c.update(gazeScreenIndex: 1)   // new pending starts fresh

        // At this point total elapsed = 0.3s but only the second window counts.
        // Second window started at t=0.3, so fire at t=0.7.
        clock.advance(0.399); c.update(gazeScreenIndex: 1)
        XCTAssertEqual(switches, [], "dwell must restart — not fire at 0.699s")

        clock.advance(0.005); c.update(gazeScreenIndex: 1)   // t=0.704, elapsed since fresh pending = 0.404
        XCTAssertEqual(switches, [1])
    }

    // AC-SETTINGS-02 (the clamp)
    func testDwellDurationClamps() {
        let c = DwellController(clock: FakeClock())
        c.dwellDuration = 0.05
        XCTAssertEqual(c.dwellDuration, DwellController.minDuration)
        c.dwellDuration = 5.0
        XCTAssertEqual(c.dwellDuration, DwellController.maxDuration)
        c.dwellDuration = 0.6
        XCTAssertEqual(c.dwellDuration, 0.6)
    }

    // AC-DWELL-04: GazeSmoother convergence after step input.
    func testSmootherConvergesWithin50Samples() {
        var s = GazeSmoother(alpha: 0.3, initial: 0.0)
        // Let it settle fully at 0 (already initial=0, but mirror the spec).
        for _ in 0..<100 { _ = s.smooth(0.0) }

        var latest: CGFloat = 0
        for _ in 0..<50 { latest = s.smooth(1.0) }
        XCTAssertGreaterThanOrEqual(latest, 0.8,
            "smoother should cover ≥80% of a step input within 50 samples (333ms @ 15fps)")
    }

    func testSmootherStableAtConstantInput() {
        var s = GazeSmoother(alpha: 0.3, initial: 0.5)
        for _ in 0..<20 { _ = s.smooth(0.5) }
        XCTAssertEqual(s.current, 0.5, accuracy: 0.0001)
    }
}
