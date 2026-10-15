# Changelog

All notable changes are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Security

- Cap the size of video packets announced by the device (32 MiB) and of clipboard messages (1 MiB) so a corrupt or hostile
  stream cannot force huge allocations.
- Only apply a device clipboard to the Mac clipboard within 5 seconds of an explicit Cmd+C / Cmd+X; unsolicited clipboard
  messages are ignored.

### Fixed

- Commit lint no longer rejects squash-merge subjects because of the ` (#123)` suffix GitHub appends.

## [0.1.0] - First public release

- `AndroidHub.app`: sidebar, live canvas with input, inspector (Settings, Info, Apps, Files, Logs, Diagnostics).
- `adbctl`: ~45 commands with versioned `--json-output`.
- `AdbKit`, `ScrcpyKit`, `EmulatorKit` libraries.
