#!/bin/bash
# One-time setup per clone: use the repo's hooks and commit template (repo-local config only).
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
git config commit.template .gitmessage
chmod +x .githooks/* scripts/check-commit-message.sh
echo "Git hooks enabled (core.hooksPath=.githooks) and commit template set."
command -v gitleaks >/dev/null || echo "Tip: brew install gitleaks (the pre-commit hook scans staged changes with it)."
