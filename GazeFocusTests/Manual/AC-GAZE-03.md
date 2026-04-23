# AC-GAZE-03 — Manual gaze classification accuracy

**Target:** ≥ 85 % correct screen classifications over 100 deliberate samples.
**Prerequisites:** M7 calibration complete. Two external displays connected left/right of the user.

## Setup

1. Enable the diagnostics overlay and stdout logging:
   ```bash
   defaults write com.shubhamdesale.gazefocus diagnosticsOverlayEnabled -bool true
   ```
2. Run GazeFocus from Xcode (⌘R) so the console captures `gaze screen=…` lines.
3. Sit ~60 cm from the center of the monitor arrangement. Ambient light around 500–1000 lux.
4. Complete 5-dot calibration from the menu (M7).

## Protocol

- Alternate gaze between the two screens, 50 times each (100 samples total).
- Hold gaze on each target for ~1 second before switching.
- After each deliberate switch, note the newest `gaze screen=N` value logged.
- Do **not** dwell-switch the cursor — this test measures raw classification, not warp behavior. Pause tracking (`⌥⌘G`) if the cursor interferes.

## Measurement

- Tally "correct" = logged `screen=N` matches the target screen.
- Record result in the table below.

| Attempt | Target (L=0 / R=1) | Logged screen | Correct? |
|---------|--------------------|---------------|----------|
| 1 | … | … | … |
| … | … | … | … |
| 100 | … | … | … |

**Pass condition:** ≥ 85/100 correct.

## Cleanup

```bash
defaults delete com.shubhamdesale.gazefocus diagnosticsOverlayEnabled
```
