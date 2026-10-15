# Third-party notices

Android Hub itself is licensed under the Apache License 2.0 (see [LICENSE](LICENSE)).
It uses the following third-party component.

## scrcpy-server

- **What:** the on-device server half of [scrcpy](https://github.com/Genymobile/scrcpy). Android Hub implements its own
  native macOS *client* for the scrcpy protocol (`Sources/ScrcpyKit`) and pushes this server to the device over `adb`.
- **Version:** 3.3.4 (pinned; the protocol is not stable between releases)
- **Copyright:** © Genymobile
- **License:** Apache License 2.0 — full text in [`Sources/ScrcpyKit/Resources/SCRCPY-LICENSE.txt`](Sources/ScrcpyKit/Resources/SCRCPY-LICENSE.txt)
- **Source:** <https://github.com/Genymobile/scrcpy/tree/v3.3.4>
- **Binary:** <https://github.com/Genymobile/scrcpy/releases/tag/v3.3.4> (`scrcpy-server-v3.3.4`)
- **SHA-256:** `8588238c9a5a00aa542906b6ec7e6d5541d9ffb9b5d0f6e1bc0e365e2303079e`

The binary is **not stored in this repository**. `scripts/fetch-scrcpy-server.sh` downloads it from the official release
and refuses to continue if the checksum differs. The unmodified upstream binary is bundled into the built app.

## Trademarks

Android is a trademark of Google LLC. Xcode, Device Hub, devicectl, macOS and Apple are trademarks of Apple Inc.
scrcpy is a project of Genymobile. Android Hub is an independent project and is **not affiliated with, endorsed by,
or sponsored by** Google, Apple or Genymobile. References to Device Hub describe the user experience that inspired this
project; no Apple code or assets are used.
