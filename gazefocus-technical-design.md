# GazeFocus — Technical Design Document
### Eye-Tracking Multi-Display Focus Switcher for macOS
**Version:** 1.0 | **Author:** Shubham Desale | **Date:** April 2026  
**Status:** Pre-development / Design Phase

---

## 1. Executive Summary

GazeFocus is a macOS menu-bar utility that uses the built-in FaceTime webcam and Apple's Vision framework to detect which display the user is looking at, then automatically warps the mouse cursor to that screen — no keyboard shortcuts, no mouse dragging, no hardware beyond the Mac itself.

This document defines the full technical architecture, component breakdown, phased build plan, and a strict set of UX/usability acceptance criteria — each written to be either human-verifiable through manual testing or automatically verifiable through unit/integration tests.

Target audience: a macOS developer who is new to the platform but experienced in backend/systems programming (Node.js, Python, AWS). All Apple-platform concepts are explained from first principles.

---

## 2. Problem Statement

### 2.1 User Pain
On a multi-display macOS setup, moving focus between screens requires physically moving the mouse across large distances — or memorizing keyboard shortcuts from third-party tools. This is a high-frequency, low-value action that interrupts flow dozens of times per day.

### 2.2 Existing Solutions and Their Gaps

| Tool | Mechanism | Gap |
|---|---|---|
| DisplayHop | Keyboard shortcut | Still requires hands |
| NinjaMouse | Keyboard shortcut | Still requires hands |
| HocusFocus | Hover/proximity detection | False triggers; not intent-based |
| Tobii Eye Tracker | Dedicated hardware | $300+ hardware required |
| Apple Eye Tracking (visionOS) | Vision Pro headset | Not a desktop solution |

### 2.3 The GazeFocus Advantage
Uses the webcam already built into every Mac. Zero extra hardware. Gaze is the most natural signal of intent — where you look is where you want to work.

---

## 3. System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        GazeFocus.app                            │
│                                                                 │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────────┐ │
│  │  AVCapture  │───▶│  Vision      │───▶│  Gaze Classifier   │ │
│  │  Session    │    │  Pipeline    │    │  (Screen Index)    │ │
│  │  (Camera)   │    │  (Face       │    │                    │ │
│  │  15fps      │    │  Landmarks)  │    │  Left / Right /    │ │
│  └─────────────┘    └──────────────┘    │  Center            │ │
│                                         └────────┬───────────┘ │
│                                                  │             │
│  ┌──────────────────────────────────────────────▼───────────┐ │
│  │               Dwell Timer + Jitter Filter                 │ │
│  │   - Ignore gaze < 350ms on new screen                    │ │
│  │   - Kalman filter for position smoothing                  │ │
│  └──────────────────────────────────────┬────────────────────┘ │
│                                         │                       │
│  ┌──────────────────────────────────────▼────────────────────┐ │
│  │                  Cursor Warp Engine                        │ │
│  │   CGWarpMouseCursorPosition() → Target Screen Center      │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌──────────────────┐   ┌──────────────────┐                  │
│  │  Menu Bar UI     │   │  Settings (SwiftUI│                  │
│  │  (AppKit/NSMenu) │   │  Panel)           │                  │
│  └──────────────────┘   └──────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.1 Process and Thread Model

```
Main Thread        → AppKit UI, Menu Bar, NSApplication lifecycle
Background Queue   → AVCaptureSession + Vision requests (serial, 15fps)
Main Thread (async)→ CGWarpMouseCursorPosition (must be main thread)
```

All Vision processing must be off the main thread. Cursor moves must be dispatched back to the main thread via `DispatchQueue.main.async`.

---

## 4. Technology Stack

### 4.1 Language and Frameworks

| Component | Technology | Why |
|---|---|---|
| Language | Swift 5.9+ | Native macOS, Swift Concurrency support |
| UI (Menu Bar) | AppKit (`NSStatusItem`, `NSMenu`) | Menu bar apps require AppKit |
| UI (Settings) | SwiftUI | Declarative, fast to build |
| Camera | AVFoundation (`AVCaptureSession`) | Apple-native camera pipeline |
| Face/Eye Detection | Vision (`VNDetectFaceLandmarksRequest`) | Free, on-device, Neural Engine |
| Cursor Control | Core Graphics (`CGWarpMouseCursorPosition`) | Only API for cursor warping |
| Display Geometry | AppKit (`NSScreen`) | Multi-display layout detection |
| Persistence | `UserDefaults` (settings) + `Codable` structs | Simple, no external deps |
| Build System | Xcode 15+ | Required for macOS development |
| Distribution | Direct DMG (not App Store) | Accessibility API blocked on App Store sandboxing |

### 4.2 Why NOT the App Store
The Accessibility API (`AXIsProcessTrusted`) and `CGWarpMouseCursorPosition` both require the user to grant Accessibility permission in System Settings. App Store sandboxed apps cannot use these APIs. Distribute as a direct-download signed `.dmg`.

