# GazeFocus — MVP & Ramp-Up Build Plan
### Companion plan to `gazefocus-technical-design.md`
**Version:** 1.0 | **Date:** 2026-04-23
**Status:** Source-of-truth task list for implementation

---

## 0. How to Read This Plan

This plan splits every feature, acceptance criterion, and component from the technical design doc into two executable phases:

- **MVP (v0.1)** — the thinnest possible slice that delivers the magical moment: *look at a screen, the cursor goes there.* A new user on a two-display Apple Silicon Mac can install, onboard, calibrate, and use the app without the authors' help. No polish that isn't load-bearing.
- **Ramp-Up (v0.2 → v0.3+)** — everything that turns the MVP into a product: polish, robustness, distribution, settings surface area, accessibility, 3+ monitor support, and future work.

Tasks are numbered and self-contained. Each task lists:
- **What** — concrete deliverable, filenames, and API calls
- **Why** — load-bearing rationale (only when non-obvious)
- **Depends on** — upstream task IDs that must ship first
- **Verifies** — acceptance criteria IDs from the tech design doc that this task unlocks
- **Done when** — observable, testable completion bar

Conventions used below:
- `[AUTO]` test means an XCTest target; `[MANUAL]` means a written QA script in `GazeFocusTests/Manual/`.
- File paths are anchored at the project structure in §6 of the tech design.
- All `Swift` API names, framework classes, and Info.plist keys are reproduced verbatim from the tech design — do not substitute.
- No task adds features beyond the tech design doc. If a task looks unfamiliar, re-check §5 of the tech design before coding.

Principle of restraint: do not add error handling, logging, abstractions, or config surface area that isn't called out here. The tech design is tight — keep the code the same way.

---

## 1. MVP (v0.1) — The Magical Moment

**Definition of MVP done:** On a two-display Apple Silicon Mac running macOS 13+, a new user can (a) launch the app, (b) grant Camera + Accessibility permission through a guided flow, (c) run a 5-dot calibration, and (d) have the cursor warp to the screen they're looking at with ≥85% classification accuracy and <3 false triggers per 5 minutes of normal reading. The app runs as a menu bar utility only, can be paused/resumed via a global shortcut, and can be quit cleanly.

**Out of MVP scope (deferred to Ramp-Up):** Settings panel, dwell progress ring overlay, full menu bar icon state machine (we ship only 3 icon states — active, paused, permission-missing), launch at login, signed DMG distribution, 3+ monitor support, screen-recording permission, monitor-config-change recalibration prompt, animated onboarding illustrations, VoiceOver polish, battery pause, camera frame-rate picker.

### MVP-M0 — Repository & Xcode Project Bootstrap

**M0.1 — Scaffold project via xcodegen**
- **What:** Install `xcodegen` (`brew install xcodegen`). Create `project.yml` at repo root declaring: name `GazeFocus`, bundle ID `com.shubhamdesale.gazefocus`, Team ID `38M5GTQP8K`, deployment target macOS 13.0, two targets (app + XCTest), Info.plist keys, entitlements file, Hardened Runtime on, App Sandbox absent. Run `xcodegen generate`. Add `.xcodeproj/` and `.xcworkspace/` to `.gitignore`.
- **Why:** Reproducible and diff-friendly. The `.xcodeproj` binary format is notoriously unreviewable in PRs; `project.yml` is the source of truth.
- **Depends on:** —
- **Done when:** `xcodegen generate` produces `GazeFocus.xcodeproj`, `xcodebuild -scheme GazeFocus build` succeeds, and `.xcodeproj` is absent from git.

**M0.2 — Remove default window, set activation policy to accessory**
- **What:** Delete the default storyboard/window; in `AppDelegate.applicationDidFinishLaunching` call `NSApp.setActivationPolicy(.accessory)`. Remove `Main.storyboard` reference from Info.plist (`NSMainStoryboardFile`).
- **Why:** Menu-bar-only apps must not show in the Dock or App Switcher.
- **Depends on:** M0.1
- **Verifies:** AC-MENU-01
- **Done when:** Running the app produces no window and no Dock icon.

**M0.3 — Configure Info.plist keys**
- **What:** Add to `GazeFocus-Info.plist`:
  - `LSUIElement` = `YES`
  - `NSCameraUsageDescription` = verbatim string from tech design §5.6 (the "All processing is done on-device…" copy)
  - `LSMinimumSystemVersion` = `13.0`
- **Depends on:** M0.2
- **Verifies:** AC-MENU-01

**M0.4 — Configure Signing & Capabilities**
- **What:** In target settings → Signing & Capabilities: set Team to the developer's Apple ID; **remove the App Sandbox capability entirely**; add Hardened Runtime; under Hardened Runtime check *Camera* in Resource Access.
- **Why:** Accessibility API (`CGWarpMouseCursorPosition`) cannot run in a sandboxed app (tech design §4.2).
- **Depends on:** M0.1
- **Done when:** Build succeeds with Hardened Runtime on and App Sandbox absent.

**M0.5 — Create directory scaffold**
- **What:** Create empty Swift files matching the project structure from tech design §6 — `App/AppDelegate.swift`, `Core/{CameraManager,GazeDetector,GazeSmoother,DwellController,CursorEngine}.swift`, `Calibration/{CalibrationManager,CalibrationViewController,CalibrationProfile}.swift`, `UI/{MenuBarController,OnboardingViewController}.swift`, `Utils/{PermissionsManager,DisplayGeometry}.swift`. Do **not** create `SettingsView.swift`, `DwellRingOverlay.swift` — those are Ramp-Up.
- **Depends on:** M0.1
- **Done when:** Empty scaffolded files compile; project navigator matches tech design §6 minus deferred files.

