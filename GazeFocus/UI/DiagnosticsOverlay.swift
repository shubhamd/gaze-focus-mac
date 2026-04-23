import AppKit

/// Debug feedback window showing a red dot whose horizontal position
/// reflects the latest gaze X. Off by default; enabled via:
///
///     defaults write com.shubhamdesale.gazefocus diagnosticsOverlayEnabled -bool true
///
/// A Settings → Advanced toggle lands in Ramp-Up R2.1. The overlay is
/// non-interactive (ignoresMouseEvents) and rides above all other windows.
final class DiagnosticsOverlay {
    private static let defaultsKey = "diagnosticsOverlayEnabled"
    private static let stripHeight: CGFloat = 36
    private static let dotSize: CGFloat = 18

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    private var window: NSWindow?
    private let dot: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.systemRed.cgColor
        v.layer?.cornerRadius = DiagnosticsOverlay.dotSize / 2
        return v
    }()

    func showIfEnabled() {
        guard Self.isEnabled, window == nil else { return }
        guard let screen = NSScreen.main else { return }

        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - Self.stripHeight - 4,
            width: screen.frame.width,
            height: Self.stripHeight
        )

        let w = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.level = .screenSaver
        w.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true

        dot.frame = NSRect(
            x: 0,
            y: (Self.stripHeight - Self.dotSize) / 2,
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

    /// normalizedX is in [0, 1]; values outside clamp.
    func update(normalizedX: CGFloat) {
        guard let w = window, let content = w.contentView else { return }
        let available = content.bounds.width - Self.dotSize
        let clamped = max(0, min(1, normalizedX))
        dot.frame.origin.x = clamped * available
    }
}
