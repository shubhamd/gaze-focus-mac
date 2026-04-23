# MVP End-to-End Manual Test

**What this verifies:** A fresh user, on a two-display Mac with no prior GazeFocus state, can install, onboard, calibrate, and use the app to warp the cursor via gaze — and can pause / resume on demand.
**Maps to:** AC-ONBOARD-01, AC-ONBOARD-02, AC-ONBOARD-04, AC-GAZE-03, AC-DWELL-05, AC-CURSOR-02, AC-CURSOR-03.

## Preconditions

- macOS 13+ (you're likely on 26).
- Two displays connected.
- No Camera or Accessibility permission granted to GazeFocus yet (revoke in System Settings if needed).
- Prior state cleared:
  ```bash
  ./scripts/reset-onboarding.sh
  ./scripts/reset-calibration.sh
  ```

## Part A — First launch & onboarding

1. Launch GazeFocus (`open .../GazeFocus.app`).
2. Expect: the onboarding window appears ("GazeFocus / Look at a screen. Your cursor follows.").
3. Click **Get Started**. Expect step 2 ("How it works").
4. Click **Continue**. Expect step 3 ("Camera access").
5. Click **Grant Camera Access**. A system dialog appears — click **OK**.
6. Expect auto-advance to step 4 ("Accessibility access").
7. Click **Open System Settings**. System Settings opens to Privacy & Security → Accessibility. Toggle GazeFocus on (enter your password).
8. Return to the onboarding window. Within 1 s expect auto-advance to step 5 ("One last step — quick calibration").
9. Click **Start Calibration**. Full-screen overlay appears with 5 dots appearing in sequence across both screens.
10. Look at each dot until it disappears (~2 s per dot, ~15 s total).
11. Overlay dismisses. Onboarding window closes. Menu bar icon is the `eye` symbol.

**Pass: the full first-launch flow takes under 3 minutes.**

## Part B — Gaze drives the cursor

1. Move the cursor to screen 1. Look at screen 1 for 2 s — cursor should stay put.
2. Shift your gaze steadily to screen 2. After ~400 ms of sustained gaze, the cursor should warp to the center of screen 2.
3. Repeat 5–10 times in alternating directions.

**Pass:** At least 85 % of deliberate switches succeed. (Formal 100-sample version: `AC-GAZE-03.md`.)

## Part C — Pause / resume

1. Press **⌥⌘G** from any app. The menu bar icon should change to `eye.slash` and the title should read "GazeFocus — Paused".
2. Move your gaze between screens. The cursor should **not** warp.
3. Press **⌥⌘G** again. Icon returns to `eye`. Title reads "Active". Gaze-driven warping resumes.

## Part D — Revocation detection (AC-EDGE-05)

1. With the app running and icon `eye`, open System Settings → Privacy & Security → Camera. Toggle GazeFocus off.
2. Within 5 s the menu bar icon should flip to the red `exclamationmark.triangle` and the menu title should read "Permission Required".
3. Toggle GazeFocus back on. Within ~4 s the icon returns to `eye`.

## Part E — Camera interruption (AC-EDGE-02)

1. While GazeFocus is active, open Photo Booth (which seizes the camera).
2. GazeFocus icon should flip to permission-missing state within ~2 s.
3. Close Photo Booth. Within ~4 s GazeFocus should return to active.

## Part F — Single-display guard (AC-EDGE-03)

1. Disconnect the secondary display.
2. Menu title should read "GazeFocus — Single Display". The app must not crash or loop.
3. Reconnect. State returns to "Active" (via the permissions path) within a couple of seconds.

## Cleanup

```bash
defaults delete com.shubhamdesale.gazefocus diagnosticsOverlayEnabled 2>/dev/null
./scripts/reset-onboarding.sh   # if you want to re-run Part A
./scripts/reset-calibration.sh
```
