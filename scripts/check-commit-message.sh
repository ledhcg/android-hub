#!/bin/bash
# Validates a commit message (or a PR title) against docs/GIT_WORKFLOW.md.
#   scripts/check-commit-message.sh <message-file>
#   scripts/check-commit-message.sh -s "<subject line>"
# Used by .githooks/commit-msg and by CI.
set -euo pipefail

TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
SCOPES="adbkit|scrcpykit|emulatorkit|adbctl|app|design|scripts|docs|ci|deps|release|repo"
MAX=72

if [[ "${1:-}" == "-s" ]]; then
    SUBJECT="${2:-}"
    BODY=""
else
    FILE="${1:?usage: check-commit-message.sh <message-file> | -s <subject>}"
    # Ignore comment lines (git's template) and leading blank lines.
    CLEAN="$(grep -v '^#' "$FILE" | sed '/./,$!d')"
    SUBJECT="$(printf '%s\n' "$CLEAN" | head -n1)"
    BODY="$(printf '%s\n' "$CLEAN" | tail -n +2)"
fi

fail() {
    echo "error: $1" >&2
    echo "  subject: $SUBJECT" >&2
    echo "  expected: <type>(<scope>)<!>: <imperative summary>   — see docs/GIT_WORKFLOW.md" >&2
    echo "  types:  ${TYPES//|/, }" >&2
    echo "  scopes: ${SCOPES//|/, } (scope is optional)" >&2
    exit 1
}

# Git-generated subjects are fine.
case "$SUBJECT" in
    "Merge "* | "Revert \""* | "fixup! "* | "squash! "* | "amend! "*) exit 0 ;;
esac

[[ -n "$SUBJECT" ]] || fail "empty subject"

# GitHub appends " (#123)" to squash-merge subjects; it is not part of what the author wrote, so judge the rest.
SUBJECT="$(printf '%s' "$SUBJECT" | sed -E 's/ \(#[0-9]+\)$//')"

# The first release commit is the only free-form one.
[[ "$SUBJECT" == "Initial commit" ]] && exit 0

PATTERN="^(${TYPES})(\((${SCOPES})\))?!?: .+"
[[ "$SUBJECT" =~ $PATTERN ]] || fail "subject must match '<type>(<scope>): <summary>'"

SUMMARY="${SUBJECT#*: }"
(( ${#SUBJECT} <= MAX )) || fail "subject is ${#SUBJECT} characters; keep it to ${MAX} or fewer"
[[ "$SUMMARY" != *"." ]] || fail "no trailing period in the subject"
[[ "$SUMMARY" =~ ^[a-z0-9\`\"\'] ]] || fail "start the summary in lowercase (imperative: 'add', 'fix', 'remove')"

if [[ -n "$BODY" ]]; then
    FIRST_BODY_LINE="$(printf '%s\n' "$BODY" | head -n1)"
    [[ -z "$FIRST_BODY_LINE" ]] || fail "leave a blank line between the subject and the body"
fi
exit 0
