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

## Cleanup and polish

- The battery-state and network speed/latency pickers in the Settings panel do not read back the current value. 🌱
- Logcat panel: visible buffer is capped at 5000 lines; add regex search, PID/package filter, highlighting. 🌱
- Sidebar: remember custom order/grouping.
- Unicode typing overwrites the phone's clipboard; consider restoring the previous clipboard or making it optional.
- `adbctl device logs --json-output` buffers the whole log in memory before writing.
- Migrate the `AndroidHub` target to Swift 6 language mode.
- Fix compiler deprecation warnings: `onChange(of:perform:)` (macOS 14) in `CanvasView`, `InspectorView`, `LogsPanel`,
  `SettingsPanel`; `AVSampleBufferDisplayLayer` → `sampleBufferRenderer` (macOS 15) in `MirrorNSView`; weak-`self` capture
  in `MirrorController`. 🌱

## Known limitations (by design)

- A screen that is off or locked produces no frames; the app wakes the screen before mirroring. `FLAG_SECURE` windows are black.
- The first mirror on some devices is slow (~30 s observed on one Xiaomi device) while ART loads the jar; later runs take under a second.
- Unicode input goes through clipboard + paste.
- Files ≥ 4 GiB need sync v2 (64-bit), used whenever adbd supports `stat_v2`/`ls_v2`; v1 is only a fallback.
- No Android equivalent for `.mobileconfig` profiles, Siri, Shake, CarPlay or AirPlay.