### 4.3 macOS Version Target
**Minimum: macOS 13 Ventura.** Vision framework face landmarks are stable from macOS 12+, but Ventura (2022) gives you SwiftUI improvements and better AVCapture performance. Covers ~90%+ of active Macs as of 2026.

---

## 5. Component Deep-Dive

### 5.1 Camera Pipeline (`CameraManager.swift`)

AVFoundation captures frames from the built-in FaceTime camera and feeds them to the Vision pipeline.

**Key implementation decisions:**
- Use `sessionPreset = .low` (320×240). Vision face landmark detection achieves full accuracy at low resolution. Higher resolution wastes CPU and battery.
- Cap at **15fps** using `AVCaptureVideoDataOutput.videoSettings` with `minFrameDuration`. Eye-to-screen classification doesn't need 60fps.
- Run the `AVCaptureSession` on a **dedicated background DispatchQueue** — never the main queue.

```swift
// CameraManager.swift — core setup
import AVFoundation
import Vision

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "com.gazefocus.camera", qos: .userInitiated)
    var onFrame: ((CVPixelBuffer) -> Void)?

    func start() {
        session.sessionPreset = .low
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        // 15fps cap
        output.setSampleBufferDelegate(self, queue: videoQueue)
        device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 15)

        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
```

### 5.2 Vision Pipeline (`GazeDetector.swift`)

Apple's Vision framework provides `VNDetectFaceLandmarksRequest`, which returns 76 facial landmark points including the left eye, right eye, and pupil positions.

**What Vision gives you:**
- `VNFaceObservation.landmarks?.leftEye` — normalized polygon of the left eye boundary
- `VNFaceObservation.landmarks?.rightEye` — normalized polygon of the right eye boundary
- `VNFaceObservation.landmarks?.leftPupil` — center point of left pupil
- `VNFaceObservation.landmarks?.rightPupil` — center point of right pupil
- `VNFaceObservation.boundingBox` — normalized face bounding box (confidence-weighted)

**Gaze Direction Estimation (simplified 2D method):**

For the screen-switching use case, you don't need full 3D gaze estimation. You only need to know: *is the user looking left or right of center?*

The approach:
1. Get the horizontal center of the left pupil position within the left eye bounding box
2. Normalize it: `gazeX = pupilCenter.x / eyeWidth` — gives a value 0.0 (looking far left) to 1.0 (looking far right)
3. Map this normalized gaze X to screen index

```swift
// GazeDetector.swift
import Vision

struct GazeResult {
    let screenIndex: Int      // Which screen (0, 1, 2...)
    let confidence: Float     // 0.0 to 1.0
    let rawGazeX: CGFloat     // Normalized 0–1 horizontal gaze
}

class GazeDetector {
    private let requestHandler = VNSequenceRequestHandler()

    func detect(in pixelBuffer: CVPixelBuffer,
                screenCount: Int,
                completion: @escaping (GazeResult?) -> Void) {

        let request = VNDetectFaceLandmarksRequest { req, err in
            guard err == nil,
                  let obs = req.results?.first as? VNFaceObservation,
                  obs.confidence > 0.7,  // Reject low-confidence detections
                  let pupils = obs.landmarks?.leftPupil,
                  let leftEye = obs.landmarks?.leftEye else {
                completion(nil)
                return
            }

            // Pupil X position within face bounding box, normalized
            let pupilX = pupils.normalizedPoints.first?.x ?? 0.5
            let gazeX = CGFloat(pupilX)

            // Map gaze to screen index
            let idx = min(Int(gazeX * CGFloat(screenCount)), screenCount - 1)
            completion(GazeResult(screenIndex: idx,
                                  confidence: obs.confidence,
                                  rawGazeX: gazeX))
        }

        try? requestHandler.perform([request], on: pixelBuffer)
    }
}
```

**Important limitation:** The simplified 2D method above works well for 2-monitor setups. For 3+ monitors or precise gaze coordinates (future feature), a full 3D gaze estimation requires a calibration-based affine transform, documented in Section 8 (Future Work).

### 5.3 Dwell Timer + Jitter Filter (`DwellController.swift`)

The most critical UX component. Without it, the cursor jumps every time you glance between screens while reading.

**Algorithm:**
1. Maintain `currentScreenIndex` (where cursor currently is)
2. Maintain `pendingScreenIndex` (where gaze is pointing)
3. Start a timer when `pendingScreenIndex != currentScreenIndex`
4. If gaze holds on `pendingScreenIndex` for `dwellDuration` (default: 400ms), trigger cursor warp
5. If gaze leaves `pendingScreenIndex` before timer fires, cancel timer

