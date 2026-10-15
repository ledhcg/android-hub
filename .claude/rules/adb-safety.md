---
paths:
  - "Sources/AdbKit/**"
  - "Sources/EmulatorKit/**"
  - "Sources/ScrcpyKit/**"
  - "Sources/adbctl/**"
---

# adb / device safety

- Interpolate nothing raw into a device shell command: use `SettingChange.shellQuote` for every path, package, name or value.
  Add a test when you add a new command string (see "emulator console tokens cannot smuggle a second command").
- Emulator console commands go through the console port + auth token (`EmulatorConsole`), never `host:emulator:<port>`.
- Anything that writes a local file must refuse to overwrite unless `--force`; downloads write to a `.part` file then rename.
- Destructive device operations (`rm`, uninstall, clear data, wipe) refuse dangerous targets (`/`, `/sdcard`, `/data`, …) and are
  confirmed in the UI.
- Use `shell,v2,raw:` for output + exit code; never parse `adb` CLI text when the protocol gives structure.
- Parsers (`devices -l`, `pm`, `dumpsys`, logcat, `ls`) are pure functions with unit tests using captured sample output.
- Error messages are English, human first (what happened, what to do); keep raw adb text as detail.
- scrcpy: the control-message encoding must match the pinned `control_msg.c` byte for byte; server lifetime = shell connection.
