import AppKit
import CoreGraphics

/// A minimal, value-typed representation of a display used by CursorEngine.
/// Using this in place of NSScreen lets us unit-test sort + warp geometry
/// without needing real screens in a test environment.
struct DisplayFrame: Equatable {
    let id: Int
    let frame: CGRect
}

protocol ScreenProvider {
    var displays: [DisplayFrame] { get }
}

struct SystemScreenProvider: ScreenProvider {
    var displays: [DisplayFrame] {
        NSScreen.screens.enumerated().map { idx, screen in
            DisplayFrame(id: idx, frame: screen.frame)
        }
    }
}

enum CursorEngine {

    // MARK: - Test hooks

    #if DEBUG
    /// If set, replaces the main-thread precondition with an observer callback.
    /// Tests set this to verify the thread check without crashing the harness.
    /// When non-nil, the engine also returns early on off-main invocations
    /// rather than calling `warpHandler`.
    static var threadCheckHook: ((Bool) -> Void)?
    #endif

    /// Dispatches the actual cursor movement. Overridable so tests don't move
    /// the real cursor.
    static var warpHandler: (CGPoint) -> Void = { point in
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - API

    /// Returns displays sorted left-to-right by their frame's minX.
    static func sorted(_ displays: [DisplayFrame]) -> [DisplayFrame] {
        displays.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Live-system helper used by TrackingCoordinator.
    static var sortedSystemDisplays: [DisplayFrame] {
        sorted(SystemScreenProvider().displays)
    }

    /// Warps the cursor to the geometric center of `display`. MUST be called
    /// on the main thread — `CGWarpMouseCursorPosition` and the subsequent
    /// cursor-reassociation call are only safe to invoke from the main run loop.
    static func warpCursor(to display: DisplayFrame) {
        let isMain = Thread.isMainThread
        #if DEBUG
        if let hook = threadCheckHook {
            hook(isMain)
            if !isMain { return }
        } else {
            precondition(isMain, "CursorEngine.warpCursor(to:) must be called on the main thread")
        }
        #else
        precondition(isMain, "CursorEngine.warpCursor(to:) must be called on the main thread")
        #endif

        let mainHeight = CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
        // CGWarpMouseCursorPosition uses a top-left origin anchored at the
        // primary display. AppKit's frame.midY is bottom-left. Flip by the
        // main display's pixel height. See tech design §5.4 for the full
        // coordinate-system derivation.
        let target = CGPoint(
            x: display.frame.midX,
            y: mainHeight - display.frame.midY
        )
        warpHandler(target)
    }
}