```swift
// DwellController.swift
import Foundation

class DwellController {
    var dwellDuration: TimeInterval = 0.4  // User-configurable (0.2–1.0s)
    var onScreenSwitch: ((Int) -> Void)?

    private var currentScreen = 0
    private var pendingScreen = 0
    private var dwellTimer: Timer?

    func update(gazeScreenIndex: Int) {
        guard gazeScreenIndex != currentScreen else {
            // Gaze returned to current screen — cancel pending switch
            cancelPending()
            return
        }

        if gazeScreenIndex != pendingScreen {
            // New pending screen — restart timer
            pendingScreen = gazeScreenIndex
            startDwellTimer()
        }
        // If gazeScreenIndex == pendingScreen, timer already running — do nothing
    }

    private func startDwellTimer() {
        cancelPending()
        dwellTimer = Timer.scheduledTimer(withTimeInterval: dwellDuration,
                                          repeats: false) { [weak self] _ in
            guard let self else { return }
            self.currentScreen = self.pendingScreen
            self.onScreenSwitch?(self.currentScreen)
        }
    }

    private func cancelPending() {
        dwellTimer?.invalidate()
        dwellTimer = nil
    }
}
```

**Exponential smoothing for raw gaze signal (pre-dwell):**

```swift
// Apply before passing to DwellController
struct GazeSmoother {
    var alpha: CGFloat = 0.3  // Lower = smoother but laggier
    private var smoothedX: CGFloat = 0.5

    mutating func smooth(_ rawX: CGFloat) -> CGFloat {
        smoothedX = alpha * rawX + (1 - alpha) * smoothedX
        return smoothedX
    }
}
```

### 5.4 Cursor Warp Engine (`CursorEngine.swift`)

```swift
// CursorEngine.swift
import CoreGraphics
import AppKit

class CursorEngine {
    /// Warp cursor to the center of the target screen.
    /// Must be called on the main thread.
    static func warpCursor(to screen: NSScreen) {
        // NSScreen uses flipped coordinates (top-left origin in AppKit)
        // CGWarpMouseCursorPosition uses bottom-left origin
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        let point = CGPoint(
            x: screen.frame.midX,
            y: CGFloat(CGDisplayPixelsHigh(CGMainDisplayID())) - screen.frame.midY
        )
        CGWarpMouseCursorPosition(point)
        // Also move the event tap cursor to stay in sync
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Returns all screens sorted left-to-right
    static var sortedScreens: [NSScreen] {
        NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
    }
}
```

**Coordinate system gotcha for beginners:**
AppKit's `NSScreen.frame` uses a coordinate system with the origin at the bottom-left of the primary display. `CGWarpMouseCursorPosition` also uses bottom-left origin but applies to the global display space. When multiple screens are involved, screen frames can have negative X/Y values (screens to the left or above the primary). Always use the global coordinate, not screen-relative coordinates.

### 5.5 Menu Bar UI (`AppDelegate.swift`)

GazeFocus has no Dock icon and no main window. It lives entirely in the macOS menu bar — the standard pattern for "utility" apps like Amphetamine, Lungo, and Rectangle.

```swift
// AppDelegate.swift
import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "GazeFocus")
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "GazeFocus — Active", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Pause (⌥⌘G)", action: #selector(togglePause), keyEquivalent: "g")
        menu.addItem(withTitle: "Recalibrate...", action: #selector(openCalibration), keyEquivalent: "")
        menu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit GazeFocus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func togglePause() { /* toggle tracking */ }
    @objc func openCalibration() { /* show calibration overlay */ }
    @objc func openSettings() { /* show SwiftUI settings panel */ }
}
```

**Menu bar icon states:**

| State | SF Symbol | Color tint |
|---|---|---|
| Tracking active | `eye` | Default (system color) |
| Paused by user | `eye.slash` | Default |
| Low confidence (bad lighting) | `eye.trianglebadge.exclamationmark` | Orange |
| Permission missing | `exclamationmark.triangle` | Red |
| Calibrating | `scope` | Blue |

### 5.6 Permissions and Onboarding Flow

GazeFocus requires three permissions. Obtaining them is the highest-friction part of the user experience. Each must be requested at the right moment with the right context.

**Permission 1: Camera**
- Requested by: `AVCaptureDevice.requestAccess(for: .video)`
- When to request: On first launch, before any camera use
- NSCameraUsageDescription in Info.plist: *"GazeFocus uses your camera to detect which screen you're looking at. Video is processed entirely on-device and never stored or transmitted."*

**Permission 2: Accessibility**
- Requested by: `AXIsProcessTrusted()` check; if false, open System Settings deeplink
- When to request: After camera permission granted, second step of onboarding
- Cannot be requested with a system dialog — must guide user to System Settings manually

```swift
// Open System Settings directly to the Accessibility pane
let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
NSWorkspace.shared.open(url)
```

**Permission 3: (Optional) Screen Recording**
- Only needed if you want to show a live "cursor preview" overlay on the correct screen
- Not required for core cursor-warp functionality
- Defer to v0.3 or later

