# Git workflow

How we commit, branch and merge. The rules are enforced by tooling where possible (hooks locally, CI on pull requests), so a
failing check tells you exactly what to fix.

## One-time setup

```bash
scripts/install-git-hooks.sh      # enables .githooks (commit-msg, pre-commit) and the commit template for this clone
brew install gitleaks             # optional but recommended: the pre-commit hook scans staged changes for secrets
```

## Commit messages — Conventional Commits

```
<type>(<scope>)<!>: <imperative summary>

<body: why this change, what it fixes or enables. Wrap at 72.>

<footers: BREAKING CHANGE: …, Fixes #123, Co-authored-by: …>
```

**Subject rules** (checked by `scripts/check-commit-message.sh`): ≤ 72 characters (not counting the ` (#123)` that GitHub adds on squash merge), starts lowercase, imperative mood ("add", "fix",
"remove", not "added"/"adds"), no trailing period, `scope` optional, blank line before the body.

### Types

| Type | Use for | Changelog |
|---|---|---|
| `feat` | New user-visible capability | *Added* |
| `fix` | Bug fix | *Fixed* |
| `perf` | Performance improvement | *Changed* |
| `refactor` | Internal change, no behaviour change | — |
| `style` | Formatting only (no logic) | — |
| `test` | Add or fix tests | — |
| `docs` | Documentation only | — |
| `build` | SwiftPM, build scripts, packaging | — |
| `ci` | GitHub Actions and automation | — |
| `chore` | Maintenance that fits nowhere else | — |
| `revert` | Reverts a previous commit (reference its SHA) | — |

A **breaking change** (CLI flag or JSON shape change without a `jsonVersion` bump path, removed public API, minimum macOS bump)
adds `!` after the type/scope **and** a `BREAKING CHANGE:` footer describing the migration.

### Scopes

| Scope | Paths |
|---|---|
| `adbkit` | `Sources/AdbKit`, `Tests/AdbKitTests` |
| `scrcpykit` | `Sources/ScrcpyKit`, `Tests/ScrcpyKitTests` |
| `emulatorkit` | `Sources/EmulatorKit`, `Tests/EmulatorKitTests` |
| `adbctl` | `Sources/adbctl` |
| `app` | `Sources/AndroidHub` (except `Design/`) |
| `design` | `Sources/AndroidHub/Design`, `docs/design` |
| `scripts` | `scripts/`, `.githooks/` |
| `docs` | other `*.md`, `docs/` |
| `ci` | `.github/` |
| `deps` | dependency or pinned-binary bumps (e.g. scrcpy-server) |
| `release` | version, changelog, packaging for a release |
| `repo` | repo-wide housekeeping (`.gitignore`, license, agent config) |

If a change spans scopes, pick the primary one or omit the scope.

### Examples

```
feat(adbctl): add `device reboot` command
fix(app): center the Start button in the AVD detail view
refactor(adbkit): extract logcat line parsing into a pure function
perf(scrcpykit): avoid copying packets when fanning out to canvases
docs(design): document the status-pill component
build(deps): bump scrcpy-server to 3.4.0

feat(adbctl)!: rename `--json` to `--json-output`

BREAKING CHANGE: scripts must use `--json-output`; `--json` is removed.
```

### Body

Explain *why*, not what the diff shows. Mention user-visible effect, trade-offs and anything a reviewer could miss (security,
device side effects). One logical change per commit; do not mix a refactor with a behaviour change.

## Branches

- `main` is always buildable and green; nobody commits to it directly once the repo is public.
- Branch from `main` as `<type>/<short-kebab-description>`: `feat/files-show-more`, `fix/logs-level-picker`, `docs/git-workflow`.
- Keep branches short-lived and rebased on `main` (`git pull --rebase`). Force-push **only** your own PR branch, using
  `--force-with-lease`. Never rewrite `main` or shared history.

## Pull requests

- Title = a valid commit subject (CI checks it). With **squash merge** this becomes the commit on `main`.
- Fill the template: what/why, how you tested (macOS version, Android version, emulator), checklist.
- UI changes include the [design checklist](design/06-checklist.md) and screenshots **of an emulator only**.
- Keep them small and focused; link issues with `Fixes #123`.
- Merge with **squash and merge**, delete the branch. Linear history, one conventional commit per PR.

## Before you commit

```bash
swift build && swift test         # green, no new warnings
git diff --staged                 # read it; no stray files, debug prints or personal data
```
The hooks then check the message and the staged files.

## What never gets committed

- Binaries and archives (`*.jar`, `*.apk`, `*.dmg`, `*.zip`, video) — the scrcpy jar is fetched by `scripts/fetch-scrcpy-server.sh`.
- Credentials and signing material (`.env`, `*.pem`, `*.p12`, `*.key`, provisioning profiles) and anything gitleaks flags.
- Screenshots or recordings outside `scripts/assets/` and `docs/assets/` — they can show private device content.
- Device serials, account names, emails, file names or any content seen on a device, in tests, docs, commits or issues.
- Machine-local files (`.claude/settings.local.json`, `CLAUDE.local.md`, `.build/`, `build/`).

## Releases and tags

Versions follow SemVer, tags are `vX.Y.Z` and annotated, created only by a maintainer (see the `release` skill). `CHANGELOG.md`
(Keep a Changelog) is updated by hand from `feat`/`fix`/`perf` commits.

## Hooks and CI

| Check | Where | What |
|---|---|---|
| `commit-msg` | local | message format (`scripts/check-commit-message.sh`) |
| `pre-commit` | local | forbidden files, size limit, gitleaks on staged changes |
| Commit lint | CI | PR title (or the pushed commit subject on `main`) |
| CI | CI | build, unit tests, gitleaks over history |

Hooks can be bypassed with `--no-verify`; CI cannot. Do not bypass a hook to push a secret or a binary.

## AI agents

Agents follow exactly the same rules. They commit only when asked, never push, force-push, tag or release on their own, and keep
attribution trailers (`Co-authored-by:`) factual. See [CLAUDE.md](../CLAUDE.md).
