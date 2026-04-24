# Genesis — GazeFocus Handover for the Next Claude Agent

Read this in full before you touch code, memory, or git. Then read [`gazefocus-technical-design.md`](./gazefocus-technical-design.md) and [`gazefocus-build-plan.md`](./gazefocus-build-plan.md). Those three documents are the source of truth for this project; this file exists to transfer everything *around* the code — persona, collaboration norms, current state, the machine context — that a fresh agent on a new machine wouldn't otherwise have.

---

## 1. Who you are collaborating with

**Shubham Desale.** Personal GitHub: `shubhamd`. Work email: `sdesale@coursera.org` (Coursera). GazeFocus is a personal project — it is **not** Coursera work. Treat it as such: no Coursera-specific tooling, no Jira, no Confluence, no Slack integrations.

Background: experienced backend/systems engineer (Node.js, Python, AWS). **New to Swift, AppKit, and the Apple frameworks.** The tech design doc is written for exactly this audience — it explains Apple-platform concepts from first principles. When you explain something Apple-native, frame it against a backend analogue if one exists, but don't over-teach. He reads code fast.

He values:
- **Restraint.** No speculative features, no dead-code abstractions, no "just in case" config surface area, no framework soup.
- **Terseness.** Short replies. Skip preamble. Skip end-of-turn recaps unless something is genuinely non-obvious.
- **Root causes over workarounds.** If a build fails, fix the underlying issue — don't `--no-verify`, don't silence warnings, don't skip tests.
- **Confirmation before irreversible actions.** Never `git push --force`, never destructively reset, never delete branches, never push commits the user didn't ask for. The setup of the two-account SSH flow is the pattern: diagnose, explain, propose, wait for "yes."

## 2. What GazeFocus is

macOS menu-bar utility. Uses the built-in FaceTime webcam + Apple's Vision framework to detect which display the user is looking at, then warps the cursor there. No hardware beyond the Mac. **On-device only; no video, no telemetry, no phone-home, ever.** This is a hard rule (see build plan §4 Non-Goals) — do not add analytics, crash reporters, usage stats, or third-party SDKs that exfiltrate anything. If asked, decline and cite this file.

Distribution: direct-download signed DMG. **Not** the Mac App Store — the Accessibility APIs the app depends on (`CGWarpMouseCursorPosition`, `AXIsProcessTrusted`) cannot run in an App Store sandbox (tech design §4.2).

Target user: macOS 13+, Apple Silicon, 2+ displays. MVP targets 2-display setups specifically; 3+ display support is v0.3 work (R6.5).

## 3. Current state (as of 2026-04-24)

**v0.1 MVP is complete and pushed to `origin/main`** on `github.com:shubhamd/gaze-focus-mac`.

The single initial commit (`d4c3532`) contains: tech design doc, build plan, and the full MVP implementation — every M-task from MVP-M0 through MVP-M10 is done. That includes: xcodegen project, AppDelegate + menu bar + global ⌥⌘G pause, permissions flow + polling, camera pipeline (15fps, `.low` preset, interruption handling), Vision-based gaze detection, exponential smoother, dwell controller with injectable clock, cursor warp engine (main-thread-only), 5-dot calibration with persistence + monitor-config hash, 5-screen onboarding (plain-text, AppKit), single-display guard, diagnostics overlay (red dot, gated by `defaults write`), and the automated + manual test suites the build plan specifies.

What hasn't been done yet: **all of ramp-up (R1–R9).** The recommended v0.2 cut line is R1 + R2 + R4 + R5 + R6.1–R6.3 + R7.1–R7.5 — see build plan §3. Workstreams within ramp-up are independent and can be parallelized; tasks within a workstream are sequential.

Nothing is in-flight. You are picking up at a clean main.

## 4. Machine context — why this file exists

Shubham works on two Macs. The company Mac (where the initial MVP was built) is staying on *other* utilities — browser-based tools, Electron apps, unrelated side projects. GazeFocus moves to the **personal machine**, which you are presumably running on now. The project repo on the personal machine is a fresh clone of `git@github-personal:shubhamd/gaze-focus-mac.git` (or `git@github.com:shubhamd/gaze-focus-mac.git` if only one GitHub account is configured there).

**Before you claim the MVP "works" on this machine, build it.** The company Mac had Xcode 26.4.1 + xcodegen + the developer's Apple ID keychain. This machine may differ. Run:

```bash
brew install xcodegen                    # if missing
xcodegen generate                        # regenerates GazeFocus.xcodeproj (gitignored)
xcodebuild -project GazeFocus.xcodeproj -scheme GazeFocus -configuration Debug build
xcodebuild -project GazeFocus.xcodeproj -scheme GazeFocus test
```

If the build is green and tests pass, you're synced. If not, fix the environment (not the code) first — `project.yml` is the source of truth and was known-good at commit `d4c3532`.

One known project.yml detail: `DEVELOPMENT_TEAM: 38M5GTQP8K` is baked in. It activates *only* when a Developer ID cert for that team is in the keychain — that's the R5 distribution step and not required for local Debug builds (Debug is ad-hoc signed with `CODE_SIGN_IDENTITY: "-"`).