**Onboarding sequence (5 screens):**
1. Welcome — one-sentence value prop + "Get Started" button
2. How it works — animated 3-panel illustration (look left → cursor goes left)
3. Camera permission request — with privacy reassurance
4. Accessibility permission — step-by-step guide with animated screenshot of System Settings
5. Quick calibration (5-dot) → Done

### 5.7 Calibration System (`CalibrationManager.swift`)

Calibration maps raw gaze X values (from Vision) to actual screen boundaries. Without calibration, gaze estimation is offset by head position, monitor placement, and individual eye anatomy.

**Minimum viable calibration (v0.1):**
5-point full-screen overlay. User looks at each dot in sequence. Each dot records 30 frames of gaze data. The median gaze X value for each point becomes an anchor.

```
Dot positions:
  [1] Far left — maps to left edge of screen 1
  [2] Center-left — maps to center of screen 1
  [3] Center — maps to boundary between screens
  [4] Center-right — maps to center of screen 2
  [5] Far right — maps to right edge of screen 2
```

**Calibration data stored:**
```swift
struct CalibrationProfile: Codable {
    var screenBoundaryGazeX: [CGFloat]  // gaze X values at each screen boundary
    var createdAt: Date
    var monitorConfig: String  // Hash of NSScreen arrangement for validity check
}
```

If the monitor configuration changes (detected by comparing hashed NSScreen frames), prompt recalibration.

### 5.8 Settings Panel (`SettingsView.swift`)

Built in SwiftUI. Opened as a floating panel (not a full window) using `NSPanel`.

**Settings exposed to user:**

| Setting | Type | Default | Range |
|---|---|---|---|
| Dwell time | Slider | 400ms | 200ms – 1000ms |
| Gaze sensitivity | Slider | 0.5 | 0.1 – 1.0 |
| Launch at login | Toggle | Off | — |
| Show dwell progress ring | Toggle | On | — |
| Pause when on battery | Toggle | Off | — |
| Camera frame rate | Picker | 15fps | 10 / 15 / 30fps |

**What NOT to expose:** Do not expose raw calibration numbers, Vision confidence thresholds, or Kalman filter parameters. These are internal constants, not user settings.

---

## 6. Project Structure

```
GazeFocus/
├── GazeFocus.xcodeproj
├── GazeFocus/
│   ├── App/
│   │   ├── AppDelegate.swift          ← NSApplication entry point
│   │   ├── GazeFocus-Info.plist       ← NSCameraUsageDescription, LSUIElement
│   │   └── GazeFocus.entitlements     ← No App Sandbox (required for Accessibility API)
│   │
│   ├── Core/
│   │   ├── CameraManager.swift        ← AVCaptureSession, 15fps feed
│   │   ├── GazeDetector.swift         ← Vision pipeline, VNDetectFaceLandmarksRequest
│   │   ├── GazeSmoother.swift         ← Exponential smoothing filter
│   │   ├── DwellController.swift      ← Dwell timer, jitter suppression
│   │   └── CursorEngine.swift         ← CGWarpMouseCursorPosition
│   │
│   ├── Calibration/
│   │   ├── CalibrationManager.swift   ← Calibration session coordinator
│   │   ├── CalibrationViewController.swift  ← Full-screen overlay (AppKit)
│   │   └── CalibrationProfile.swift   ← Codable struct + UserDefaults persistence
│   │
│   ├── UI/
│   │   ├── MenuBarController.swift    ← NSStatusItem, NSMenu, icon state
│   │   ├── OnboardingViewController.swift  ← First-launch flow
│   │   ├── SettingsView.swift         ← SwiftUI settings panel
│   │   └── DwellRingOverlay.swift     ← NSPanel overlay showing dwell progress
│   │
│   └── Utils/
│       ├── PermissionsManager.swift   ← Camera + Accessibility checks
│       └── DisplayGeometry.swift      ← NSScreen helpers, coordinate conversion
│
└── GazeFocusTests/
    ├── DwellControllerTests.swift
    ├── GazeDetectorTests.swift
    └── CalibrationTests.swift
```

**Critical Info.plist keys:**

```xml
<!-- Hides from Dock and App Switcher — essential for menu bar apps -->
<key>LSUIElement</key>
<true/>

<!-- Camera permission description shown in system dialog -->
<key>NSCameraUsageDescription</key>
<string>GazeFocus uses your camera to detect which screen you are looking at.
All processing is done on-device and no video is ever stored or transmitted.</string>
```

---

## 7. Build Phases (Phased Roadmap)

### Phase 0 — "Hello macOS" (Week 1)
**Goal:** Get comfortable with Xcode and the menu bar app pattern before writing any eye-tracking code.

- [ ] Create a new macOS app in Xcode (target: macOS 13, language: Swift)
- [ ] Set `LSUIElement = true` in Info.plist — verify app disappears from Dock
- [ ] Create `NSStatusItem` with a system SF Symbol icon
- [ ] Add a basic `NSMenu` with "Quit" item that works
- [ ] Verify the app launches, shows in menu bar, and quits cleanly