**M0.6 — Add SwiftLint (optional, recommended)**
- **What:** `brew install swiftlint`; add a `.swiftlint.yml` at repo root with default rules minus `line_length` (raise to 140). Add a Run Script build phase.
- **Depends on:** M0.1
- **Done when:** `swiftlint` runs clean on the scaffold.

---

### MVP-M1 — Menu Bar Foundation

**M1.1 — Implement `MenuBarController`**
- **What:** In `UI/MenuBarController.swift`, create `class MenuBarController` that owns an `NSStatusItem` (`.squareLength`) with a default SF Symbol `eye` icon. Expose `setIcon(state:)` taking an enum `IconState { active, paused, permissionMissing }`. Only map these three states for MVP — defer `lowConfidence` and `calibrating` to ramp-up.
- **Depends on:** M0.5
- **Verifies:** AC-MENU-02 (partial — 3 of 5 states)

**M1.2 — Wire menu bar in AppDelegate**
- **What:** In `AppDelegate.applicationDidFinishLaunching`, instantiate `MenuBarController` and retain it as a property. Build an `NSMenu` with items: `"GazeFocus — Active"` (disabled title row), separator, `"Pause (⌥⌘G)"`, `"Recalibrate…"`, separator, `"Quit GazeFocus"`. Do **not** include `"Settings…"` in MVP — defer.
- **Depends on:** M1.1
- **Verifies:** AC-MENU-01, AC-MENU-05

**M1.3 — Menu state title updates**
- **What:** The first menu item's title must reflect current state: `"GazeFocus — Active"` / `"GazeFocus — Paused"` / `"GazeFocus — Permission Required"`. Rebuild or update the `NSMenuItem.title` on state change; update within 1s of the trigger.
- **Depends on:** M1.2
- **Verifies:** AC-MENU-05

**M1.4 — Global shortcut for pause (⌥⌘G)**
- **What:** Register a local event monitor via `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` for `g` with `.option + .command`. Toggle a `TrackingCoordinator.isPaused` bool. The menu item's title and icon must both reflect the new state within 1s.
- **Why:** A single keyboard fallback is mandatory for the MVP — when gaze misfires, the user must be able to stop instantly without clicking.
- **Depends on:** M1.3
- **Verifies:** AC-MENU-05

---

### MVP-M2 — Permissions

