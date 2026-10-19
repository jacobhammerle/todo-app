#!/usr/bin/env bash
# Runs after an issue is REPLICATED on the cloud simulator: clones the
# base branch, lets an agent write a minimal fix, gates it with
# tsc, pushes expo-bot/issue-N, and opens a PR that closes the issue.
# Writes the PR URL to /tmp/fix-pr-url; an empty file means no fix was
# made (the reason is in /tmp/fix-summary.md). With AUTO_VERIFY=true it
# also dispatches expo-bot-verify.yml on the PR and writes the run URL to
# /tmp/fix-verify-run-url.
# Requires: ISSUE_NUMBER, BASE_BRANCH, GITHUB_TOKEN, EVIDENCE_URL,
#           VERDICT_LINE, the agent runner's credentials (scripts/agent/run-agent.sh)
# Optional: AUTO_VERIFY (default true; "false" skips the verify dispatch),
#           EXPO_TOKEN (needed to dispatch the verify run),
#           GH_REPO (owner/repo; default: package.json "repository")
# Expects /tmp/issue-info.json and /tmp/issue-verdict.md from validate-issue.sh.
set -euo pipefail

ORIG_DIR=$(pwd)
# shellcheck disable=SC1091
. "$ORIG_DIR/scripts/agent/comment-lib.sh"
BOT=$(bot_handle)
GH_REPO=$(repo_slug)
export GH_REPO
FIX_DIR=/tmp/fix-repo
FIX_BRANCH="${BOT#@}/issue-${ISSUE_NUMBER}"
: > /tmp/fix-pr-url
: > /tmp/fix-verify-run-url
rm -rf "$FIX_DIR" /tmp/fix-summary.md

# The workflow checkout has no pushable git remote, so work in a real
# clone. Its node_modules are reused (same branch, same lockfile) so the
# tsc gate runs without a second install.
git clone --depth 1 --branch "$BASE_BRANCH" \
  "https://x-access-token:${GITHUB_TOKEN}@github.com/${GH_REPO}.git" "$FIX_DIR"
ln -s "$ORIG_DIR/node_modules" "$FIX_DIR/node_modules"
# .gitignore's "node_modules/" matches directories only; a symlink is a
# file to git, so without this `git add -A` commits the link into the PR.
echo "node_modules" >> "$FIX_DIR/.git/info/exclude"

cp .eas/expo-bot-fix-prompt.md /tmp/fix-prompt.md
printf '\nThe issue under fix is #%s on %s.\n' "$ISSUE_NUMBER" "$GH_REPO" >> /tmp/fix-prompt.md

use_agent_token
echo "Running the fix agent..."
cd "$FIX_DIR"
# The summary file is the contract; the agent's exit code is not.
bash "$ORIG_DIR/scripts/agent/run-agent.sh" run --prompt-file /tmp/fix-prompt.md \
  --profile fix --max-turns 80 --timeout 10m

if [ -z "$(git status --porcelain)" ]; then
  echo "Fix agent made no change; the reason (if given) is in /tmp/fix-summary.md."
  exit 0
fi

# Hard gate: never push code that does not type-check or lint clean (the
# PR preview workflow runs the same two checks and would go red). On a
# failure, replace the agent's summary: its line 1 would otherwise read as
# the "no PR" reason on the issue comment.
if ! npx tsc --noEmit || ! npx expo lint; then
  echo "No fix: the agent's change did not pass the tsc/lint gate; the failing check is in the workflow logs." > /tmp/fix-summary.md
  exit 1
fi

SUMMARY_LINE=$(head -n 1 /tmp/fix-summary.md 2>/dev/null || true)
[ -n "$SUMMARY_LINE" ] || SUMMARY_LINE="Fix the behavior reported in issue #${ISSUE_NUMBER}"
# Drop leading blank lines so the PR body has no gap before the write-up.
DETAILS=$(tail -n +2 /tmp/fix-summary.md 2>/dev/null | sed '/./,$!d' || true)

# The github-actions[bot] noreply address: commits show the bot avatar and
# the address does not deliver mail.
git config user.name "${BOT#@}"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -b "$FIX_BRANCH"
git add -A
git commit -m "${BOT#@}: ${SUMMARY_LINE}" \
  -m "Fixes #${ISSUE_NUMBER}. Replicated on an EAS cloud simulator, then fixed, via an ${BOT} issue comment."
