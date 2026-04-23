#!/bin/bash
# Clears the stored CalibrationProfile so the next launch starts fresh.
set -euo pipefail
defaults delete com.shubhamdesale.gazefocus com.shubhamdesale.gazefocus.calibration 2>/dev/null || true
echo "GazeFocus calibration profile cleared."
