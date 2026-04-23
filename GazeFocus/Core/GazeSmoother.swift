import CoreGraphics

/// Exponential smoothing for the raw gaze-X signal before dwell classification.
/// Lower alpha = smoother but laggier. MVP uses alpha = 0.3 (hardcoded per
/// tech design §5.3). A user-facing "Gaze sensitivity" slider is Ramp-Up R2.6.
struct GazeSmoother {
    static let defaultAlpha: CGFloat = 0.3

    var alpha: CGFloat
    private var smoothedX: CGFloat

    init(alpha: CGFloat = defaultAlpha, initial: CGFloat = 0.5) {
        self.alpha = alpha
        self.smoothedX = initial
    }

    mutating func smooth(_ rawX: CGFloat) -> CGFloat {
        smoothedX = alpha * rawX + (1 - alpha) * smoothedX
        return smoothedX
    }

    var current: CGFloat { smoothedX }
}