## 5. Collaboration norms — do not drift from these

These are earned rules, not defaults. Follow them.

- **Work the plan.** `gazefocus-build-plan.md` is the task list. When Shubham picks a ramp-up task, the plan entry tells you the deliverable, dependencies, and acceptance criteria IDs. Don't invent scope beyond that entry. If a task looks unfamiliar or underspecified, re-read the tech design §5 (component deep-dives) before coding.
- **`project.yml` is source of truth.** The `.xcodeproj` is a build artifact and is gitignored. Never commit it. Regenerate with `xcodegen generate` whenever the project structure changes.
- **Swift style matches what's already in the repo.** Small, focused classes. No premature protocols. Protocol-based indirection *only* where the build plan asks for it (e.g., `DwellClock`, `ScreenProvider` — injected strictly to make tests deterministic). Don't add `// MARK:` sections or doc comments for obvious code; follow the existing restraint.
- **No telemetry, no analytics, no crash reporters.** Already said. Saying it again because this is the most common way an agent drifts.
- **No new top-level dependencies without asking.** The project currently has zero third-party Swift packages — Apple frameworks only. If a ramp-up task tempts you to pull in e.g. Lottie for animations (R4.1) or a DMG builder, surface it first; don't just add it.
- **Tests are load-bearing.** The MVP ships with XCTest coverage of camera gating, gaze classifier boundaries, dwell state machine (injected clock), cursor-engine sort + main-thread precondition, and calibration persistence. Ramp-up tasks that add new behavior must extend this suite — see the `[AUTO]` and `[MANUAL]` tags in the build plan.
- **Never run destructive git operations without explicit approval.** Includes `push --force`, `reset --hard`, `branch -D`, amending published commits, rewriting main.
- **Before you recommend something from a previous turn's memory, verify it still holds.** A file that existed in the MVP may have been refactored. `grep` or `ls` first.

## 6. Running, resetting, diagnosing

See `README.md` for the user-facing version. Agent-facing shortcuts:

- Launch after build: `open ~/Library/Developer/Xcode/DerivedData/GazeFocus-*/Build/Products/Debug/GazeFocus.app` — no Dock icon, look for the `eye` SF Symbol in the menu bar.
- Force re-onboarding: `./scripts/reset-onboarding.sh`
- Clear stored calibration: `./scripts/reset-calibration.sh`
- Turn on the red-dot diagnostics overlay: `defaults write com.shubhamdesale.gazefocus diagnosticsOverlayEnabled -bool true` then relaunch. Turn off: `defaults delete …`. DEBUG builds also print one `gaze screen=N x=… conf=…` line per frame to stdout when the overlay is on — useful for AC-GAZE-03 accuracy runs.
- Permissions the app needs: Camera (prompted on first run) + Accessibility (user must toggle in System Settings → Privacy & Security → Accessibility after first launch).

## 7. Starting your first session on this machine

A clean first pass, in order:

1. Read this file. (Done.)
2. Read `README.md` for the user-facing build/test workflow.
3. Skim `gazefocus-technical-design.md` §3–§6 (architecture, thread model, component contracts) and §5 in full for whichever ramp-up task you're about to touch.
4. Open `gazefocus-build-plan.md` at the R-section matching the user's request. Work the plan, not your instinct.
5. Run `xcodegen generate` + build + test to confirm the environment is clean before you change anything.
6. When in doubt, ask — Shubham prefers one clarifying question over a wrong assumption.

## 8. Things that are easy to get wrong

- **Thread model.** Vision requests run on the camera's `videoQueue` (background). `CGWarpMouseCursorPosition` **must** run on main — `CursorEngine.warpCursor` has a `precondition(Thread.isMainThread, …)` guard and the test suite enforces it. Don't remove or weaken it.
- **NSScreen coordinates.** `NSScreen.frame` is bottom-left origin and can have negative X/Y values on multi-display setups. `sortedScreens` sorts by `frame.minX` ascending; tests depend on this sort being stable. See tech design §5.4 for the flipped-coordinate gotcha.
- **Calibration profile shape.** MVP writes `screenBoundaryGazeX = [centerDotMedian]` — a single dividing X for 2-screen setups. R6.5 extends this to N-1 boundaries for N screens. Don't "generalize early" before R6.5 — you'll break the classifier fallback and AC-CAL-05.
- **Dwell controller timing.** Tests inject a `DwellClock` protocol. Real-`Timer`-based tests are flaky on CI; the injectable clock is deliberate. Don't replace it with `XCTWaiter` sleeps.
- **Icon state machine.** MVP ships 3 of 5 states (`active`, `paused`, `permissionMissing`). R1.1 expands to 5. Don't sneak the other two states in via a half-wired PR — the build plan keeps them separate for a reason.

---

*Genesis v1.0 — 2026-04-24. If you significantly update collaboration norms or the current state, revise this file and bump the version.*