**Learning resources:**
- Apple's "Building a Menu Bar Extra" sample code (developer.apple.com)
- Hacking With Swift "How to add a toolbar to a macOS window" — for AppKit fundamentals

### Phase 1 — Camera + Face Detection (Week 2)
**Goal:** See Vision landmarks working before building any UI around them.

- [ ] Request camera permission correctly; handle denied state gracefully
- [ ] Start `AVCaptureSession` at 15fps, 320×240
- [ ] Run `VNDetectFaceLandmarksRequest` on each frame
- [ ] Log pupil X position to Xcode console — verify values shift left/right as you move your gaze
- [ ] Add a simple debug overlay (NSWindow) showing a dot that moves with your gaze — this is your feedback mechanism during development

### Phase 2 — Cursor Warp (Week 2–3)
**Goal:** Manually trigger cursor warp with a keyboard shortcut first, then hook it to gaze.

- [ ] Request Accessibility permission; handle missing permission state
- [ ] Implement `CursorEngine.warpCursor(to:)` — test with hardcoded screen index
- [ ] Add global keyboard shortcut (e.g., `⌥1`, `⌥2`) to warp to each screen — validates the warp works before gaze is involved
- [ ] Hook `GazeDetector` output to `DwellController` to `CursorEngine` — the full pipeline

### Phase 3 — Dwell + Jitter Control (Week 3)
**Goal:** Make the cursor switching feel controlled and non-annoying.

- [ ] Implement `DwellController` with 400ms default
- [ ] Implement `GazeSmoother` with alpha=0.3
- [ ] Test with daily work for 30 minutes — tune dwell duration until false triggers feel rare
- [ ] Implement pause/resume via `⌥⌘G` global shortcut

### Phase 4 — Onboarding + Calibration (Week 4)
**Goal:** App is usable by someone who didn't build it.

- [ ] Build 5-screen onboarding flow (AppKit `NSViewController` stack or SwiftUI `NavigationStack` in an `NSWindow`)
- [ ] Build 5-dot calibration overlay (full-screen `NSWindow`, `NSScreen.main`, animated `CALayer` dots)
- [ ] Store `CalibrationProfile` in `UserDefaults`
- [ ] Detect monitor config changes and prompt recalibration

### Phase 5 — Settings + Polish (Week 5)
**Goal:** App feels finished, not like a prototype.

- [ ] SwiftUI `SettingsView` exposed via menu bar
- [ ] Dwell progress ring overlay (`NSPanel`, `CAShapeLayer` stroke animation)
- [ ] Menu bar icon state machine (active/paused/low-confidence/error)
- [ ] Launch at Login via `ServiceManagement` framework (macOS 13 API: `SMAppService.mainApp.register()`)
- [ ] Create signed `.dmg` for distribution (use `create-dmg` CLI tool)

---

## 8. Acceptance Criteria

Each criterion is marked with its verification method:
- **[AUTO]** — Verifiable by XCTest unit/integration test
- **[MANUAL]** — Verified by a human tester following the described procedure

---

### 8.1 Camera Pipeline

**AC-CAM-01** [AUTO]  
`CameraManager` must not start the `AVCaptureSession` without camera permission.  
_Test: Mock `AVCaptureDevice.authorizationStatus` returning `.denied`. Assert `session.isRunning == false`._

**AC-CAM-02** [AUTO]  
`CameraManager` frame rate must not exceed 15fps under normal operation.  
_Test: Count frames received via `onFrame` callback over a 2-second window. Assert count <= 32 (allowing 1 frame tolerance)._

**AC-CAM-03** [MANUAL]  
CPU usage while camera pipeline is running must be below 10% on an Apple Silicon MacBook.  
_Test: Launch app, open Activity Monitor, observe GazeFocus CPU% for 60 seconds with face in frame. Must stay below 10% average._

**AC-CAM-04** [MANUAL]  
Battery impact: the app must not appear in "Significant Energy" list in Battery menu after 30 minutes of normal use.  
_Test: Run app for 30 minutes with face in frame. Open Battery menu → "Apps Using Significant Energy". GazeFocus must not appear._

---

### 8.2 Gaze Detection

**AC-GAZE-01** [AUTO]  
`GazeDetector` must return `nil` when Vision confidence is below 0.7.  
_Test: Feed a blurry/occluded test image. Assert `completion(nil)` is called._

**AC-GAZE-02** [AUTO]  
`GazeDetector` must return `nil` when no face is detected in the frame.  
_Test: Feed a blank gray `CVPixelBuffer`. Assert `completion(nil)` is called._

**AC-GAZE-03** [MANUAL]  
Gaze screen classification accuracy must be >= 85% over 100 deliberate gaze samples.  
_Test: Sit 60cm from monitor. Alternate looking at screen 1 and screen 2, 50 times each, holding gaze 1 second per screen. Enable debug logging. Count correct screen classifications. Must be >= 85/100._

