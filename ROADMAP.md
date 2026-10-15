# Roadmap

Open items, roughly in priority order. Each one is (or should become) a GitHub issue; items marked 🌱 are good first issues.

## Needs verification on real hardware (code exists, not yet exercised)

- Full Wi-Fi pairing flow with an Android 11+ device (`adb pair` with code, then `connect`). UI, mDNS discovery and parsers work;
  no pairing session has been completed end to end.
- Touch and keyboard input on a real Xiaomi device (needs "USB debugging (Security settings)"). Video was measured via the CLI;
  input was only verified on an emulator.
- Pinch (⌥-drag), Cmd+C / Cmd+X (device → Mac clipboard) and Cmd+V (Mac → device) in the GUI.
- A real Telex/VNI input method (marked text). Only synthetic typing tools have been tried.
- Location mocking on real devices (`cmd location` test provider); only emulators (`geo fix`) are verified.

## Testing

- No automated UI tests; the GUI is checked manually.
- `adbctl` has no unit tests for argument parsing and dispatch. 🌱

## Features

- Mount the device filesystem in Finder (FSKit or File Provider).
- Push files into an app's data container (`run-as`); today it is browse and pull only.
- Audio (scrcpy audio, Android 11+), multi-display (`display_id`, `new_display`), camera, H.265/AV1.
- UI for mirror configuration: `ScrcpyConfiguration` (max size, fps, bitrate, show touches, stay awake) exists but the app uses defaults.
- Per-model device bezels and a model-specific navigation bar.
- Stop `dumpstate` on the device when a `bugreport` is cancelled (today only the connection is closed).
- Change the system language directly (currently only opens the settings screen).
- Advanced developer options: layout bounds, GPU overdraw, profiling.
- Distribution: Developer ID signing, notarization, DMG, Homebrew tap (builds are currently ad-hoc signed and run only on the
  machine that built them).

## UI and design system

Follow-ups from the [design system](docs/design/README.md) rollout.

- Verify visually (light **and** dark, Increased Contrast): Logs panel header after the Level picker fix, the mirroring canvas after
  the token refactor, the Pair and New Emulator sheets, the compact window. 🌱
- Honour **Reduce Motion** and **Reduce Transparency** everywhere (audit transitions, toast, glass fallbacks).
- "Show More" progressive disclosure for long lists (apps, files, logs) instead of fixed caps.
- Bezel side buttons are 5 pt wide (below the 24 pt hit-target rule); add a larger invisible hit area and an accessibility label.
- Semantic status colour tokens (warning / error / success) replacing raw `.orange` / `.red`; promote the sheet error banner
  (`SheetLog` in `Sheets.swift`) to a shared `Banner` component in `Design/`.
- `StatusMessage`: slot for a `ProgressView` as the leading glyph (the "starting" state is currently hand-built).
- Token for the dashed drop-target outline used by the Apps and Files panels.
- Group toolbar items with `ToolbarSpacer` on macOS 26+.
- Migrate `ObservableObject` / `@StateObject` / `@EnvironmentObject` to `@Observable` (separate, carefully tested change).
- Automated visual regression: scripted screenshots of every state against an emulator (never a physical device).
- Add an explicit confirmation or setting before a compact window auto-starts mirroring.

## Cleanup and polish

- The battery-state and network speed/latency pickers in the Settings panel do not read back the current value. 🌱
- Logcat panel: visible buffer is capped at 5000 lines; add regex search, PID/package filter, highlighting. 🌱
- Sidebar: remember custom order/grouping.
- Unicode typing overwrites the phone's clipboard; consider restoring the previous clipboard or making it optional.
- `adbctl device logs --json-output` buffers the whole log in memory before writing.
- Migrate the `AndroidHub` target to Swift 6 language mode.
- Fix remaining compiler warnings: `AVSampleBufferDisplayLayer` → `sampleBufferRenderer` (macOS 15) in `MirrorNSView`, and the
  weak-`self` capture in `MirrorController`. Verify mirroring on a device or emulator afterwards. 🌱

## Known limitations (by design)

- A screen that is off or locked produces no frames; the app wakes the screen before mirroring. `FLAG_SECURE` windows are black.
- The first mirror on some devices is slow (~30 s observed on one Xiaomi device) while ART loads the jar; later runs take under a second.
- Unicode input goes through clipboard + paste.
- Files ≥ 4 GiB need sync v2 (64-bit), used whenever adbd supports `stat_v2`/`ls_v2`; v1 is only a fallback.
- No Android equivalent for `.mobileconfig` profiles, Siri, Shake, CarPlay or AirPlay.
