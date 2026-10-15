# Agent instructions

The authoritative project guide for AI coding agents is [CLAUDE.md](CLAUDE.md). Read it before making changes; it points to the
rules in `.claude/rules/` and the procedures in `.claude/skills/`. The short version:

- Build/test: `scripts/fetch-scrcpy-server.sh` once, then `swift build && swift test`.
- Never use a physical device for tests or screenshots; integration tests are emulator-only.
- English only. UI follows `docs/design/`. Shell-interpolated values go through `SettingChange.shellQuote`.
- Do not rewrite history, force-push, publish or release unless asked.
- Commits: Conventional Commits (`type(scope): summary`), only when asked; never push or rewrite history (see `docs/GIT_WORKFLOW.md`).
