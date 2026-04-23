# GazeFocus

Eye-tracking multi-display focus switcher for macOS. Look at a screen — your cursor follows.

Menu bar utility. No extra hardware. Uses the built-in webcam and Apple's Vision framework. All processing is on-device; no video leaves the Mac.

## Status

MVP (v0.1). Two-display setups, 15 fps gaze pipeline, 5-dot calibration, menu-bar-only UI. Ramp-up features (settings panel, launch-at-login, signed DMG, polished onboarding, 3+ monitor support) are scoped in [`gazefocus-build-plan.md`](./gazefocus-build-plan.md).

## Documents

- [`gazefocus-technical-design.md`](./gazefocus-technical-design.md) — architecture, acceptance criteria, future work
- [`gazefocus-build-plan.md`](./gazefocus-build-plan.md) — exhaustive MVP + ramp-up task list

## Build

Prerequisites:

```bash
# Xcode 15+ (tested on Xcode 26.4.1)
brew install xcodegen
```

Generate the project and build:

```bash
xcodegen generate
xcodebuild -project GazeFocus.xcodeproj -scheme GazeFocus -configuration Debug build
```

MVP builds are ad-hoc signed (no Apple Developer certificate needed). The Team ID `38M5GTQP8K` is baked into `project.yml` and activates once a real Developer ID cert is in the keychain — that's the Ramp-Up R5 step.

## Run

After build, the app lives under Xcode's DerivedData:

```bash
open ~/Library/Developer/Xcode/DerivedData/GazeFocus-*/Build/Products/Debug/GazeFocus.app
```

The app has no Dock icon and no main window — look for the `eye` SF Symbol in the menu bar.

## Test

```bash
xcodebuild -project GazeFocus.xcodeproj -scheme GazeFocus test
```

The automated suite covers: camera pipeline auth + frame-rate cap, gaze classifier boundaries, dwell state machine (with injected clock), cursor-engine sort + thread checks, and calibration persistence + hash + profile-aware classification.

Manual test scripts are in [`GazeFocusTests/Manual/`](./GazeFocusTests/Manual/). The full MVP end-to-end walkthrough is in [`MVP-E2E.md`](./GazeFocusTests/Manual/MVP-E2E.md).

## Diagnostics

A red-dot overlay that reflects the live raw gaze X can be toggled on without rebuilding:

```bash
defaults write com.shubhamdesale.gazefocus diagnosticsOverlayEnabled -bool true
# relaunch the app
```

Disable:

```bash
defaults delete com.shubhamdesale.gazefocus diagnosticsOverlayEnabled
```

In DEBUG builds, enabling the overlay also prints one `gaze screen=N x=… conf=…` line per frame to stdout. Useful for tallying AC-GAZE-03 accuracy runs.

A Settings → Advanced toggle for this lands in Ramp-Up R2.1.

## Reset

Re-run onboarding from scratch (wipes the "has completed" flag):

```bash
./scripts/reset-onboarding.sh
```

Clear the stored calibration profile (next launch behaves as if calibration never ran):

```bash
./scripts/reset-calibration.sh
```

## Project layout

```
GazeFocus/
├── App/              AppDelegate, Info.plist, entitlements
├── Core/             CameraManager, GazeDetector, GazeSmoother,
│                     DwellController, CursorEngine, TrackingCoordinator
├── Calibration/      CalibrationProfile, CalibrationViewController,
│                     CalibrationManager
├── UI/               MenuBarController, OnboardingViewController,
│                     OnboardingWindowController, DiagnosticsOverlay
└── Utils/            PermissionsManager, DisplayGeometry
```

`project.yml` is the source of truth. The generated `GazeFocus.xcodeproj` is gitignored; regenerate it any time with `xcodegen generate`.

## Licensing and distribution

Not signed, not notarized, not distributed outside a single developer machine yet. Developer ID signing + notarization + DMG building is Ramp-Up R5. Do not share MVP builds.
