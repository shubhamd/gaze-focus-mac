import AppKit

/// Full-screen, transparent, click-through window that draws a single red dot
/// at the predicted gaze position. Lives at .screenSaver level so it floats
/// above app windows; `ignoresMouseEvents = true` keeps it from stealing
/// clicks. Position updates run inside a CATransaction with implicit actions
/// disabled so the dot snaps with the gaze stream instead of trailing it via
/// the default 0.25s layer animation.
final class OverlayWindow {
    static let dotSize: CGFloat = 28

    private var window: NSWindow?
    private var screenFrame: NSRect = .zero

    private let dot: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.systemRed.cgColor
        v.layer?.cornerRadius = OverlayWindow.dotSize / 2
        v.layer?.shadowColor = NSColor.systemRed.cgColor
        v.layer?.shadowOpacity = 0.7
        v.layer?.shadowRadius = 12
        v.layer?.shadowOffset = .zero
        return v
    }()

    func show() {
        guard window == nil, let screen = NSScreen.main else { return }
        screenFrame = screen.frame

        let w = NSWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.level = .screenSaver
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let content = NSView(frame: NSRect(origin: .zero, size: screenFrame.size))
        content.wantsLayer = true

        dot.frame = NSRect(
            x: (screenFrame.width - Self.dotSize) / 2,
            y: (screenFrame.height - Self.dotSize) / 2,
            width: Self.dotSize,
            height: Self.dotSize
        )
        content.addSubview(dot)

        w.contentView = content
        w.orderFrontRegardless()
        window = w
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    /// `point` is in NSScreen.main coords (origin = bottom-left of the screen,
    /// in the global Cocoa coordinate space). The dot is centered on `point`.
    func update(point: CGPoint) {
        guard window != nil else { return }

        // Window content is in 0..width / 0..height (local view coords). Map
        // back from global screen coords by subtracting the screen origin —
        // necessary on multi-display setups where NSScreen.main may not be at
        // (0, 0).
        let localX = point.x - screenFrame.origin.x
        let localY = point.y - screenFrame.origin.y

        let clampedX = max(Self.dotSize / 2, min(screenFrame.width - Self.dotSize / 2, localX))
        let clampedY = max(Self.dotSize / 2, min(screenFrame.height - Self.dotSize / 2, localY))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.frame.origin = NSPoint(
            x: clampedX - Self.dotSize / 2,
            y: clampedY - Self.dotSize / 2
        )
        CATransaction.commit()
    }
}
