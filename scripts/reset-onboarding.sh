#!/bin/bash
# Clears the "has completed onboarding" flag so the next launch re-runs the
# first-launch flow. Useful for MVP QA.
set -euo pipefail
defaults delete com.shubhamdesale.gazefocus hasCompletedOnboarding 2>/dev/null || true
echo "GazeFocus onboarding flag cleared."
