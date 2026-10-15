# Android Hub

[![CI](https://github.com/ledhcg/android-hub/actions/workflows/ci.yml/badge.svg)](https://github.com/ledhcg/android-hub/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
![Platform: macOS 15+](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey.svg)
![Swift 6](https://img.shields.io/badge/swift-6-orange.svg)

A native macOS app for Android devices, inspired by the **Device Hub** experience in Xcode: one window with a **sidebar**
(devices + emulators), a **canvas** (live, controllable device screen) and an **inspector** (settings, info, apps, files,
logs, diagnostics) — plus `adbctl`, a scriptable command-line companion.

```
Android Hub.app  SwiftUI/AppKit app
adbctl           CLI; every command supports versioned --json-output
AdbKit           talks to the adb server directly (no `adb` subprocess per call)
ScrcpyKit        native client for scrcpy-server (H.264 video, input, MP4 recording)
EmulatorKit      AVD management (create, start, stop, delete, wipe)
```

> Android Hub is an independent project. It is **not affiliated with, endorsed by, or sponsored by** Apple, Google or
> Genymobile. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Requirements

| Requirement | Notes |
|---|---|
| macOS 15 or later | Apple Silicon or Intel |
| Swift 6.0+ toolchain (Xcode) | Developed and tested with Xcode 27 / Swift 6.4. Install full Xcode: the app bundle step uses `iconutil` and `codesign`. |
| Android SDK **platform-tools** | Provides `adb`. Found via `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `~/Library/Android/sdk`, Homebrew paths or `PATH`. |
| Android SDK **cmdline-tools** + a JDK | *Optional* — only needed to create/delete emulators and download system images. Android Studio's bundled JDK is detected automatically. |
| Internet access on first build | `scripts/fetch-scrcpy-server.sh` downloads the pinned scrcpy-server (checksum-verified). |

Install the Android tools if you do not have them yet:

```bash
brew install --cask android-platform-tools      # adb only
# or install Android Studio, which provides the SDK, cmdline-tools and a JDK
```

## Quick start

```bash
git clone https://github.com/ledhcg/android-hub.git
cd android-hub

scripts/build-app.sh            # fetches scrcpy-server, builds, produces "build/Android Hub.app" and build/adbctl
open "build/Android Hub.app"
```

`scripts/build-app.sh [release|debug]` (default `release`) builds the SwiftPM package, assembles an ad-hoc signed app
bundle with its icon and resources, and copies `adbctl` (plus its resource bundle) to `build/`. Because it is signed
ad-hoc and built locally, it runs on the machine that built it; it is not notarized.

### Prepare your Android device

1. Enable **Developer options** (Settings → About phone → tap *Build number* 7 times).
2. Enable **USB debugging**, connect the cable, and tap **Allow** on the "Allow USB debugging?" prompt.
3. Xiaomi / MIUI / HyperOS only: also enable **"USB debugging (Security settings)"**, otherwise mouse and keyboard
   control will not work (screen viewing still does).
4. Wireless (Android 11+): Developer options → **Wireless debugging** → *Pair device with pairing code*, then use the
   **Pair** sheet in the app or `adbctl manage pair`. On older devices connect via USB once and run
   `adbctl manage tcpip`.

Emulators work out of the box: create one in Android Studio or with `adbctl emulator create`, then start it from the
sidebar or `adbctl emulator start`.

### Using the app

- Select a device in the sidebar → **View Screen** opens the live canvas. Click/drag/scroll and type from your Mac;
  right-click = Back, middle-click = Home, ⌥-drag = pinch.
- Use the bezel and toolbar for hardware buttons, rotation, zoom, screenshot and screen recording.
- The inspector (right) has *Settings*, *Info*, *Apps* (drag an `.apk` onto it to install), *Files*, *Logs* and
  *Diagnostics*.

## Running from source (development)

```bash
scripts/fetch-scrcpy-server.sh   # once; required before the first build (SwiftPM needs the bundled jar to exist)
swift build                      # debug build
swift test                       # unit tests — no device needed
swift run adbctl list devices    # run the CLI without packaging
swift run AndroidHub             # run the app unpackaged (no icon / Info.plist; fine for development)
```

Or open the package in Xcode: `xed .` (Xcode generates the project in memory; no `.xcodeproj` is committed).

### Integration tests

Integration tests run against a real device and are **skipped unless** `ADBHUB_TEST_SERIAL` is set. They change settings
and write files (and clean up after themselves), so **point them at an emulator only**:

```bash
adbctl emulator start Pixel_8 --headless --wait
ADBHUB_TEST_SERIAL=emulator-5554 swift test --filter IntegrationTests
```

When checking for leftover servers, note that `ps -A` only shows `app_process`; use
`ps -A -o ARGS | grep '[s]crcpy.Server'`.

## CLI

```bash
adbctl list devices
adbctl device info details -d emulator-5554
adbctl device settings set appearance dark
adbctl device apps install app.apk            # several files = split APK
adbctl device files pull /sdcard/DCIM --output ~/Pictures
adbctl device record --duration 10 --output demo.mp4
adbctl device logs --level W --filter crash --count 50
adbctl emulator start Pixel_8 --headless --wait
adbctl help                                   # full command list; `<command> --help` for details
```

To use it anywhere: `cp build/adbctl /usr/local/bin/` **together with** the `AndroidHub_ScrcpyKit.bundle` directory
that sits next to it in `build/` (the CLI locates the pinned scrcpy-server through that bundle).

- `--json-output <file|->` writes `{info:{command,jsonVersion,outcome}, result|error}`. Scripts should read the JSON,
  not parse text.
- With one device attached `--device` may be omitted; with several it is **required** (never guessed). Names match in
  tiers: exact serial → case-insensitive name/model → prefix; ambiguous matches fail and list the candidates.
- Safety: commands that write local files (`screenshot`, `record`, `files pull`, `apps extract`) **refuse to overwrite**
  existing files unless `--force`; downloads go through a `.part` file and are renamed on success; `files rm` refuses
  `/`, `/sdcard`, `/data`, …
- A leading negative number (`location -33.87,151.2`) is treated as a value; use `--` to end options
  (`input text -- "-5%"`).

## Feature comparison with Device Hub

| Device Hub (Xcode) | Android Hub | Notes |
|---|---|---|
| Sidebar: devices + simulators, filter/sort | ✅ Filter real devices / emulators, sort, search | live plug/unplug tracking (`host:track-devices`) |
| Pair a device (cable / wireless) | ✅ USB, `adb pair` with code, `adb connect`, mDNS, `tcpip` | Android 11+ pairs with a code |
| Canvas: live screen + bezel | ✅ H.264 via scrcpy-server, hardware decode (VideoToolbox) | generic bezel, not per device model |
| Touch, drag, scroll, keyboard from the Mac | ✅ mouse/trackpad/keyboard, ⌥-drag pinch | Unicode typing goes through clipboard + paste |
| Home / Back / Recents / Power / Volume | ✅ bezel, toolbar and menus | |
| Rotate, zoom, actual size, resize mode | ✅ (`wm size` / `wm density`, works on real devices) | |
| Compact windows, multiple devices | ✅ several windows per device share one session | |
| Screenshot / screen recording | ✅ native-resolution PNG; MP4 H.264 without re-encoding | saved to Desktop; screenshots also go to clipboard |
| Inspector → Settings | ✅ appearance, font size, animations, orientation, network, brightness, volume, accessibility, battery, location, time zone, per-app language, developer options | applied immediately |
| Inspector → Info | ✅ model, OS, serial, display, battery, all `getprop` | |
| Inspector → Apps | ✅ list, install APK (drag & drop, split APKs), uninstall, launch, stop, clear data, grant/revoke permissions, extract APK, data container (debuggable apps) | |
| Inspector → Diagnostics | ✅ live logcat with filters, crashes/ANRs, dumpsys, bugreport, diagnostics bundle | |
| `devicectl` + `--json-output` | ✅ `adbctl` | JSON carries `jsonVersion` |
| Simulator management | ✅ create / start (cold boot, headless, wipe) / stop / delete AVDs | needs cmdline-tools + JDK to create/delete |
| Mount DeviceFS in Finder | ⚠️ in-app file browser + `adbctl device files` instead | macOS has no MTP; FSKit / File Provider is separate work |
| Profiles (`.mobileconfig`) | ❌ no Android equivalent | |
| Camera/mic, AirPlay, CarPlay, Siri, Shake | ❌ not applicable | |

## Architecture notes

- **adb protocol, directly.** `AdbKit` opens a socket to the adb server (`127.0.0.1:5037`), uses `shell,v2,raw:`
  (separate stdout/stderr/exit code, binary-safe) and `sync:` (push/pull/list/stat). The emulator console is reached
  through its console port plus auth token, like `adb emu` — **not** via `host:emulator:<port>`, which *registers* a new
  transport.
- **scrcpy-server is pinned** (`3.3.4`) and fetched at build time with a SHA-256 check. The scrcpy protocol is not stable
  between releases; upgrading means changing `ScrcpyServer.version`, `scripts/fetch-scrcpy-server.sh` and re-checking
  `ControlMessage.swift`. The connection goes over adb's `localabstract:`; no TCP port is opened on the Mac, and the
  server's lifetime equals its shell connection.
- **Video stays off the main thread.** H.264 packets → `CMSampleBuffer` → `AVSampleBufferDisplayLayer` on the reader thread.
- **Many windows, one session.** `MirrorHub` fans the stream out to every canvas; a late canvas gets the cached config
  packet and a key-frame request.
- **Unicode typing.** scrcpy's `injectText` only types what the virtual keyboard can (ASCII). Other text is batched
  (~40 ms), NFC-normalised, put on the device clipboard and pasted — so the *phone's* clipboard is overwritten.
- **Recording keeps real duration.** Every frame carries an explicit duration, so a static screen does not shorten the file.

More detail and current status: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [ROADMAP.md](ROADMAP.md).

## Privacy & security

- Everything runs locally. Android Hub has **no telemetry** and makes no network requests of its own; the only download
  is the scrcpy-server at build time.
- The app mirrors your screen and can read logs, bugreports, installed apps and files on a device you have authorised
  for USB/Wi-Fi debugging. Only authorise computers you trust.
- Wireless debugging exposes adbd on your network while enabled; turn it off when done.
- `FLAG_SECURE` / DRM content cannot be captured (appears black).
- Report vulnerabilities privately — see [SECURITY.md](SECURITY.md).

## Known limitations

- A screen that is off/locked produces no frames; the app wakes the screen before mirroring.
- The first mirror on some devices is slow (≈30 s seen on one Xiaomi device) while ART loads the jar; later runs take < 1 s.
- Location mocking on real devices relies on the `shell` test provider (ROM-dependent); emulators use `geo fix`.
- No audio, multi-display (`display_id`), camera or physical HID keyboard/mouse yet.
- Cancelling a running `bugreport` closes the connection but may not stop `dumpstate` on the device.
- Pushing files *into* an app's data container (run-as) is not supported; browse and pull only.
- Decomposed Vietnamese diacritics from synthetic typing tools can drop the last mark; real Telex/VNI input sends composed text.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md).
Changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## License

Apache License 2.0 — see [LICENSE](LICENSE). Third-party components and trademarks: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
