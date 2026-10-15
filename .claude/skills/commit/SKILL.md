---
name: commit
description: Create a git commit that follows the project's Conventional Commits rules and hooks. Use only when the user asks to commit; never push or amend unless asked.
---

# Commit

Read `.claude/rules/git.md` (full policy: `docs/GIT_WORKFLOW.md`).

1. `git status` and `git diff` (staged and unstaged). Decide what belongs in **one logical change**; if the work mixes concerns,
   propose splitting into several commits.
2. Code changes: run the `verify-app` skill steps 1–2 (`swift build`, `swift test`). Do not commit a red build.
3. Stage explicit paths (`git add path/…`), then read `git diff --staged`. Remove anything forbidden: jars/binaries, credentials,
   screenshots outside `scripts/assets/`/`docs/assets/`, local settings, personal or device data.
4. Pick `type` and `scope` from the tables in `docs/GIT_WORKFLOW.md`. Write the subject (imperative, lowercase, ≤ 72, no period)
   and a body that explains **why**. Breaking change → `!` and a `BREAKING CHANGE:` footer.
5. Dry-run the subject: `scripts/check-commit-message.sh -s "<subject>"`.
6. Commit with a heredoc (preserves the body), adding any attribution trailers the session requires. Let the hooks run; if one
   fails, fix the cause and create a **new** commit — never `--no-verify`, never amend a commit that was already pushed.
7. Update `CHANGELOG.md` (Unreleased) in the same commit for `feat`/`fix`/`perf` that users will notice.
8. Show `git log -1 --stat`. Do **not** push unless the user asks.
