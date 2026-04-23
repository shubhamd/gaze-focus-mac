# AC-CURSOR-02 — Cursor lands at geometric center of target screen

**Target:** After a warp to screen N, the cursor position is within 1 display point of `NSScreen.frame.midX / midY`.
**Prerequisites:** Two displays connected. Accessibility + Camera permissions granted. M7 calibration complete.

## Procedure

1. Enable macOS cursor-location indicator:
   System Settings → Accessibility → Display → Pointer → toggle **Shake mouse pointer to locate** on. Press ⌘ rapidly while watching the cursor to confirm position.
   Alternatively, run the helper script below in Terminal and have it log every 500 ms:

   ```bash
   while true; do
     /usr/bin/osascript -e 'tell application "System Events" to return (get position of window 1 of (processes whose name is "GazeFocus"))' 2>/dev/null
     /usr/bin/python3 -c "from AppKit import NSEvent; p=NSEvent.mouseLocation(); print(f'{p.x:.1f}, {p.y:.1f}')"
     sleep 0.5
   done
   ```
2. From the GazeFocus menu bar, start tracking (or verify it's active — icon should be an eye).
3. Look at screen 1 and dwell until the cursor warps there.
4. Without moving the mouse, record the cursor position.
5. Compute the expected center:
   ```
   expectedX = NSScreen.frame.origin.x + NSScreen.frame.width  / 2
   expectedY = NSScreen.frame.origin.y + NSScreen.frame.height / 2
   ```
   (AppKit's bottom-left coordinate system. Use `NSScreen.screens` in a Playground to read the values if needed.)
6. Repeat for screen 2 (and screen 3+ when multi-monitor calibration ships in R6.5).

## Measurement

| Target screen | Measured cursor (x, y) | Expected center (x, y) | Delta |
|---------------|-------------------------|-------------------------|-------|
| 1 | … | … | … |
| 2 | … | … | … |

**Pass condition:** |Δx| ≤ 1 pt AND |Δy| ≤ 1 pt for every warp.