# The branch is bot-owned: force push so re-triaging the issue replaces it.
git push --force origin "$FIX_BRANCH"

ISSUE_TITLE=$(node -e "console.log(JSON.parse(require('fs').readFileSync('/tmp/issue-info.json','utf8')).title)")
if [[ "$VERDICT_LINE" == CONFIRMED* ]]; then
  KIND_WORD="implementation"; DID_WORD="confirmed the capability is missing"
else
  KIND_WORD="fix"; DID_WORD="replicated the report"
fi
# Replication screenshots, inline, so the PR shows the bug it fixes.
THUMBS=$(evidence_thumbs "$ORIG_DIR/evidence" "$EVIDENCE_URL")

# The agent writes three "### " sections. "What changed" stays visible;
# the why and the file list fold away (the diff tab has the files anyway).
# If the sections are missing, the whole write-up stays visible.
CHANGED=$(printf '%s\n' "$DETAILS" | awk '/^### What changed/{f=1} /^### / && !/^### What changed/{f=0} f')
if [ -n "$CHANGED" ]; then
  REST=$(printf '%s\n' "$DETAILS" | awk '/^### What changed/{f=1; next} /^### /{f=0} !f' | sed '/./,$!d')
  WRITEUP="${CHANGED}

<details>
<summary>What was wrong, files touched</summary>

${REST}

</details>"
else
  WRITEUP="$DETAILS"
fi

if [ "${AUTO_VERIFY:-true}" != "false" ]; then
  NEXT_LINE="**Posted below as they complete:** code review · agent verification on a second cloud simulator · this PR's own \`pr-<number>\` update channel to surf to from the Admin tab."
else
  NEXT_LINE="**Not verified yet:** comment \`${BOT}\` on this PR for a code review and a cloud-simulator check."
fi

# Same shape as every bot post: "## 🤖 <stage>", bold label lines, the
# evidence thumbnails, the agent's write-up, then what lands on the PR next.
PR_BODY="## 🤖 Automated ${KIND_WORD} for #${ISSUE_NUMBER}

**Issue:** #${ISSUE_NUMBER} ${ISSUE_TITLE}
**Replication verdict:** $(verdict_badge "$VERDICT_LINE")
**Evidence:** [screenshots](${EVIDENCE_URL}) — an agent ${DID_WORD} on an EAS cloud simulator; an agent wrote the ${KIND_WORD}; \`tsc\` and lint pass

${THUMBS}

${WRITEUP}

${NEXT_LINE}

Closes #${ISSUE_NUMBER}. _Opened by the expo-bot-issue EAS workflow._"

PR_JSON=$(node "$ORIG_DIR/scripts/agent/gh.mjs" create-pr \
  "${SUMMARY_LINE} (#${ISSUE_NUMBER})" "$FIX_BRANCH" "$BASE_BRANCH" "$PR_BODY")
PR_URL=$(node -e "console.log(JSON.parse(process.argv[1]).url)" "$PR_JSON")
PR_NUMBER=$(node -e "console.log(JSON.parse(process.argv[1]).number)" "$PR_JSON")
echo "Opened fix PR: $PR_URL"
printf '%s' "$PR_URL" > /tmp/fix-pr-url

if [ "${AUTO_VERIFY:-true}" != "false" ]; then
  # Dispatch from this clone, not the workflow checkout: workflow:run
  # uploads the current tree, and expo-bot-verify must see the PR's code
  # (the @expo-bot bridge does the same by checking out the PR head).
  # A dispatch failure is reported, not fatal: the PR still exists and a
  # human can comment @expo-bot on it.
  echo "Dispatching expo-bot-verify on PR #$PR_NUMBER..."
  VERIFY_INSTRUCTION=$(printf "This PR was opened by ${BOT} for issue #%s (%s). Verify that behavior specifically: %s" \
    "$ISSUE_NUMBER" "$ISSUE_TITLE" "$VERDICT_LINE")
  VERIFY_OUT=$(eas workflow:run .eas/workflows/expo-bot-verify.yml \
    --input "pr_number=${PR_NUMBER}" \
    --input "instruction=${VERIFY_INSTRUCTION}" \
    --non-interactive 2>&1 | tee /dev/stderr) || true
  printf '%s' "$VERIFY_OUT" | grep -oE 'https://expo\.dev[^[:space:]]*' | head -n 1 > /tmp/fix-verify-run-url || true
fi
