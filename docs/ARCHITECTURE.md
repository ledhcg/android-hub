# Architecture

Android Hub is a SwiftPM package with five targets. Dependencies point downwards:

```
AndroidHub (app)   adbctl (CLI)
        \            /
   EmulatorKit   ScrcpyKit
              \   /
              AdbKit
```

| Target | Role |
|---|---|
| `AdbKit` | Speaks the adb server protocol directly over a socket: `host:devices-l`, `track-devices`, `shell,v2`, `sync:` v1/v2, `pair`/`connect`/`mdns`/`tcpip`, the emulator console, `localabstract:`. On top of that: device services (settings, apps, files, screenshots, logcat, crashes/ANRs, dumpsys, bugreport, diagnostics bundle). |
| `ScrcpyKit` | Native client for the pinned scrcpy-server: control-message encoding, device-message parsing, Annex-B → AVCC → `CMSampleBuffer`, passthrough MP4 recording, session lifecycle over `localabstract:`, mouse/keyboard mapping. |
| `EmulatorKit` | Android Virtual Device management through `avdmanager`/`sdkmanager`/`emulator`: list, create, delete, rename, start (cold boot / headless / wipe), stop, wipe, running detection. |
| `adbctl` | Command-line front end for the libraries. Every command supports versioned `--json-output`. |
| `AndroidHub` | The macOS app (SwiftUI + AppKit): sidebar, canvas, inspector. |

## Key decisions

- **No `adb` subprocess per call.** `AdbKit` talks to the adb server (`127.0.0.1:5037`) directly. The `adb` executable is only
  launched to run `start-server` when no server is reachable.
- **`shell,v2,raw:`** gives separate stdout/stderr/exit status and is binary-safe. Every value interpolated into a device shell
  command goes through `SettingChange.shellQuote`.
- **Emulator console.** Connect to the console port (the number in `emulator-5554`) and authenticate with
  `~/.emulator_console_auth_token`. Never use `host:emulator:<port>`: that service *registers* an emulator with the adb server and
  creates a ghost transport that only an adb server restart clears.
- **scrcpy-server is pinned and fetched at build time.** `scripts/fetch-scrcpy-server.sh` downloads it and verifies the SHA-256.
  The connection goes through adb's `localabstract:`, so no TCP port is opened on the Mac. The server process lives exactly as long
  as its shell connection: closing the socket cleans it up (and scrcpy deletes its own jar on exit, so tests must re-push it).
- **Video stays off the main thread.** H.264 packets become `CMSampleBuffer`s and are enqueued on `AVSampleBufferDisplayLayer`
  directly from the reader thread.
- **Many windows, one session.** `MirrorHub` fans the stream out to every canvas; a canvas that attaches late receives the cached
  config packet and a key-frame request.
- **Unicode typing.** scrcpy's `injectText` only types characters the virtual keyboard produces (ASCII). Other text is batched
  (~40 ms), NFC-normalised, placed on the device clipboard and pasted. The phone's clipboard is overwritten as a side effect.
- **Recording keeps real duration.** Each sample carries an explicit duration, so a static screen does not shorten the MP4.
- **Swift language mode.** Library targets build in Swift 6 mode. The `AndroidHub` app target uses Swift 5 mode because the
  AppKit/AVFoundation interop (video thread → layer) is not yet Sendable-clean.

## Upgrading scrcpy-server

The scrcpy control protocol is not stable between releases.

1. Update `VERSION` and `SHA256` in `scripts/fetch-scrcpy-server.sh` (checksum from the official release asset).
2. Update `ScrcpyServer.version` in `Sources/ScrcpyKit/ScrcpySession.swift`, the resource names in `Package.swift`, and
   `THIRD_PARTY_NOTICES.md`.
3. Re-check `ControlMessage.swift` byte-for-byte against `control_msg.c` of the new release, and the device-message parser.
4. Run the unit tests, then the integration tests on an emulator.

## Gotchas learned the hard way

1. `ps -A` shows `app_process64`, not the Java class. To check for leftover scrcpy servers use
   `ps -A -o ARGS | grep '[s]crcpy.Server'`.
2. `adb shell` reads stdin. In scripts and heredocs add `< /dev/null`, or `adb` swallows the rest of the script.
3. `avdmanager` writes `target=android-0` for system images with a minor version; the API level comes from `image.sysdir.1`.
4. SwiftPM output directories vary between toolchains. Use `swift build --show-bin-path`, and never pass several `--product`
   flags at once (only the last one is built).
5. adb pairing by code needs Android 11+. Older devices use `adbctl manage tcpip` over USB.
6. Xiaomi/MIUI/HyperOS require "USB debugging (Security settings)" for input injection.
