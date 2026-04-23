import AppKit
import CryptoKit
import Foundation

/// User-specific calibration data. For 2-screen MVP, `screenBoundaryGazeX`
/// contains a single value — the gaze-X reading when the user looked at the
/// boundary between screens. Post-smoothing gazeX < boundary → screen 0,
/// else screen 1. 3+ monitor support uses N-1 boundaries (Ramp-Up R6.5).
struct CalibrationProfile: Codable, Equatable {
    var screenBoundaryGazeX: [CGFloat]
    var createdAt: Date
    var monitorConfig: String

    static let userDefaultsKey = "com.shubhamdesale.gazefocus.calibration"

    // MARK: - Persistence

    static func load(from defaults: UserDefaults = .standard) -> CalibrationProfile? {
        guard let data = defaults.data(forKey: Self.userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CalibrationProfile.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: Self.userDefaultsKey)
    }

    // MARK: - Monitor config hash

    /// SHA-256 of the (left-to-right sorted) display frames. Used to detect
    /// when a user's monitor setup changes vs. when calibration was recorded.
    static func currentMonitorConfigHash(
        screens: [DisplayFrame] = SystemScreenProvider().displays
    ) -> String {
        let sorted = CursorEngine.sorted(screens)
        let joined = sorted.map {
            "\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.size.width),\($0.frame.size.height)"
        }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var isValidForCurrentMonitors: Bool {
        monitorConfig == Self.currentMonitorConfigHash()
    }

    // MARK: - Classifier

    /// Returns the target screen index for a smoothed gazeX sample. Profile-
    /// aware when available; falls back to an equal-width split otherwise.
    static func classifyScreen(
        smoothedX: CGFloat,
        screenCount: Int,
        profile: CalibrationProfile?
    ) -> Int {
        guard screenCount > 0 else { return 0 }
        guard screenCount > 1 else { return 0 }

        if let boundaries = profile?.screenBoundaryGazeX,
           boundaries.count == screenCount - 1 {
            var idx = 0
            for boundary in boundaries {
                if smoothedX < boundary { break }
                idx += 1
            }
            return min(idx, screenCount - 1)
        }
        // Fallback: equal-width split in [0, 1].
        let clamped = max(0, min(1, smoothedX))
        return min(Int(clamped * CGFloat(screenCount)), screenCount - 1)
    }
}