**AC-GAZE-04** [MANUAL]  
Detection must work in typical indoor lighting (500–1000 lux, equivalent to a lit office).  
_Test: Turn on standard overhead office lights. Perform AC-GAZE-03. Must pass._

**AC-GAZE-05** [MANUAL]  
Detection must gracefully degrade (return to neutral, not crash) when user puts hand over camera.  
_Test: Cover camera with hand. Verify no crash. Menu bar icon switches to amber "low confidence" state within 2 seconds._

---

### 8.3 Dwell Controller

**AC-DWELL-01** [AUTO]  
No cursor switch must occur when gaze is on a new screen for less than the configured dwell duration.  
_Test: Set `dwellDuration = 0.4`. Feed `update(gazeScreenIndex: 1)` for 380ms, then `update(gazeScreenIndex: 0)`. Assert `onScreenSwitch` is never called._

**AC-DWELL-02** [AUTO]  
Cursor switch must occur after dwell duration is met.  
_Test: Set `dwellDuration = 0.4`. Feed `update(gazeScreenIndex: 1)` continuously for 450ms. Assert `onScreenSwitch(1)` is called exactly once._

**AC-DWELL-03** [AUTO]  
Dwell timer must reset when gaze returns to current screen before firing.  
_Test: `update(gazeScreenIndex: 1)` for 200ms, then `update(gazeScreenIndex: 0)` for 100ms, then `update(gazeScreenIndex: 1)` again. Assert the second dwell window starts fresh (total switch occurs only after a full 400ms on the second gaze-to-1)._

**AC-DWELL-04** [AUTO]  
`GazeSmoother` output must converge within 300ms of a step input change.  
_Test: Feed 100 samples of `rawX = 0.0` (settled), then switch to `rawX = 1.0` for 50 samples at 15fps (~333ms). Assert smoothed output >= 0.8 after 50 samples._

**AC-DWELL-05** [MANUAL]  
False trigger rate during normal reading: user reads a document on one screen for 5 minutes while a second screen is visible. Fewer than 3 unintended cursor switches must occur.  
_Test: Tester reads static text on screen 1. Counts unintended cursor movements. Must be < 3 in 5 minutes with default settings._

---

### 8.4 Cursor Warp Engine

**AC-CURSOR-01** [AUTO]  
`CursorEngine.warpCursor(to:)` must be called on the main thread.  
_Test: In a test that calls `warpCursor` from a background queue, assert a `preconditionFailure` or use `Thread.isMainThread` check in the implementation._

**AC-CURSOR-02** [MANUAL]  
Cursor must appear at the center of the target screen after a warp, within 1 display point of the geometric center.  
_Test: Trigger a warp to screen 2. Use macOS "Show cursor location" accessibility tool to verify final position is within 1pt of `NSScreen.frame.midX/midY`._

**AC-CURSOR-03** [MANUAL]  
Warping the cursor must not generate spurious mouse click events on the target screen.  
_Test: Place a button on screen 2 directly at screen center. Trigger 10 cursor warps to screen 2. Verify the button is not activated by any warp. (CGWarpMouseCursorPosition is event-free; CGAssociateMouseAndMouseCursorPosition must be called correctly.)_

**AC-CURSOR-04** [MANUAL]  
Cursor warp latency from dwell timer fire to cursor appearing on target screen must be under 50ms.  
_Test: Use Instruments Time Profiler. Measure time from `onScreenSwitch` callback to `CGWarpMouseCursorPosition` call. Must be < 50ms._

---

### 8.5 Menu Bar UI

**AC-MENU-01** [MANUAL]  
App must not appear in the Dock after launch.  
_Test: Launch app. Verify Dock contains no GazeFocus icon. Verify `LSUIElement = true` in Info.plist._

**AC-MENU-02** [MANUAL]  
Menu bar icon must reflect tracking state correctly within 2 seconds of state change.  
_Test: Block camera (icon should turn amber within 2s). Unblock (icon returns to green within 2s). Press pause (icon changes to `eye.slash`)._

**AC-MENU-03** [MANUAL]  
All menu items must have keyboard equivalents or be accessible via VoiceOver.  
_Test: Tab through menu items using VoiceOver. All items must be announced correctly with their action and keyboard shortcut (if any)._

**AC-MENU-04** [MANUAL]  
Selecting "Settings…" must open the settings panel within 300ms.  
_Test: Click "Settings…" in menu. Panel must be visible and interactive in under 300ms (use Instruments if needed)._

**AC-MENU-05** [MANUAL]  
The menu title line showing current status ("GazeFocus — Active" / "GazeFocus — Paused") must update within 1 second of state change.  
_Test: Toggle pause. Verify title text in menu updates within 1s._

---

### 8.6 Onboarding Flow

**AC-ONBOARD-01** [MANUAL]  
Onboarding must be shown on first launch and never shown again on subsequent launches.  
_Test: Fresh install → onboarding appears. Complete onboarding. Quit and relaunch → onboarding must not appear._

