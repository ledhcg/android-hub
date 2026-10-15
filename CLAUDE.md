# Android Hub — agent guide

Native macOS app + CLI for Android devices (live screen mirroring and control, settings, apps, files, logs, emulators).
Swift 6 / SwiftPM, macOS 15+. Open source (Apache-2.0). Read this first; detailed rules live in `.claude/rules/` and
repeatable procedures in `.claude/skills/`.

## Layout

```
Sources/AdbKit       adb protocol client (sockets, shell v2, sync, services). No UI. Foundation of everything
Sources/ScrcpyKit    native client for the pinned scrcpy-server (video, input, recording)
Sources/EmulatorKit  AVD management (avdmanager / emulator)
Sources/adbctl       CLI; every command has versioned --json-output
Sources/AndroidHub   SwiftUI/AppKit app. Design/ = tokens + shared components; Views/; Model/
Tests/               Swift Testing (@Suite/@Test). Integration tests are opt-in (see below)
scripts/             build-app.sh, fetch-scrcpy-server.sh, make-icon.swift, assets/
docs/                ARCHITECTURE.md, design/ (UI system)
```
Dependency direction: `AndroidHub`, `adbctl` → `EmulatorKit`, `ScrcpyKit` → `AdbKit`. Never import upward.

## Commands

```bash
scripts/fetch-scrcpy-server.sh      # once per clone; SwiftPM fails without the jar (it is gitignored)
swift build && swift test           # unit tests, no device needed
scripts/build-app.sh [debug|release]   # -> "build/Android Hub.app" + build/adbctl (ad-hoc signed)
swift run adbctl help
ADBHUB_TEST_SERIAL=emulator-5554 swift test --filter IntegrationTests   # EMULATOR ONLY
```
Use `swift build --show-bin-path`; never pass several `--product` flags. Quote the app path: it contains a space.

## Non-negotiables

1. **Never touch a physical device for tests or screenshots.** Integration tests change settings and write files; mirroring or
   screenshotting a real phone exposes private content. Use an emulator; before any "View Screen" confirm the selected device
   is the emulator (window title). Delete screenshots you took. See `.claude/rules/testing-and-privacy.md`.
2. **English only** in source, UI, CLI output, docs and comments (Unicode test *data* is the one exception).
3. **Shell safety:** everything interpolated into a device shell command goes through `SettingChange.shellQuote`.
   Local file writes refuse to overwrite without `--force`. See `.claude/rules/adb-safety.md`.
4. **UI follows the design system** in `docs/design/` — tokens from `Design/DesignTokens.swift`, no literals; system accent is
   never overridden. See `.claude/rules/ui.md`.
5. **Do not reference third-party products as design sources** in docs or code comments.
6. scrcpy-server is pinned and checksum-verified; never commit the jar. Upgrade only via the `upgrade-scrcpy-server` skill.
7. Do not rewrite git history, force-push, publish the repo or cut a release unless explicitly asked.

## Conventions

- Match surrounding code; Swift 6 strict concurrency in libraries (the `AndroidHub` target stays in Swift 5 mode until the
  AppKit/AVFoundation video path is Sendable-clean).
- Pure parsing and protocol logic gets unit tests (`@Suite`/`@Test`/`#expect`); device behaviour goes in opt-in integration tests.
- `adbctl` JSON shape changes bump `jsonVersion`. Every new command: usage line, summary, `--json-output`, human output.
- Update `CHANGELOG.md` (Unreleased) for user-visible changes and `ROADMAP.md` when you find or finish follow-ups.
- Commits: Conventional Commits (`type(scope): summary`), body explains why, one logical change each. Rules and tooling:
  `docs/GIT_WORKFLOW.md`, `.claude/rules/git.md`. Run `scripts/install-git-hooks.sh` once per clone.

## Skills (use via the Skill tool)

| Skill | When |
|---|---|
| `commit` | When asked to commit: Conventional Commits, hooks, no push |
| `verify-app` | After any code change: build, test, and (for UI) a guarded emulator-only visual check |
| `ui-change` | Any change under `Sources/AndroidHub/` |
| `add-adbctl-command` | Adding or changing a CLI command |
| `upgrade-scrcpy-server` | Bumping the pinned scrcpy-server |
| `release` | Only when the maintainer asks for a release |

## Gotchas

- `host:emulator:<port>` *registers* an emulator; use the console port + `~/.emulator_console_auth_token` instead.
- `adb shell` reads stdin: add `< /dev/null` in scripts. `ps -A` hides the Java class: use `ps -A -o ARGS | grep '[s]crcpy.Server'`.
- A compact window auto-starts mirroring and `MirrorController` is shared per device, so one window can start the canvas of another.
- More in `docs/ARCHITECTURE.md`.
