---
name: add-adbctl-command
description: Add or change an adbctl CLI command (registry entry, library call, JSON output, tests, docs). Use whenever a new device capability needs a command-line surface.
---

# Add an `adbctl` command

1. **Library first.** Implement the capability in `AdbKit` / `EmulatorKit` / `ScrcpyKit` (pure, testable; no printing). Parsing is a
   pure function with a unit test using captured sample output. Follow `.claude/rules/adb-safety.md` (`shellQuote`, no overwrite
   without `--force`, dangerous-target refusal).
2. **Register** in `Sources/adbctl/Commands+<Group>.swift`, inside the group's `register…Commands()` function:
   ```swift
   register("device files mv", "<from> <to>", "Rename / move") { context in
       let from = try context.positional(0, "from")
       …
       return CommandOutput(json: ["moved": to]) { print("\(from) → \(to)") }
   }
   ```
   - Path words (`"device files mv"`) define nesting in `adbctl help`; usage string lists args; summary is one English line.
   - Resolve the device with `try context.serial()`; options via `context.args.option("--name", "-n")`, boolean flags via
     `context.args.has("--force")`, integers via `context.args.intOption(...)` (see `Arguments.swift`); local writes use
     `conflictPolicy(context.args)`.
   - Return `CommandOutput(json:human:)`; the JSON is the stable contract (`jsonVersion` is in the envelope — bump it if you change
     an existing shape; adding fields is fine).
3. **A new group** must also be registered in `main.swift`.
4. **Errors:** throw `CLIError` / library errors with English, human-first messages.
5. **Test:** unit tests for the library and any parsing; argument handling in `Tests/` where practical.
6. **Docs:** add a line to `README.md` CLI section only if it is a headline command; always update `CHANGELOG.md`.
7. **Verify:** `swift build && swift test`, then run `swift run adbctl help` and `<command> --help`; exercise it against an emulator
   with `--json-output -` (the `verify-app` skill's privacy rules apply).