**AC-ONBOARD-02** [MANUAL]  
If camera permission is denied during onboarding, the app must show a specific error screen with a button that opens System Settings → Privacy & Security → Camera.  
_Test: Deny camera in system dialog during onboarding. Verify error screen appears. Click "Open Settings" button. Verify System Settings opens to the Camera privacy pane._

**AC-ONBOARD-03** [MANUAL]  
If Accessibility permission is not granted, the app must show a step-by-step guide with a numbered screenshot sequence.  
_Test: Do not grant Accessibility permission. Verify onboarding shows at least 2 numbered steps with visual indication of where to click in System Settings._

**AC-ONBOARD-04** [MANUAL]  
Onboarding must be completable by a new user in under 3 minutes.  
_Test: Hand the app to a person unfamiliar with it. Time from first launch to first successful gaze-triggered cursor switch. Must be < 3 minutes._

**AC-ONBOARD-05** [MANUAL]  
Each onboarding screen must have a visible "Back" action (except the first screen) and a clear primary action button.  
_Test: Navigate forward and backward through all 5 onboarding screens. Verify Back works on screens 2–5. Verify each screen has exactly one primary CTA._

---

### 8.7 Calibration

**AC-CAL-01** [AUTO]  
`CalibrationProfile` must be stored and retrieved correctly from `UserDefaults`.  
_Test: Create a mock profile with known `screenBoundaryGazeX` values. Encode to UserDefaults. Decode and assert values match exactly._

**AC-CAL-02** [AUTO]  
If stored `CalibrationProfile.monitorConfig` does not match the current `NSScreen` arrangement hash, `CalibrationManager` must flag the profile as invalid.  
_Test: Store a profile with a fake monitor hash. Call `CalibrationManager.isProfileValid()`. Assert returns `false`._

**AC-CAL-03** [MANUAL]  
Calibration dots must appear in the correct screen positions: far-left, center-left, center, center-right, far-right.  
_Test: Enter calibration mode. Verify 5 dots appear sequentially at positions matching the above description, one at a time, with a visible animation between them._

**AC-CAL-04** [MANUAL]  
Calibration overlay must be full-screen and block all underlying app interaction while active.  
_Test: Enter calibration mode. Try clicking the Dock, switching apps, or using the menu bar. All interactions must be blocked._

**AC-CAL-05** [MANUAL]  
Post-calibration gaze accuracy must meet AC-GAZE-03 (>= 85%).  
_Test: Run AC-GAZE-03 immediately after completing calibration._

**AC-CAL-06** [MANUAL]  
Users must be able to cancel calibration mid-session without corrupting the stored profile.  
_Test: Start calibration. Press Escape after the 2nd dot. Verify the previous valid profile is still intact and the app continues working._

---

### 8.8 Settings Panel

**AC-SETTINGS-01** [MANUAL]  
All settings changes must take effect immediately without requiring an app restart.  
_Test: Change dwell time from 400ms to 200ms in Settings. Without restarting, verify the faster dwell time is active (manually test switching speed)._

**AC-SETTINGS-02** [AUTO]  
Dwell time slider must enforce min=200ms and max=1000ms. Setting `dwellDuration` outside this range must clamp to bounds.  
_Test: Programmatically set `DwellController.dwellDuration = 0.05`. Assert it clamps to 0.2. Set `dwellDuration = 5.0`. Assert it clamps to 1.0._

**AC-SETTINGS-03** [MANUAL]  
"Launch at Login" toggle must correctly register/deregister the app using `SMAppService`.  
_Test: Enable "Launch at Login". Restart Mac. Verify GazeFocus appears in menu bar automatically. Disable it. Restart Mac. Verify it does not launch._

**AC-SETTINGS-04** [MANUAL]  
Settings panel must open as a floating panel that stays above all other windows but does not take focus away from the current app.  
_Test: While typing in VSCode, click "Settings…" in the GazeFocus menu. Settings panel must appear above VSCode. The cursor/focus in VSCode must remain where it was._

---

### 8.9 Error and Edge Cases

**AC-EDGE-01** [MANUAL]  
App must not crash when displays are connected or disconnected while tracking is active.  
_Test: With tracking running, connect an external display via HDMI/USB-C. Disconnect it. Repeat 3 times. App must remain running throughout._

**AC-EDGE-02** [MANUAL]  
App must not crash when another process requests camera access (e.g., FaceTime call starts) while GazeFocus is tracking.  
_Test: Start a FaceTime call while GazeFocus is running. GazeFocus must gracefully pause tracking (amber icon) and resume when FaceTime ends._

**AC-EDGE-03** [MANUAL]  
App must handle "single display" setup gracefully — no crashes, no infinite loops.  
_Test: Disconnect all external displays. Verify GazeFocus shows a "Single display detected" notice in the menu and disables tracking rather than crashing._

