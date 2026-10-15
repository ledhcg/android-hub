---
name: verify-app
description: Build, test and (for UI changes) visually verify Android Hub safely. Use after any code change, before reporting work as done, or when asked to run/check the app. Emulator-only; never mirrors or screenshots a physical device.
---

# Verify the app

Read `.claude/rules/testing-and-privacy.md` first. Physical devices are off limits for mirroring, screenshots and integration tests.

## 1. Build and unit tests (always)

```bash
scripts/fetch-scrcpy-server.sh          # no-op if the jar is present and verified
swift build 2>&1 | grep -E "error:|warning:"   # no new warnings
swift test 2>&1 | grep -E "Test run with|error:|✘"
```
Report the real result. If something fails, show the output; do not claim success.

## 2. Package the app (when UI or resources changed)

```bash
scripts/build-app.sh                    # -> "build/Android Hub.app", build/adbctl
```

## 3. Guarded visual check (UI changes)

1. Start an emulator: `build/adbctl emulator start Pixel_8 --wait` (1–2 min). Confirm with `build/adbctl list devices`.
2. Quit any running copy, then `open -n "build/Android Hub.app"`, `osascript -e 'tell application "Android Hub" to activate'`.
3. Window ID/bounds: `swift .claude/skills/verify-app/winid.swift`. Screen point = window origin + point inside the window.
4. Select the emulator row with `swift .claude/skills/verify-app/click.swift <x> <y>`, then **read the window title**:
   `osascript -e 'tell application "System Events" to tell process "Android Hub" to get name of window 1'`.
   **Continue only if it is the emulator ("Pixel 8").** Otherwise stop: a physical phone may be selected.
5. Capture only the window: `screencapture -x -o -l <windowID> $SCRATCH/shot.png`, then read the image. Never capture the full screen.
6. Cover the states the change touches (empty, idle, mirroring, each inspector tab, sheets), in light and dark if styling changed
   (Settings → Appearance, or the Device menu).
7. Clean up: `pkill -x AndroidHub`, `build/adbctl emulator stop --device emulator-5554`, delete the screenshots, and check
   `adb -s <physical serial> shell 'ps -A -o ARGS' < /dev/null | grep -c '[s]crcpy'` prints `0`.

## 4. Report

What you built/ran, test counts, which states you actually looked at, and — explicitly — which you did **not** verify visually.
