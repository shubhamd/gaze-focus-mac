import AppKit

/// 9-point calibration controller. Sequences a 3×3 grid of dots, collects the
/// gaze feature during each dot's hold window, and surfaces the resulting
/// (gaze, screen) sample list to the caller for `GazeMapper.fit`.
///
/// Sample collection is gated by `isCollecting` — the caller pushes features
/// in via `record(gaze:)` and skips the call between dots so saccades and
/// drift around dot transitions don't pollute buckets.
final class Calibrator {

    /// Normalized 3×3 grid in NSScreen coords (origin = bottom-left).
    /// Inset 10% from edges so the user doesn't have to look past the bezel.
    static let dotPositionsNormalized: [CGPoint] = [
        CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.9, y: 0.1),
        CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.9, y: 0.5),
        CGPoint(x: 0.1, y: 0.9), CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.9, y: 0.9),
    ]

    /// First slice of each dot's hold is discarded — the eye needs ~300–500ms
    /// to land on the new target.
    static let saccadeDelay: TimeInterval = 0.5
    /// Sampling window. ~30 samples at 30fps gives a stable mean per dot.
    static let collectDuration: TimeInterval = 1.0
    static let fadeIn: TimeInterval = 0.2

    private var window: KeyableWindow?
    private var dotView: DotView?
    private var keyMonitor: Any?
    private var currentIdx: Int = -1
    private(set) var isCollecting: Bool = false

    private var bucket: [CGPoint] = []
    private var samples: [(gaze: CGPoint, screen: CGPoint)] = []

    var onCompleted: (([(gaze: CGPoint, screen: CGPoint)]) -> Void)?
    var onCancelled: (() -> Void)?

    // MARK: - Lifecycle

    func present() {
        guard window == nil, let screen = NSScreen.main else { return }
        let frame = screen.frame

        let w = KeyableWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.level = .screenSaver
        w.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        w.isOpaque = false
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = false

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true

        let label = NSTextField(labelWithString:
            "Look at each red dot. Hold steady. Press ESC to cancel.")
        label.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.85)
        label.alignment = .center
        label.sizeToFit()
        label.frame.origin = NSPoint(
            x: (frame.size.width - label.frame.width) / 2,
            y: frame.size.height - 80
        )
        content.addSubview(label)

        let dot = DotView(frame: NSRect(x: 0, y: 0, width: DotView.diameter, height: DotView.diameter))
        dot.alphaValue = 0
        content.addSubview(dot)
        dotView = dot

        w.contentView = content
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // ESC
                self?.cancel()
                return nil
            }
            return event
        }

        // Brief settle delay before the first dot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.advance()
        }
    }

    func dismiss() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
        dotView = nil
        isCollecting = false
    }

    // MARK: - Sample plumbing

    func record(gaze: CGPoint) {
        guard isCollecting else { return }
        bucket.append(gaze)
    }

    // MARK: - Internals

    private func advance() {
        currentIdx += 1
        guard currentIdx < Self.dotPositionsNormalized.count else {
            finish()
            return
        }
        guard let win = window, let dot = dotView, let content = win.contentView else { return }
        let bounds = content.bounds

        let normalized = Self.dotPositionsNormalized[currentIdx]
        let screenPoint = CGPoint(
            x: normalized.x * bounds.width,
            y: normalized.y * bounds.height
        )

        dot.frame.origin = NSPoint(
            x: screenPoint.x - DotView.diameter / 2,
            y: screenPoint.y - DotView.diameter / 2
        )
        dot.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeIn
            dot.animator().alphaValue = 1.0
        }

        bucket.removeAll(keepingCapacity: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saccadeDelay) { [weak self] in
            self?.isCollecting = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saccadeDelay + Self.collectDuration) { [weak self] in
            guard let self else { return }
            self.isCollecting = false
            self.commitBucket(target: screenPoint)
            self.advance()
        }
    }

    private func commitBucket(target: CGPoint) {
        guard !bucket.isEmpty else { return }
        var sx: CGFloat = 0, sy: CGFloat = 0
        for p in bucket { sx += p.x; sy += p.y }
        let n = CGFloat(bucket.count)
        samples.append((
            gaze: CGPoint(x: sx / n, y: sy / n),
            screen: target
        ))
    }

    private func finish() {
        let collected = samples
        dismiss()
        onCompleted?(collected)
    }

    private func cancel() {
        dismiss()
        onCancelled?()
    }
}

// MARK: - Window + dot views

private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class DotView: NSView {
    static let diameter: CGFloat = 32

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemRed.cgColor
        layer?.cornerRadius = Self.diameter / 2
        layer?.shadowColor = NSColor.systemRed.cgColor
        layer?.shadowOpacity = 0.8
        layer?.shadowRadius = 16
        layer?.shadowOffset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not implemented")
    }
}