**AC-EDGE-04** [AUTO]  
`CursorEngine.sortedScreens` must return screens in left-to-right order regardless of how macOS reports them.  
_Test: Create mock `NSScreen` frames with X positions [1920, 0, 3840]. Assert sorted order is [0, 1920, 3840]._

**AC-EDGE-05** [MANUAL]  
If the user revokes camera permission while the app is running, the app must detect this within 5 seconds and show a red menu bar icon with a "Camera permission required" menu item.  
_Test: Grant camera permission. Start tracking. Go to System Settings and revoke camera permission. Within 5s, verify red icon and menu item appear._

---

### 8.10 Performance Baselines

**AC-PERF-01** [MANUAL]  
Cold launch time (from app icon click to menu bar icon visible) must be under 1.5 seconds.  
_Test: Measure with stopwatch 5 times. Average must be < 1.5s._

**AC-PERF-02** [MANUAL]  
Memory usage must stay below 80MB during normal tracking operation.  
_Test: Use Activity Monitor. Observe Real Memory for GazeFocus over 10 minutes of active use. Must stay below 80MB._

**AC-PERF-03** [AUTO]  
Vision pipeline processing time per frame must be under 50ms on Apple M1 or later.  
_Test: Add timing instrumentation around `VNSequenceRequestHandler.perform()`. Run 100 frames. Assert p95 latency < 50ms._

---

## 9. Known Constraints and Future Work

### 9.1 Current Constraints

| Constraint | Impact | Mitigation |
|---|---|---|
| Webcam gaze is 2D, not 3D | Poor accuracy for 3+ monitor setups | Support 3+ monitors via full calibration regression in v0.3 |
| Accuracy drops in poor lighting | False triggers at night | Ambient light check via `AVCaptureDevice.exposureISO`; warn user |
| Head movement affects gaze X | User must sit relatively still | Normalize gaze by face bounding box size (head distance proxy) |
| Accessibility permission is scary | Onboarding drop-off | Privacy-first copy, link to open-source code |
| Not available on App Store | Reduced discoverability | GitHub + direct DMG + Homebrew cask |

### 9.2 Future Work (v0.3+)

- **Full 3D gaze estimation** using head pose + iris position for pixel-accurate gaze coordinates, enabling in-screen scrolling via gaze
- **Tobii hardware support** as a precision mode upgrade
- **Gaze-to-app focus** — bring the focused app to front, not just the cursor
- **Gaze history heatmaps** — optional analytics showing where on screen the user spends attention
- **Accessibility mode** — designed for users with limited hand mobility (larger dwell zones, audio feedback)

---

## 10. Development Environment Setup

### 10.1 Required Tools

```bash
# Xcode 15+ (download from Mac App Store — required, ~8GB)
# After installing:
xcode-select --install    # Command-line tools

# Useful CLI tools
brew install create-dmg   # For building distribution DMG
brew install swiftlint    # Code style linter (optional but recommended)
```

### 10.2 Xcode Project Settings Checklist

```
Target Settings → General:
  ✓ Deployment Target: macOS 13.0
  ✓ Bundle Identifier: com.yourname.gazefocus

Target Settings → Signing & Capabilities:
  ✓ Team: Your Apple Developer account (free account works for local testing)
  ✓ Remove "App Sandbox" capability entirely (required for Accessibility API)
  ✓ Add "Hardened Runtime" capability
  ✓ Under Hardened Runtime → check "Camera" in Resource Access

Target Settings → Info:
  ✓ Add key: LSUIElement = YES
  ✓ Add key: NSCameraUsageDescription = "<your privacy text>"
```

### 10.3 Testing Without a Physical Second Monitor

Use macOS's built-in display mirroring or the free tool **Display Menu** to create a virtual second display. Alternatively, test with `NSScreen.screens` mocked in unit tests.

---

## 11. Appendix — Key Apple APIs Quick Reference

| API | Import | Purpose |
|---|---|---|
| `AVCaptureSession` | `AVFoundation` | Camera pipeline orchestration |
| `AVCaptureDevice` | `AVFoundation` | Camera device access and permission |
| `VNDetectFaceLandmarksRequest` | `Vision` | Face + eye landmark detection |
| `VNSequenceRequestHandler` | `Vision` | Performs Vision requests on video frames |
| `CGWarpMouseCursorPosition` | `CoreGraphics` | Move cursor without mouse events |
| `CGAssociateMouseAndMouseCursorPosition` | `CoreGraphics` | Sync hardware mouse position after warp |
| `NSScreen.screens` | `AppKit` | All connected display geometries |
| `NSStatusItem` | `AppKit` | Menu bar icon and menu |
| `AXIsProcessTrusted` | `ApplicationServices` | Check Accessibility permission |
| `SMAppService.mainApp` | `ServiceManagement` | Launch at login (macOS 13+) |

---

*Document version 1.0 — April 2026. Subject to revision as implementation reveals new constraints.*
