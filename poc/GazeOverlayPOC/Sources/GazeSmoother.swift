import CoreGraphics

/// 2D exponential smoother. Mirrors the main app's `GazeSmoother` (alpha=0.3
/// per tech design §5.3) but operates on a CGPoint so we can smooth the
/// mapped *screen position* rather than the 1D gaze X.
struct GazeSmoother2D {
    static let defaultAlpha: CGFloat = 0.3

    var alpha: CGFloat
    private(set) var current: CGPoint = .zero
    private var initialized = false

    init(alpha: CGFloat = defaultAlpha) {
        self.alpha = alpha
    }

    mutating func smooth(_ p: CGPoint) -> CGPoint {
        if !initialized {
            current = p
            initialized = true
            return p
        }
        current = CGPoint(
            x: alpha * p.x + (1 - alpha) * current.x,
            y: alpha * p.y + (1 - alpha) * current.y
        )
        return current
    }

    mutating func reset() {
        initialized = false
        current = .zero
    }
}
