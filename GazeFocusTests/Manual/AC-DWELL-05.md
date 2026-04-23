# AC-DWELL-05 — Manual false-trigger test

**Target:** Fewer than 3 unintended cursor switches during 5 minutes of normal reading.
**Prerequisites:** M7 calibration complete. Default settings (dwell = 400 ms, smoother α = 0.3).

## Setup

1. Enable the diagnostics overlay (optional but useful for tallying):
   ```bash
   defaults write com.shubhamdesale.gazefocus diagnosticsOverlayEnabled -bool true
   ```
2. Place a long-form document (article, docs page, essay) on screen 1. A second screen should be visible at the edge of peripheral vision but not being used.
3. Sit naturally at your desk, ~60 cm from the primary display, normal ambient light.
4. Complete 5-dot calibration (M7).

## Protocol

- Read the document for **5 uninterrupted minutes**. Natural reading only — no deliberate screen switching.
- Each time the cursor unexpectedly warps away from screen 1, tally a "false trigger."
- Do **not** pause tracking during the test. If you need to stop early, abandon the run and restart.

## Measurement

| Trigger # | Approx. time (mm:ss) | Likely cause (guess) |
|-----------|-----------------------|------------------------|
| 1 | — | — |
| 2 | — | — |
| 3 | — | — |

**Pass condition:** Total count < 3 across the full 5 minutes.

## If it fails

Do not change settings yet. Run the test a second time — gaze behavior has high session-to-session variance. If the average over two runs still fails, file the problem as a dwell-tuning issue (candidate fixes: raise dwell duration to 500 ms, lower α to 0.2, or add hysteresis around the screen boundary — the last of which is Ramp-Up territory, not MVP).

## Cleanup

```bash
defaults delete com.shubhamdesale.gazefocus diagnosticsOverlayEnabled
```
