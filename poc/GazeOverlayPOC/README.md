# GazeOverlayPOC

Standalone POC: a transparent overlay window with a single red dot that follows where the user is looking on the active display. Built to validate gaze-tracking improvements before they land in the main GazeFocus app.

## What it does

1. Launches as a menu-bar-only app (no Dock icon).
2. Asks for camera permission, then runs a **9-point calibration** (3×3 grid).
3. Fits a per-user gaze model — quadratic regression from the eye-relative pupil feature to screen coordinates.
4. Shows a click-through, screen-saver-level red dot that tracks gaze in real time.
5. Menu-bar item: **Recalibrate** / **Quit**.

## Why a POC

The shipping app uses only `leftPupil.normalizedPoints.first.x` to pick *which* display you're on. That's enough for cursor warp, but not point-on-screen accuracy: raw pupil-X is dominated by head position, not gaze. This POC is the smallest thing that proves a more useful pipeline:

| Stage | Main app (today) | POC |
|---|---|---|
| Feature | left pupil X (1D, in face-bbox coords) | both pupils, offset from eye-corner span (2D, head-pose tolerant) |
| Calibration | 5 dots → 1 boundary X | 9 dots → 6+6 polynomial coefficients |
| Output | which display index | (x, y) on the active display |
| Smoothing | EMA α=0.3 on gaze X | EMA α=0.3 on mapped (x, y) |

Same Vision/AVCapture spine, same restrained code style, ~6 source files.

## Accuracy envelope (be honest)

Webcam-only gaze, no IR, no specialized hardware:

- **Center of screen, head still:** ~50–100 px median error.
- **Edges / corners:** ~100–200 px.
- **Head movement of >5–10 cm:** breaks calibration; recalibrate.
- **Glasses:** mostly OK; reflective lenses can confuse pupil detection.

This is a POC — it's not aiming for cursor-grade precision. It's enough to demonstrate that point-on-screen gaze is reachable with the existing stack, and to surface the work needed to get there (head-pose normalization, blink rejection, recalibration triggers).

## Build & run

```bash
brew install xcodegen   # if missing
cd poc/GazeOverlayPOC
xcodegen generate
xcodebuild -project GazeOverlayPOC.xcodeproj -scheme GazeOverlayPOC -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/GazeOverlayPOC-*/Build/Products/Debug/GazeOverlayPOC.app
```

First launch: macOS prompts for camera. Grant it, then the calibration overlay appears. Look at each dot, hold steady (~1.5s per dot), avoid moving your head.

## Files

```
Sources/
  AppDelegate.swift     # @main; status item; pipeline wiring
  CameraManager.swift   # AVCapture → CVPixelBuffer (640×480, native fps)
  GazeEstimator.swift   # Vision face landmarks → 2D gaze feature
  GazeMapper.swift      # quadratic regression (Gauss-Jordan on normal eqs)
  GazeSmoother.swift    # 2D EMA, α=0.3
  Calibrator.swift      # 9-dot calibration window + sample buckets
  OverlayWindow.swift   # transparent screen-saver-level red dot
Resources/
  Info.plist            # LSUIElement, NSCameraUsageDescription
  POC.entitlements      # com.apple.security.device.camera
```

## What this is not

- **No persistence.** Calibration is in-memory; relaunch = recalibrate. Persisting it isn't free (monitor-config invalidation, head-anchored profiles) — left out on purpose.
- **No multi-display.** Targets `NSScreen.main` only. Multi-display is a separate problem from accuracy and out of POC scope.
- **No blink / out-of-frame handling.** Dot freezes at last position when the face leaves the frame. A more careful version would fade it.
- **No tests.** Math in `GazeMapper` would be the natural unit-test target if this graduates into the main app.

## Hand-off into the main app

Things in this POC that would inform main-app enhancements:

1. **Eye-relative pupil feature** (`GazeEstimator.eyeRelative`) — direct upgrade to `GazeDetector` for a head-pose-tolerant signal.
2. **Polynomial regression mapper** (`GazeMapper.fit`) — the missing piece for sub-display targeting; also handles N-screen calibration cleanly (just regress over a wider point set).
3. **9-point calibration UX** — extends the existing `CalibrationViewController` from 1D (5 dots, X-only) to 2D (3×3 grid).
4. **2D smoothing** — small extension of the existing `GazeSmoother`.

The intentional gaps (persistence, multi-display, blink handling) are where main-app integration adds the missing rigor.
