import AppKit

/// Full-screen overlay window that sequences through 5 calibration dots,
/// blocks underlying interaction, and reports completion / cancellation.
/// One window spans the union of all connected screens.
final class CalibrationViewController: NSObject {

    /// Normalized horizontal positions across the union of all screens.
    /// Index 2 (center) provides the boundary anchor for the 2-screen MVP.
    static let normalizedDotPositions: [CGFloat] = [0.0, 0.25, 0.5, 0.75, 1.0]

    /// How long each dot holds (≈30 samples at 15fps per the plan).
    static let dotHoldDuration: TimeInterval = 2.0

    /// Fade-in duration for each dot.
    static let fadeInDuration: TimeInterval = 0.25

    private var window: KeyableWindow?
    private var dotView: DotView?
    private var currentDotIndex: Int = -1
    private var keyMonitor: Any?

    /// Fires on the main thread when a dot appears (pass index). The manager
    /// uses this as the signal to begin sample collection.
    var onDotAppeared: ((Int) -> Void)?

    /// Fires when the user presses ESC or the window is otherwise dismissed.
    var onCancel: (() -> Void)?

    /// Fires after all dots complete.
    var onFinished: (() -> Void)?

    // MARK: - Lifecycle

    func present() {
        guard window == nil else { return }
        let union = unionFrame()
        let w = KeyableWindow(
            contentRect: union,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.level = .screenSaver
        w.backgroundColor = NSColor.black.withAlphaComponent(0.82)
        w.isOpaque = false
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = false

        let content = NSView(frame: NSRect(origin: .zero, size: union.size))
        content.wantsLayer = true

        let dot = DotView(frame: NSRect(x: 0, y: 0, width: DotView.diameter, height: DotView.diameter))
        dot.alphaValue = 0
        content.addSubview(dot)
        dotView = dot

        // Instructions label anchored to the top of the overlay.
        let label = NSTextField(labelWithString:
            "Look at each dot as it appears. Press ESC to cancel.")
        label.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.85)
        label.alignment = .center
        label.sizeToFit()
        label.frame.origin = NSPoint(
            x: (union.size.width - label.frame.width) / 2,
            y: union.size.height - 80
        )
        content.addSubview(label)

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
    }

    func dismiss() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
        dotView = nil
        currentDotIndex = -1
    }

    // MARK: - Dot sequencing

    /// Advances to the next dot in sequence. Returns true if a new dot is
    /// being shown, false if the sequence is complete.
    @discardableResult
    func advance() -> Bool {
        currentDotIndex += 1
        guard currentDotIndex < Self.normalizedDotPositions.count,
              let dot = dotView,
              let content = window?.contentView else {
            onFinished?()
            return false
        }

        let normalized = Self.normalizedDotPositions[currentDotIndex]
        let centerX = content.bounds.width * normalized
        let centerY = content.bounds.height / 2
        dot.frame.origin = NSPoint(
            x: centerX - DotView.diameter / 2,
            y: centerY - DotView.diameter / 2
        )

        // Fade-in.
        dot.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeInDuration
            dot.animator().alphaValue = 1.0
        }

        onDotAppeared?(currentDotIndex)
        return true
    }

    private func cancel() {
        dismiss()
        onCancel?()
    }

    // MARK: - Helpers

    private func unionFrame() -> NSRect {
        let frames = NSScreen.screens.map { $0.frame }
        guard let first = frames.first else {
            return NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }
}

// MARK: - Supporting views

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
