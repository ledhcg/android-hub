# Contributing to Android Hub

Thanks for your interest! Bug reports, device compatibility reports, docs and code are all welcome.
By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Contributions are licensed under
[Apache-2.0](LICENSE).

## Getting set up

```bash
git clone https://github.com/ledhcg/android-hub.git && cd android-hub
scripts/fetch-scrcpy-server.sh     # once: downloads + verifies the pinned scrcpy-server
swift build && swift test          # unit tests need no device
scripts/install-git-hooks.sh       # commit-message and pre-commit checks (see docs/GIT_WORKFLOW.md)
scripts/build-app.sh debug && open "build/Android Hub.app"
```

Requirements and device setup are in the [README](README.md). Architecture and design decisions are in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); open work is in [ROADMAP.md](ROADMAP.md).

## Before you open a pull request

- `swift build` and `swift test` pass with no new warnings.
- Add or update unit tests for parsing, protocol and argument-handling changes (they run without a device).
- Integration tests (`ADBHUB_TEST_SERIAL=emulator-5554 swift test --filter IntegrationTests`) change settings and write files on
  the device. **Run them against an emulator only**, never your own phone.
- Anything interpolated into a device shell command must go through `SettingChange.shellQuote`.
- Commands that write local files must refuse to overwrite without `--force`.
- Keep user-facing text (UI, CLI help, errors) and comments in English.
- UI changes follow the [design system](docs/design/README.md); run through its [checklist](docs/design/06-checklist.md).
- Changing a JSON output shape of `adbctl` requires bumping `jsonVersion`.
- Update `CHANGELOG.md` under *Unreleased*.
- Commits and PR titles follow [Conventional Commits](docs/GIT_WORKFLOW.md) (`feat(adbctl): add device reboot command`); CI checks the PR title.
- Keep PRs focused; describe how you tested (device model, Android version, macOS version).

## Reporting bugs

Please include macOS version, Android version and device model, how it is connected (USB / Wi-Fi / emulator), and the exact
steps. For connection problems add the output of `adbctl list devices` and `adb version`. **Do not attach screenshots or logs
containing private data.** Report security issues privately: see [SECURITY.md](SECURITY.md).

## Upgrading scrcpy-server

See "Upgrading scrcpy-server" in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The protocol changes between releases, so
this needs a careful, byte-level review of `ControlMessage.swift`.

## Working with AI coding agents

Agents are welcome, under the same rules as people. [CLAUDE.md](CLAUDE.md) (also surfaced through [AGENTS.md](AGENTS.md)) is the
project guide for them; path-scoped rules live in `.claude/rules/` and repeatable procedures (verify, UI change, new CLI command,
scrcpy upgrade, release) in `.claude/skills/`. The most important rule applies to everyone: **never test or take screenshots
against a physical device; use an emulator.** Machine-local agent settings go in `.claude/settings.local.json` (gitignored).
