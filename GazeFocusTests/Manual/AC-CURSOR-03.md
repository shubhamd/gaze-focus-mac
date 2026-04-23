# AC-CURSOR-03 — Cursor warp does not generate spurious click events

**Target:** Over 10 warps to a screen with a large button at its center, the button is **never** activated.
**Prerequisites:** Two displays. Permissions granted. M7 calibration complete.

## Setup

1. On screen 2, open any app with a large click-target at the display's geometric center. A blank SwiftUI window with a `Button("Do not press", action: { print("CLICKED") })` is ideal. Alternatively, use Finder's desktop with a single folder centered on that display.
2. Confirm the button's center is within ±50 pt of `NSScreen[1].frame.midX / midY`.
3. Enable stdout logging in whatever app hosts the button so a click is observable.

## Procedure

1. With tracking active, sit so gaze starts on screen 1.
2. Look at screen 2. Wait for the cursor to warp there (the cursor should land on or very near the button).
3. Do **not** click manually during the test.
4. Look back at screen 1 so the cursor leaves.
5. Repeat steps 2–4 ten times.
6. After the tenth warp, check the button's activation log / click counter.

## Measurement

| Warp # | Cursor landed near button? | Click fired? |
|--------|----------------------------|--------------|
| 1 | … | … |
| … | … | … |
| 10 | … | … |

**Pass condition:** **Zero** clicks observed over 10 warps. The warp should only reposition the cursor; `CGAssociateMouseAndMouseCursorPosition(1)` re-synchronizes the hardware cursor without posting a mouse-down event.

## If it fails

If any click fires, review `CursorEngine.warpCursor(to:)`. Suspects, in order of likelihood:
1. A stray `CGEvent` posting code path (there shouldn't be one — MVP only calls `CGWarpMouseCursorPosition` + `CGAssociateMouseAndMouseCursorPosition`).
2. `CGAssociateMouseAndMouseCursorPosition(0)` being called somewhere (would decouple cursor from hardware and stale mouse-ups could fire).
