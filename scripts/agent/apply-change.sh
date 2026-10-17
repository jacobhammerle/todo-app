#!/usr/bin/env bash
# Applies the reviewer's @expo-bot instruction to the checked-out PR
# branch: a Claude Code agent edits the code, a tsc gate must pass, and
# the result is committed and pushed to the PR head. Posts a summary
# comment on the PR either way.
# Requires: INSTRUCTION, PR_NUMBER, ACTOR, GH_TOKEN, GH_REPO,
#           CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY (the bridge
#           checks the secret and posts the missing-token comment first)
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh

SUMMARY_FILE=/tmp/expo-bot-change-summary.md
# bot-comment.sh posts on ISSUE_NUMBER; a PR is an issue to the API.
export ISSUE_NUMBER="${ISSUE_NUMBER:-$PR_NUMBER}"

use_claude_token

rm -f "$SUMMARY_FILE"
cp .eas/expo-bot-change-prompt.md /tmp/change-prompt.md
printf '\nThe requested change (from the @expo-bot comment on PR #%s): %s\n' \
  "$PR_NUMBER" "$INSTRUCTION" >> /tmp/change-prompt.md

echo "Running Claude change agent..."
# The summary file is the contract; Claude's own exit code is not.
timeout 10m npx --yes @anthropic-ai/claude-code@latest \
  -p "$(cat /tmp/change-prompt.md)" \
  --model claude-sonnet-5 \
  --max-turns 60 \
  --output-format stream-json --verbose \
  --allowedTools "Edit,Write,Read,Glob,Grep,Bash(npx tsc --noEmit),Bash(npx expo lint)" \
  | node scripts/agent/claude-log-format.js || true

if [ -z "$(git status --porcelain)" ]; then
  REASON=$(cat "$SUMMARY_FILE" 2>/dev/null || echo "The agent gave no reason (error or timeout).")
  bash scripts/agent/bot-comment.sh "🤖 Agent iteration" "**Requested:** _${INSTRUCTION}_

⚠️ **No change made** — ${REASON}"
  exit 1
fi

# Hard gate: never push code that does not type-check or lint clean (the
# PR preview workflow runs the same two checks and would go red).
npx tsc --noEmit
npx expo lint

SUMMARY_LINE=$(head -n 1 "$SUMMARY_FILE" 2>/dev/null || true)
[ -n "$SUMMARY_LINE" ] || SUMMARY_LINE="$INSTRUCTION"

# The github-actions[bot] noreply address: commits show the bot avatar and
# the address does not deliver mail.
git config user.name "expo-bot"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git commit -m "expo-bot: ${SUMMARY_LINE}" \
  -m "Requested via an @expo-bot comment on PR #${PR_NUMBER}."
git push
COMMIT_SHA=$(git rev-parse --short HEAD)

DETAILS=$(tail -n +2 "$SUMMARY_FILE" 2>/dev/null || true)
# Same shape as every bot post: "## 🤖 <stage>", bold label lines, the
# agent's write-up, a "_Posted by_" footer (bot-comment.sh adds it).
bash scripts/agent/bot-comment.sh "🤖 Agent iteration" "**Requested:** _${INSTRUCTION}_

✅ **Applied** — ${SUMMARY_LINE} (\`${COMMIT_SHA}\`, type-check passed)

${DETAILS}"
