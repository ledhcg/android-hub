---
name: upgrade-scrcpy-server
description: Bump the pinned scrcpy-server version safely (checksum, protocol re-verification, notices, tests). Use only when the maintainer asks to upgrade scrcpy.
---

# Upgrade scrcpy-server

The scrcpy control protocol is **not stable between releases**. Never bump the version without the protocol review in step 3.

1. Pick the release on <https://github.com/Genymobile/scrcpy/releases> and download `scrcpy-server-v<VERSION>` to a scratch dir.
   Compute `shasum -a 256`; cross-check against the release notes when they publish it.
2. Update in one change:
   - `scripts/fetch-scrcpy-server.sh`: `VERSION`, `SHA256`.
   - `Sources/ScrcpyKit/ScrcpySession.swift`: `ScrcpyServer.version`.
   - `Package.swift`: the `.copy("Resources/scrcpy-server-<VERSION>.jar")` resource name.
   - `THIRD_PARTY_NOTICES.md`: version, source and binary links, SHA-256.
   - `CHANGELOG.md`.
3. **Protocol review (byte level):** diff the upstream `app/src/control_msg.c`, `device_msg.c`, `server.c` (arguments) and the
   video stream header between the old and new tags. Update `ControlMessage.swift`, the device-message parser, server arguments in
   `ScrcpySession.swift`, and `ProtocolTests.swift` expectations. Note every incompatibility in the commit body.
4. Delete the old jar (`rm Sources/ScrcpyKit/Resources/*.jar`), run `scripts/fetch-scrcpy-server.sh`, `swift build && swift test`.
5. Run the ScrcpyKit integration tests against an **emulator only** (`ADBHUB_TEST_SERIAL=emulator-5554`), and confirm no leftover
   server (`ps -A -o ARGS | grep '[s]crcpy.Server'` is empty after `stop()`).
6. Never commit the jar (it is gitignored).