**M2.1 — `PermissionsManager` API**
- **What:** In `Utils/PermissionsManager.swift`, implement:
  - `static var cameraStatus: AVAuthorizationStatus`
  - `static func requestCamera(completion: @escaping (Bool) -> Void)` wrapping `AVCaptureDevice.requestAccess(for: .video)`
  - `static var hasAccessibility: Bool` calling `AXIsProcessTrusted()`
  - `static func openAccessibilityPrefs()` opening `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
  - `static func openCameraPrefs()` opening the Camera pane
- **Depends on:** M0.5

**M2.2 — Poll for revocation**
- **What:** Start a 2-second repeating `Timer` on the main run loop from `AppDelegate` that calls `PermissionsManager.cameraStatus` and `PermissionsManager.hasAccessibility`. On revocation, pause tracking, set icon to `permissionMissing`, and update menu title. Must detect revocation within 5 seconds.
- **Depends on:** M2.1, M1.3
- **Verifies:** AC-EDGE-05

---

### MVP-M3 — Camera Pipeline

**M3.1 — Implement `CameraManager`**
- **What:** In `Core/CameraManager.swift`, implement the class exactly as specified in tech design §5.1 (AVCaptureSession with `.low` preset, dedicated `videoQueue`, 15fps via `activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 15)`, BGRA pixel format, `onFrame` closure callback).
- **Depends on:** M0.5

**M3.2 — Gate camera start on permission**
- **What:** `CameraManager.start()` must return early without calling `session.startRunning()` if `PermissionsManager.cameraStatus != .authorized`. Provide a separate `startIfPermitted()` convenience.
- **Why:** Without this gate, MVP fails AC-CAM-01.
- **Depends on:** M3.1, M2.1
- **Verifies:** AC-CAM-01

**M3.3 — Handle interruption (camera taken by another app)**
- **What:** Observe `AVCaptureSession.wasInterruptedNotification` and `.interruptionEndedNotification`. On interruption, set icon to `permissionMissing` (MVP has no `lowConfidence` state) and pause tracking. On resume, restore the prior state.
- **Why:** FaceTime calls, Zoom, Photo Booth will grab the camera. Crashing or spinning is unacceptable.
- **Depends on:** M3.1, M1.3
- **Verifies:** AC-EDGE-02

**M3.4 — Frame-rate enforcement test [AUTO]**
- **What:** Write `GazeFocusTests/CameraManagerTests.swift` that counts frames received over 2s and asserts ≤32.
- **Depends on:** M3.1
- **Verifies:** AC-CAM-02

**M3.5 — Session lifecycle test [AUTO]**
- **What:** In `CameraManagerTests.swift`, stub `AVCaptureDevice.authorizationStatus` (via a protocol-based indirection added in M3.2) to `.denied` and assert `session.isRunning == false`.
- **Depends on:** M3.2
- **Verifies:** AC-CAM-01

---

### MVP-M4 — Gaze Detection

**M4.1 — Implement `GazeDetector`**
- **What:** In `Core/GazeDetector.swift`, implement `struct GazeResult` and `class GazeDetector` exactly per tech design §5.2. Use `VNSequenceRequestHandler` retained on the instance (so sequential frames benefit from tracking). Reject `VNFaceObservation.confidence < 0.7`. Read `landmarks?.leftPupil.normalizedPoints.first?.x` as gaze X in [0,1].
- **Depends on:** M3.1

**M4.2 — Hook camera → detector on background queue**
- **What:** In a new `Core/TrackingCoordinator.swift`, create a single owner object that holds `CameraManager`, `GazeDetector`, `GazeSmoother`, and `DwellController`. The `CameraManager.onFrame` callback fires on `videoQueue`; it calls `GazeDetector.detect(...)` on the same queue. Results are smoothed, then the smoothed value is converted to a screen index and passed to `DwellController.update(...)`. Cursor warp (M6) must be dispatched back to the main queue.
- **Why:** §3.1 explicitly requires Vision off the main thread and warp on the main thread. Getting this wrong causes UI hangs and cursor jitter.
- **Depends on:** M4.1, M3.1
- **Verifies:** AC-CURSOR-01

**M4.3 — Diagnostics overlay (gated by hidden setting)**
- **What:** Build a borderless `NSPanel` that shows a red dot positioned at `gazeX * screenWidth`. Gate it behind a `UserDefaults` key `diagnosticsOverlayEnabled` (default `false`). Ship in release builds — in MVP the key is only toggleable via `defaults write com.shubhamdesale.gazefocus diagnosticsOverlayEnabled -bool true`. Ramp-Up R2 adds a Settings → Advanced toggle.
- **Why:** §7 Phase 1 calls this out as the essential development feedback mechanism. Keeping it in release (off by default) lets us field-debug accuracy complaints without shipping a custom build.
- **Depends on:** M4.2
- **Done when:** Toggling the defaults key on and relaunching shows a small red dot that slides left/right as the user looks around. Toggling off hides it with no residual window.

**M4.4 — Confidence & no-face unit tests [AUTO]**
- **What:** In `GazeFocusTests/GazeDetectorTests.swift`, feed a 320×240 gray `CVPixelBuffer` and assert `completion(nil)`. Feed a deliberately blurry face image (checked into `GazeFocusTests/Fixtures/blurry_face.png`) and assert `completion(nil)` when confidence < 0.7.
- **Depends on:** M4.1
- **Verifies:** AC-GAZE-01, AC-GAZE-02

**M4.5 — Manual accuracy script [MANUAL]**
- **What:** Create `GazeFocusTests/Manual/AC-GAZE-03.md` describing the sit-60cm, 100-sample classification test. Include a toggle in debug builds that logs `screenIndex` classifications to stdout for tallying.
- **Depends on:** M4.2, M7 (calibration, since gaze must be calibrated before this passes)
- **Verifies:** AC-GAZE-03, AC-GAZE-04

---

### MVP-M5 — Smoothing & Dwell Control

**M5.1 — Implement `GazeSmoother`**
- **What:** In `Core/GazeSmoother.swift`, implement `struct GazeSmoother` with `alpha = 0.3` (hardcoded for MVP — no setting). Provide `mutating func smooth(_ rawX: CGFloat) -> CGFloat`.
- **Depends on:** M0.5

**M5.2 — Implement `DwellController`**
- **What:** In `Core/DwellController.swift`, implement `class DwellController` exactly per tech design §5.3. Default `dwellDuration = 0.4`. Expose `onScreenSwitch: ((Int) -> Void)?`. Clamp `dwellDuration` to [0.2, 1.0] in the setter.
- **Depends on:** M0.5

**M5.3 — Dwell tests [AUTO]**
- **What:** In `GazeFocusTests/DwellControllerTests.swift`, implement the three scenarios from AC-DWELL-01, -02, -03. Use `XCTWaiter` with explicit expected timelines. Add AC-DWELL-04 test for `GazeSmoother` convergence. Use a custom clock injected into `DwellController` (protocol `DwellClock`) so tests don't rely on real `Timer`.
- **Why:** Real `Timer`-based tests are flaky on CI. Inject a clock.
- **Depends on:** M5.2, M5.1
- **Verifies:** AC-DWELL-01, AC-DWELL-02, AC-DWELL-03, AC-DWELL-04

**M5.4 — Dwell clamp test [AUTO]**
- **What:** In `DwellControllerTests.swift`, set `dwellDuration = 0.05`; assert observed value == `0.2`. Set `dwellDuration = 5.0`; assert observed value == `1.0`.
- **Depends on:** M5.2
- **Verifies:** AC-SETTINGS-02 (the clamp itself; the slider UI is ramp-up)

**M5.5 — Manual false-trigger test [MANUAL]**
- **What:** Create `GazeFocusTests/Manual/AC-DWELL-05.md` describing the 5-minute reading test. Tester tallies unintended switches; target < 3.
- **Depends on:** M7 (calibration prerequisite)
- **Verifies:** AC-DWELL-05

---

### MVP-M6 — Cursor Warp

**M6.1 — Implement `CursorEngine`**
- **What:** In `Core/CursorEngine.swift`, implement `static func warpCursor(to: NSScreen)` and `static var sortedScreens` exactly per tech design §5.4. Add a `precondition(Thread.isMainThread, "CursorEngine must be called on main thread")` at the top of `warpCursor`.
- **Depends on:** M0.5
- **Verifies:** AC-CURSOR-01

**M6.2 — Sorted-screens test [AUTO]**
- **What:** In `GazeFocusTests/CursorEngineTests.swift`, introduce a protocol `ScreenProvider` (`var screens: [DisplayFrame]`) injected into `CursorEngine`. Feed frames with `minX` values `[1920, 0, 3840]` and assert the sort result is `[0, 1920, 3840]`.
- **Depends on:** M6.1
- **Verifies:** AC-EDGE-04

**M6.3 — Main-thread enforcement test [AUTO]**
- **What:** Write a test that calls `warpCursor` from `DispatchQueue.global()` and asserts a `preconditionFailure` via `XCTAssertCrashes` helper, OR use a feature flag to downgrade the precondition to a test-observable flag.
- **Depends on:** M6.1
- **Verifies:** AC-CURSOR-01

**M6.4 — Integration: screen index → warp**
- **What:** In `TrackingCoordinator`, subscribe to `DwellController.onScreenSwitch` and dispatch `CursorEngine.warpCursor(to: CursorEngine.sortedScreens[index])` on `DispatchQueue.main`.
- **Depends on:** M6.1, M5.2, M4.2

**M6.5 — Manual centering test [MANUAL]**
- **What:** `GazeFocusTests/Manual/AC-CURSOR-02.md` with the `NSScreen.frame.midX/midY` verification procedure.
- **Depends on:** M6.4
- **Verifies:** AC-CURSOR-02

**M6.6 — No-spurious-click test [MANUAL]**
- **What:** `GazeFocusTests/Manual/AC-CURSOR-03.md` — button at screen center; 10 warps; expect 0 activations. Verifies the `CGAssociateMouseAndMouseCursorPosition(1)` call does not re-inject phantom events.
- **Depends on:** M6.4
- **Verifies:** AC-CURSOR-03

---

### MVP-M7 — Calibration (5-Dot, Minimum Viable)

**M7.1 — Implement `CalibrationProfile`**
- **What:** In `Calibration/CalibrationProfile.swift`, implement the `Codable` struct per tech design §5.7. Add persistence helpers `static func load() -> CalibrationProfile?` and `func save()` using `UserDefaults.standard` under key `com.shubhamdesale.gazefocus.calibration`. Encode via `JSONEncoder`.
- **Depends on:** M0.5
- **Verifies:** AC-CAL-01

**M7.2 — Monitor config hash**
- **What:** Add `static func currentMonitorConfigHash() -> String` that takes `NSScreen.screens.sorted(by: minX)`, concatenates `"{id}:{frame.origin.x},{frame.origin.y},{frame.size.width},{frame.size.height}"` and SHA256s the result.
- **Depends on:** M7.1
- **Verifies:** AC-CAL-02 (hash is used in ramp-up for invalidation; MVP only needs the field populated)

**M7.3 — Calibration overlay UI**
- **What:** In `Calibration/CalibrationViewController.swift`, build a full-screen borderless `NSWindow` (level: `.screenSaver`, ignores mouse events only after setup completes) spanning the union of `NSScreen.screens.map { $0.frame }`. Draw 5 dots in sequence at normalized positions `[0.0, 0.25, 0.5, 0.75, 1.0]` of the total horizontal span, each at vertical center. Animate dot appearance with a 0.25s fade-in. Advance to next dot automatically after 2.0s of hold (30 frames at 15fps).
- **Depends on:** M3.1, M4.1
- **Verifies:** AC-CAL-03, AC-CAL-04

**M7.4 — Calibration capture logic**
- **What:** In `Calibration/CalibrationManager.swift`, for each dot, collect 30 raw gaze X samples from `GazeDetector`. Store the median as that dot's anchor. After all 5 dots, write `screenBoundaryGazeX` = `[anchor[1], anchor[3]]` (the center-left and center-right values mark the intra-screen-1-center and intra-screen-2-center gaze positions; the midpoint of those two becomes the dividing line). For MVP, derive a single dividing gaze X = `(anchor[2])` — the center dot's median. `screenBoundaryGazeX = [anchor[2]]` for 2-screen setups.
- **Why:** MVP targets 2-screen setups; one dividing gaze X is sufficient. Full N-boundary regression is ramp-up.
- **Depends on:** M7.3, M4.1, M7.1
- **Verifies:** AC-CAL-05 (combined with M4.5)

**M7.5 — Apply calibration in gaze → screen mapping**
- **What:** Replace the naive `min(Int(gazeX * CGFloat(screenCount)), screenCount - 1)` in `GazeDetector` (or a new `GazeClassifier` helper) with: `screenIndex = gazeX < profile.screenBoundaryGazeX[0] ? 0 : 1`. If no profile exists, fall back to the naive `0.5` midpoint split.
- **Depends on:** M7.4
- **Verifies:** AC-GAZE-03 (dependent on calibration)

**M7.6 — Cancel calibration safely**
- **What:** Calibration overlay accepts ESC key → dismisses overlay without mutating the stored profile. If no prior profile existed, no profile is written.
- **Depends on:** M7.3
- **Verifies:** AC-CAL-06

**M7.7 — Calibration entry points**
- **What:** Menu item `"Recalibrate…"` opens the calibration overlay. On first launch, the onboarding flow (M8) triggers it automatically as its last step.
- **Depends on:** M7.3, M1.2

**M7.8 — Persistence round-trip test [AUTO]**
- **What:** `CalibrationTests.swift` — create profile with known values, save, clear in-memory reference, reload, assert equality.
- **Depends on:** M7.1
- **Verifies:** AC-CAL-01

---

### MVP-M8 — Onboarding (Functional, Unpolished)

**M8.1 — First-launch detection**
- **What:** Use a `UserDefaults` flag `hasCompletedOnboarding`. On `applicationDidFinishLaunching`, if the flag is absent, show onboarding.
- **Depends on:** M1.2
- **Verifies:** AC-ONBOARD-01

**M8.2 — Onboarding window**
- **What:** In `UI/OnboardingViewController.swift`, build a single 640×480 `NSWindow` (titled, non-resizable, centered) hosting a stack of view controllers advanced via a Next button. No SwiftUI in MVP — straight AppKit to minimize surface area.
- **Depends on:** M0.5

**M8.3 — Onboarding screens (5, minimal copy only)**
- **What:** Implement these 5 view controllers, each with plain text + one primary button. **Back button not required for MVP.** Defer animated illustrations, numbered screenshot guides, and per-screen Back to ramp-up.
  1. **Welcome** — Title: "GazeFocus", body: "Look at a screen. Your cursor follows.", button: "Get Started".
  2. **How it works** — Body: "GazeFocus watches your eyes using the webcam and moves the cursor to the screen you're looking at. Everything happens on your Mac. No video ever leaves your device." Button: "Continue".
  3. **Camera permission** — Body: privacy copy from §5.6. Button triggers `PermissionsManager.requestCamera`. On denial, show inline error with a button that opens camera prefs.
  4. **Accessibility permission** — Body: 3 plain-text numbered steps ("1. Click Open System Settings. 2. Find GazeFocus in the list. 3. Toggle the switch on."). Button opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. Poll `AXIsProcessTrusted()` every 1s; auto-advance when true.
  5. **Calibration** — Body: "We'll show 5 dots. Look at each one until it disappears. Takes 15 seconds." Button: "Start Calibration" → opens calibration overlay (M7). On completion, set `hasCompletedOnboarding = true` and close window.
- **Depends on:** M8.2, M2.1, M7.3
- **Verifies:** AC-ONBOARD-01, AC-ONBOARD-02, AC-ONBOARD-03 (MVP-minimal version), AC-ONBOARD-04

**M8.4 — Camera denial recovery path**
- **What:** On screen 3, if the user denies, show the error copy and a button "Open System Settings → Camera" that calls `PermissionsManager.openCameraPrefs()`. Poll `cameraStatus` every 1s; when it flips to `.authorized`, auto-advance.
- **Depends on:** M8.3, M2.1
- **Verifies:** AC-ONBOARD-02

---

### MVP-M9 — Integration, Single-Display Guard, and Cleanup

**M9.1 — Single-display handling**
- **What:** In `TrackingCoordinator`, check `NSScreen.screens.count`. If `< 2`, pause tracking, set menu title to `"GazeFocus — Single Display"`, and show a plain `NSMenuItem` with that text. No crash path.
- **Depends on:** M1.3, M6.1
- **Verifies:** AC-EDGE-03

**M9.2 — Display arrangement change listener**
- **What:** Register for `NSApplication.didChangeScreenParametersNotification`. On fire, re-evaluate single-vs-multi-display state (M9.1) and resume/pause as appropriate. Do **not** invalidate the calibration profile in MVP — that's ramp-up.
- **Depends on:** M9.1
- **Verifies:** AC-EDGE-01

**M9.3 — Shutdown cleanup**
- **What:** On `applicationWillTerminate`, stop the `AVCaptureSession`, invalidate any active `Timer`s, and close the debug overlay window if present.
- **Depends on:** M3.1, M4.3

**M9.4 — Happy-path end-to-end manual test [MANUAL]**
- **What:** `GazeFocusTests/Manual/MVP-E2E.md` — full script: fresh install → onboarding → calibration → 5 minutes of use. Tallies accuracy and false triggers against ACs.
- **Depends on:** M8.3, M7.7
- **Verifies:** AC-ONBOARD-04, AC-GAZE-03, AC-DWELL-05

---

### MVP-M10 — Local Build & Developer Docs

**M10.1 — README for contributors**
- **What:** Create `README.md` at repo root with: (a) tech design link, (b) this plan link, (c) build instructions (Xcode 15+, open `.xcodeproj`, ⌘R), (d) test instructions (⌘U), (e) required tools (`brew install swiftlint` optional), (f) how to reset onboarding (`defaults delete com.shubhamdesale.gazefocus hasCompletedOnboarding`), (g) how to reset calibration (same key).
- **Depends on:** M0.1

**M10.2 — Unsigned local `.app` build**
- **What:** Document in the README: Xcode → Product → Archive → Developer ID (or Personal Team for local-only). Do not create a DMG in MVP. Hand-install by copying `.app` to `/Applications`.
- **Depends on:** M0.4
- **Note:** Signed DMG distribution is a Ramp-Up task (R5).

**M10.3 — Reset scripts**
- **What:** Add `scripts/reset-onboarding.sh` and `scripts/reset-calibration.sh` invoking `defaults delete` for the respective keys. Useful during MVP QA to re-run onboarding without reinstalling.
- **Depends on:** M7.1, M8.1

---

### MVP — Acceptance Coverage Summary

| Tech-design AC | Covered by MVP task(s) | Notes |
|---|---|---|
| AC-CAM-01 | M3.5 | |
| AC-CAM-02 | M3.4 | |
| AC-CAM-03 | — | Ramp-Up R7.1 |
| AC-CAM-04 | — | Ramp-Up R7.2 |
| AC-GAZE-01 | M4.4 | |
| AC-GAZE-02 | M4.4 | |
| AC-GAZE-03 | M4.5 + M7 | |
| AC-GAZE-04 | M4.5 | |
| AC-GAZE-05 | — | Partial via M3.3 (interruption); full low-confidence icon state deferred to R1.1 |
| AC-DWELL-01..04 | M5.3 | |
| AC-DWELL-05 | M5.5 | |
| AC-CURSOR-01 | M6.1, M6.3 | |
| AC-CURSOR-02 | M6.5 | |
| AC-CURSOR-03 | M6.6 | |
| AC-CURSOR-04 | — | Ramp-Up R7.3 (instrument profile) |
| AC-MENU-01 | M0.2, M1.2 | |
| AC-MENU-02 | M1.1 (3 of 5 states); full icon state machine R1.1 | |
| AC-MENU-03 | — | Ramp-Up R3 (VoiceOver) |
| AC-MENU-04 | — | Ramp-Up R2 (Settings panel) |
| AC-MENU-05 | M1.3, M1.4 | |
| AC-ONBOARD-01 | M8.1 | |
| AC-ONBOARD-02 | M8.4 | |
| AC-ONBOARD-03 | M8.3 (plain-text steps; animated screenshots deferred R4.1) | |
| AC-ONBOARD-04 | M9.4 | |
| AC-ONBOARD-05 | — | Ramp-Up R4.2 (Back buttons) |
| AC-CAL-01 | M7.8 | |
| AC-CAL-02 | — | Ramp-Up R6 |
| AC-CAL-03 | M7.3 | |
| AC-CAL-04 | M7.3 | |
| AC-CAL-05 | M7 + M4.5 | |
| AC-CAL-06 | M7.6 | |
| AC-SETTINGS-01..04 | Partial (clamp via M5.4); UI deferred R2 | |
| AC-EDGE-01 | M9.2 | |
| AC-EDGE-02 | M3.3 | |
| AC-EDGE-03 | M9.1 | |
| AC-EDGE-04 | M6.2 | |
| AC-EDGE-05 | M2.2 | |
| AC-PERF-01..03 | — | Ramp-Up R7 |

---

## 2. Ramp-Up (v0.2 → v0.3+)

Ramp-up is grouped by workstream. Workstreams inside a phase (R1–R9) are **independent** and can be parallelized by separate agents; tasks within a workstream are sequential.

### R1 — Menu Bar State Machine & Low-Confidence Handling

**R1.1 — Expand icon state enum**
- **What:** Extend `IconState` to the full 5 states from tech design §5.5 table: `active (eye)`, `paused (eye.slash)`, `lowConfidence (eye.trianglebadge.exclamationmark, orange)`, `permissionMissing (exclamationmark.triangle, red)`, `calibrating (scope, blue)`. Use `NSImage.symbolConfiguration(hierarchicalColor:)` for tinting.
- **Verifies:** AC-MENU-02 (full)

**R1.2 — Low-confidence detection**
- **What:** In `GazeDetector`, emit a `lowConfidenceStreak` counter when Vision returns `nil` or confidence < 0.7 for consecutive frames. After 30 consecutive low-confidence frames (~2s at 15fps), set icon to `lowConfidence`. First good detection clears it.
- **Verifies:** AC-GAZE-05

**R1.3 — Calibrating state**
- **What:** While calibration overlay is active, set icon to `calibrating`.
- **Depends on:** R1.1, MVP-M7.3

---

### R2 — Settings Panel

**R2.1 — SwiftUI `SettingsView`**
- **What:** Build `UI/SettingsView.swift` with the full settings table from tech design §5.8 (dwell time slider 200–1000ms, gaze sensitivity slider 0.1–1.0, launch at login toggle, show dwell progress ring toggle, pause when on battery toggle, camera frame rate picker 10/15/30fps). Add an **Advanced** disclosure section with a `Show diagnostics overlay` toggle bound to `diagnosticsOverlayEnabled` (MVP-M4.3). Bind all controls to a `SettingsStore: ObservableObject` backed by `UserDefaults` with `@AppStorage` where possible.

**R2.2 — `NSPanel` host**
- **What:** Host the SwiftUI view inside an `NSPanel` with `.nonactivatingPanel`, `.titled`, `.closable`. Floats above other windows without stealing focus. Open latency < 300ms.
- **Verifies:** AC-MENU-04, AC-SETTINGS-04

**R2.3 — Menu entry**
- **What:** Add `"Settings…"` menu item (keyboard equivalent `,`) between Recalibrate and Quit.

**R2.4 — Live-apply all settings**
- **What:** `SettingsStore` publishes changes; `TrackingCoordinator` subscribes. No restart required for any setting.
- **Verifies:** AC-SETTINGS-01

**R2.5 — Frame-rate picker plumbing**
- **What:** On picker change, `CameraManager` rebuilds `activeVideoMinFrameDuration` to `CMTimeMake(value: 1, timescale: selectedFps)` without tearing down the session (or restart the session if needed — ≤500ms reconfiguration).

**R2.6 — Sensitivity plumbing**
- **What:** Map "Gaze sensitivity" slider to `GazeSmoother.alpha` inversely (higher sensitivity → higher alpha → more responsive, less smooth). Clamp to [0.1, 0.9] to avoid degenerate cases.

**R2.7 — Settings test coverage [AUTO]**
- **What:** Unit tests for `SettingsStore` round-trip persistence; slider clamps.
- **Verifies:** AC-SETTINGS-02

---

### R3 — Accessibility & VoiceOver

**R3.1 — Menu VoiceOver labels**
- **What:** Set `NSMenuItem.accessibilityLabel` and `accessibilityHelp` for every menu item. Include keyboard equivalent in label.
- **Verifies:** AC-MENU-03

**R3.2 — SettingsView accessibility**
- **What:** Every control has a SwiftUI `.accessibilityLabel` and `.accessibilityValue`. Slider values announced in ms/percent.

**R3.3 — Onboarding accessibility**
- **What:** Each onboarding screen has a logical reading order. All buttons are keyboard-reachable with Tab. Use `.accessibilityAddTraits(.isHeader)` on titles.

**R3.4 — Calibration dot announcement**
- **What:** Each dot reads aloud its position ("Calibration dot 1 of 5, far left") via `NSAccessibility.post(element:, notification: .announcementRequested)`.

**R3.5 — VoiceOver walkthrough [MANUAL]**
- **What:** `GazeFocusTests/Manual/AC-MENU-03.md` — full VO walkthrough script.
- **Verifies:** AC-MENU-03

---

### R4 — Polished Onboarding

**R4.1 — Animated 3-panel "How it works" illustration**
- **What:** Replace plain-text screen 2 with a 3-panel `CAAnimation`-driven illustration (Lottie optional): head turning left → cursor sliding left; head turning right → cursor sliding right; head centered → cursor centered. Each panel 1.2s loop.

**R4.2 — Back buttons**
- **What:** Add a Back button on screens 2–5. Screen 1 has no Back. Preserve state when navigating backward (e.g., don't re-request camera permission).
- **Verifies:** AC-ONBOARD-05

**R4.3 — Numbered screenshot guide for Accessibility permission**
- **What:** Replace screen 4's text steps with inline screenshots (PNG assets in `Resources/Onboarding/`) showing System Settings → Privacy & Security → Accessibility → toggle. At least 2 numbered callouts with arrows.
- **Verifies:** AC-ONBOARD-03 (full)

**R4.4 — Privacy reassurance copy audit**
- **What:** Security-focused copy review with the "All processing is on-device, nothing leaves your Mac" guarantee prominent on screens 1, 3, and in the app description metadata.

**R4.5 — Onboarding timing test [MANUAL]**
- **What:** Run AC-ONBOARD-04 with a fresh user; target < 3 minutes to first gaze-triggered switch.

---

### R5 — Distribution & Launch-at-Login

**R5.1 — Developer ID signing**
- **What:** Purchase/configure an Apple Developer ID ($99/yr). Add `CODE_SIGN_IDENTITY` and automatic signing in Xcode. Verify `codesign --verify --deep --strict GazeFocus.app` returns success.

**R5.2 — Notarization**
- **What:** Script a `notarize.sh` that runs `xcrun notarytool submit` with stored keychain credentials, then `stapler staple`. Document the Apple notarization profile requirement (app-specific password or API key).

**R5.3 — DMG build**
- **What:** `brew install create-dmg`. Create `scripts/build-dmg.sh` that archives the app, codesigns, notarizes, staples, then runs `create-dmg` with a branded background image (asset in `Resources/Distribution/dmg-bg.png`), `Applications` symlink, and volume icon.

**R5.4 — Launch at login**
- **What:** Implement in `Utils/LoginItemManager.swift` using `SMAppService.mainApp.register()` / `unregister()`. Bind to the "Launch at Login" toggle in SettingsView.
- **Verifies:** AC-SETTINGS-03

**R5.5 — Launch-at-login QA [MANUAL]**
- **What:** `GazeFocusTests/Manual/AC-SETTINGS-03.md` — toggle on, reboot, verify; toggle off, reboot, verify.

**R5.6 — GitHub release workflow**
- **What:** GitHub Actions workflow that builds, signs (via encrypted certificate in secrets), notarizes, and attaches the DMG to a release. Optional: Homebrew cask formula.

---

### R6 — Calibration Robustness

**R6.1 — Monitor-config change detection**
- **What:** On `didChangeScreenParametersNotification`, compute `currentMonitorConfigHash()`; if it differs from stored `CalibrationProfile.monitorConfig`, mark profile invalid and show a non-blocking notification: "Monitor setup changed — recalibrate for best accuracy."
- **Verifies:** AC-CAL-02

**R6.2 — Profile-invalidation test [AUTO]**
- **What:** `CalibrationTests.swift` — store profile with fake hash; call `CalibrationManager.isProfileValid()`; assert false.
- **Verifies:** AC-CAL-02

**R6.3 — Dwell progress ring overlay**
- **What:** `UI/DwellRingOverlay.swift` — borderless `NSPanel` at the pending-screen's estimated gaze point, showing a `CAShapeLayer` ring that fills in `dwellDuration` seconds. Hides 200ms after switch fires or cancels. Gated by the "Show dwell progress ring" setting.

**R6.4 — Calibration quality score**
- **What:** During calibration, compute gaze-sample variance per dot. If any dot's variance > threshold (e.g., 0.05), show "Calibration quality: Fair — consider recalibrating with better lighting." post-save.

**R6.5 — 3+ monitor support via piecewise regression**
- **What:** Extend `CalibrationProfile.screenBoundaryGazeX` to `N-1` boundaries for N screens. Add a 7- or 9-dot calibration that scales dots by `NSScreen.screens.count`. Classifier becomes a binary search over boundaries.
- **Why:** Tech design §9.1 lists this as a constraint; tech design §5.2 notes the 2D method "works well for 2-monitor setups" and points to full regression for 3+. This is the v0.3 feature.

---

### R7 — Performance & Energy

**R7.1 — CPU baseline enforcement [MANUAL]**
- **What:** `GazeFocusTests/Manual/AC-CAM-03.md` — Activity Monitor procedure, 60s observation, fail if > 10% on M-series.
- **Verifies:** AC-CAM-03

**R7.2 — Energy impact check [MANUAL]**
- **What:** `GazeFocusTests/Manual/AC-CAM-04.md` — 30-minute run; verify absence from Battery → "Significant Energy."
- **Verifies:** AC-CAM-04

**R7.3 — Latency profile [MANUAL + AUTO hybrid]**
- **What:** Add `os_signpost` around dwell-fire → warp-call boundary. Instruments Time Profiler template committed at `GazeFocusTests/Manual/latency.tracetemplate`. Also write `PerformanceTests.swift` that runs 100 synthetic frames through `VNSequenceRequestHandler.perform` and asserts p95 < 50ms.
- **Verifies:** AC-CURSOR-04, AC-PERF-03

**R7.4 — Cold launch time [MANUAL]**
- **What:** `GazeFocusTests/Manual/AC-PERF-01.md` — 5 timed launches, average < 1.5s.
- **Verifies:** AC-PERF-01

**R7.5 — Memory baseline [MANUAL]**
- **What:** `GazeFocusTests/Manual/AC-PERF-02.md` — 10 minutes of tracking, Activity Monitor real memory < 80MB.
- **Verifies:** AC-PERF-02

**R7.6 — Battery pause setting**
- **What:** Bind "Pause when on battery" toggle (from R2.1) to `IOPowerSources`-based observation. On AC unplug, pause tracking automatically; on replug, resume.

---

### R8 — Resilience & Edge Cases (Remaining)

**R8.1 — Display hot-plug stress test [MANUAL]**
- **What:** `GazeFocusTests/Manual/AC-EDGE-01.md` — 3 connect/disconnect cycles with tracking active. Verify no crash, calibration invalidation, resume tracking.
- **Verifies:** AC-EDGE-01 (full)

**R8.2 — Low-light detection**
- **What:** Read `AVCaptureDevice.exposureISO`; if sustained > threshold for 10s, show an in-menu notice: "Low light detected — accuracy may drop." Do **not** block tracking.

**R8.3 — Head-distance normalization**
- **What:** Scale `rawGazeX` by `VNFaceObservation.boundingBox.width` to compensate for the user leaning closer/further. Document the coefficient tuning in `GazeDetector.swift`.

**R8.4 — Crash reporting (optional)**
- **What:** Integrate a lightweight, privacy-respecting crash reporter (e.g., Bugsnag free tier, or Apple's built-in `.crash` log capture). Disable by default; opt-in via Settings → Advanced.

---

### R9 — Future Work (v0.3+)

**R9.1 — Full 3D gaze estimation**
- **What:** Implement head-pose + iris-vector 3D gaze. Requires `VNDetectFaceRectanglesRequest` + `VNDetectFaceCaptureQualityRequest` + a calibrated affine transform from gaze vector → screen point. Scoped separately; not a single task.

**R9.2 — Tobii precision mode**
- **What:** If a Tobii Eye Tracker is plugged in, use its SDK as the gaze source instead of the webcam. Hot-swap at runtime.

**R9.3 — Gaze-to-app focus**
- **What:** In addition to warping the cursor, call `NSRunningApplication(processIdentifier:)?.activate(options: .activateIgnoringOtherApps)` for the frontmost app on the target screen.

**R9.4 — Gaze history heatmaps**
- **What:** Optional, opt-in analytics (all local) that logs gaze-to-screen distribution and renders a weekly heatmap. No network, no telemetry.

**R9.5 — Accessibility mode**
- **What:** Larger dwell zones, audio tick feedback on screen switch, longer dwell defaults. Target users with limited hand mobility.

---

## 3. Ramp-Up Sequencing & Parallelization Guide

| Agent | Can own in parallel | Blockers |
|---|---|---|
| Agent A | R1 (icon states), R3 (VoiceOver) | MVP complete |
| Agent B | R2 (Settings panel), R2 plumbing into core | MVP complete |
| Agent C | R4 (Polished onboarding) | MVP complete; may share copy with R3 |
| Agent D | R5 (Distribution + launch-at-login) | R2 for the Launch-at-Login setting UI |
| Agent E | R6 (Calibration robustness) | MVP complete; R2 (settings) for ring toggle |
| Agent F | R7 (Performance) | MVP complete |
| Agent G | R8 (Edge cases) | MVP complete |
| Agent H | R9 (Future work) | All of v0.2 shipped |

Recommended v0.2 cut line: **R1 + R2 + R4 + R5 + R6.1–R6.3 + R7.1–R7.5**. This is the first "shippable to friends" build.
Recommended v0.3 cut line: **R6.5 (3+ monitors) + R7.6 + R8 + selective R9**.

---

## 4. Non-Goals (Do Not Build)

Listed explicitly so agents don't drift:
- Cloud sync of calibration profiles
- **Telemetry, analytics, or phone-home of any kind — hard rule, no exceptions.** This includes "anonymous usage stats," "performance metrics to improve the product," A/B testing hooks, and third-party SDKs that exfiltrate anything. The only network-adjacent code allowed is a user-initiated "Check for updates" (post-v0.3, explicit opt-in). Crash reporting (R8.4) is backlog-only and, if ever added, must be opt-in and disabled by default.
- Mac App Store distribution (tech design §4.2 forbids)
- Windows/Linux port
- iOS/iPadOS companion
- A custom-trained ML model for gaze — Apple Vision is sufficient for MVP and R9.1 extensions
- Multi-user profiles within one Mac account
- Per-app behavior rules (e.g., "don't switch while in Zoom") — revisit post-v0.3
- Any UI chrome (animated icons, particle effects, haptics) not called out in the tech design

---

## 5. Decisions Locked & Remaining Open Questions

**Decided (2026-04-23):**
- **App icon:** Placeholder for MVP (SF Symbol `eye` rendered to 1024×1024 PNG at `Resources/AppIcon.appiconset/`). Real icon is a prerequisite for R5 distribution.
- **Diagnostics overlay:** Ships in release, default off. Toggled via `defaults write` in MVP; Settings → Advanced toggle lands in R2.1.
- **Crash reporting:** Backlog. R8.4 stays tagged optional and will not be picked up without an explicit go-ahead.
- **Telemetry / analytics:** None, ever. Codified as a hard rule in §4 Non-Goals.

**Also decided (2026-04-23):**
- **Apple Developer Team ID:** `38M5GTQP8K`
- **Bundle identifier:** `com.shubhamdesale.gazefocus`
- **Project generation:** `xcodegen` from a checked-in `project.yml`. The `.xcodeproj` is a build artifact and is gitignored. Any agent or CI regenerates it with `xcodegen generate`.

**Still open:** none blocking MVP.

---

*Plan v1.0 — 2026-04-23. Revise as MVP implementation reveals constraints.*
