# Git and commits

Full rules: `docs/GIT_WORKFLOW.md`. Short form for agents:

- Commit **only when asked**. Never push, force-push, tag, amend published commits, rewrite history or merge unless asked.
  Never use `--no-verify`, `git reset --hard`, `git filter-*`, or `-f`/`--force` on pushes (denied in `.claude/settings.json`).
- Message: `<type>(<scope>)<!>: <imperative lowercase summary ≤ 72, no period>`, blank line, body explaining **why** (wrap 72).
  Types: feat fix docs style refactor perf test build ci chore revert. Scopes: adbkit scrcpykit emulatorkit adbctl app design
  scripts docs ci deps release repo. Breaking change: `!` + `BREAKING CHANGE:` footer.
- Validate before committing: `scripts/check-commit-message.sh -s "<subject>"`. Hooks run via `scripts/install-git-hooks.sh`.
- One logical change per commit; do not mix refactor and behaviour changes. Stage explicit paths, not `git add -A` blindly —
  read `git diff --staged` first.
- Never stage: binaries/jars, credentials, screenshots outside `scripts/assets/` or `docs/assets/`, local settings, anything
  containing device content or personal data.
- Run `swift build && swift test` (see the `verify-app` skill) before committing code changes.
- Follow any attribution/trailer lines the session or user requires; do not invent others. No session or tool links in the
  message body beyond what the harness requires.
- Branches: `<type>/<kebab-description>`. PR titles are valid commit subjects (squash merge).
