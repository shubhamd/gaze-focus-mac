import XCTest
@testable import GazeFocus

final class CalibrationTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "calibration.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "")
        defaults = nil
        super.tearDown()
    }

    // AC-CAL-01
    func testRoundTripPersistence() throws {
        let original = CalibrationProfile(
            screenBoundaryGazeX: [0.42],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            monitorConfig: "abc123"
        )
        original.save(to: defaults)

        let loaded = try XCTUnwrap(CalibrationProfile.load(from: defaults))
        XCTAssertEqual(loaded, original)
    }

    func testLoadReturnsNilWhenAbsent() {
        XCTAssertNil(CalibrationProfile.load(from: defaults))
    }

    func testClearRemovesProfile() {
        CalibrationProfile(
            screenBoundaryGazeX: [0.5],
            createdAt: Date(),
            monitorConfig: "x"
        ).save(to: defaults)
        XCTAssertNotNil(CalibrationProfile.load(from: defaults))
        CalibrationProfile.clear(from: defaults)
        XCTAssertNil(CalibrationProfile.load(from: defaults))
    }

    // AC-CAL-02 (hash determinism + change detection)
    func testMonitorConfigHashIsStableAndDistinctive() {
        let layoutA: [DisplayFrame] = [
            DisplayFrame(id: 0, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayFrame(id: 1, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ]
        let layoutB: [DisplayFrame] = [
            DisplayFrame(id: 0, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayFrame(id: 1, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        ]
        let hashA1 = CalibrationProfile.currentMonitorConfigHash(screens: layoutA)
        let hashA2 = CalibrationProfile.currentMonitorConfigHash(screens: layoutA)
        let hashB = CalibrationProfile.currentMonitorConfigHash(screens: layoutB)

        XCTAssertEqual(hashA1, hashA2, "hash must be deterministic for a given layout")
        XCTAssertNotEqual(hashA1, hashB, "different layouts must hash differently")
        XCTAssertEqual(hashA1.count, 64, "SHA-256 hex digest is 64 chars")
    }

    func testMonitorConfigHashIsOrderIndependent() {
        let reversed: [DisplayFrame] = [
            DisplayFrame(id: 1, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
            DisplayFrame(id: 0, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        ]
        let normal: [DisplayFrame] = [
            DisplayFrame(id: 0, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayFrame(id: 1, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ]
        XCTAssertEqual(
            CalibrationProfile.currentMonitorConfigHash(screens: reversed),
            CalibrationProfile.currentMonitorConfigHash(screens: normal)
        )
    }

    // M7.5 — profile-aware classifier
    func testClassifierUsesProfileBoundary() {
        let profile = CalibrationProfile(
            screenBoundaryGazeX: [0.4],  // user's center-stare produces gazeX=0.4
            createdAt: Date(),
            monitorConfig: "x"
        )
        XCTAssertEqual(
            CalibrationProfile.classifyScreen(smoothedX: 0.30, screenCount: 2, profile: profile), 0)
        XCTAssertEqual(
            CalibrationProfile.classifyScreen(smoothedX: 0.50, screenCount: 2, profile: profile), 1)
        // Without a profile, naive midpoint → 0.30 < 0.5 → screen 0, 0.50 → screen 1.
        XCTAssertEqual(
            CalibrationProfile.classifyScreen(smoothedX: 0.30, screenCount: 2, profile: nil), 0)
        XCTAssertEqual(
            CalibrationProfile.classifyScreen(smoothedX: 0.45, screenCount: 2, profile: nil), 0)
        XCTAssertEqual(
            CalibrationProfile.classifyScreen(smoothedX: 0.50, screenCount: 2, profile: nil), 1)
    }

    func testClassifierSingleScreenReturnsZero() {
        XCTAssertEqual(
            CalibrationProfile.classifyScreen(smoothedX: 0.5, screenCount: 1, profile: nil), 0)
    }
}
