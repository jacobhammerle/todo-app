#!/usr/bin/env bash
# Boots an EAS cloud simulator with the binary the workflow repacked (or
# built) with the base branch's JS, lets Claude Code try to replicate the
# reported issue (screenshots into evidence/),
# deploys the evidence to EAS Hosting, then:
#   REPLICATED     -> fix-issue.sh opens a PR; the issue gets verdict +
#                     PR link + evidence link
#   CONFIRMED      -> (feature request: capability absent) same path, the
#                     PR implements it
#   NOT-REPLICATED -> the issue gets the reasoning + evidence link
# Requires: BUILD_ID, ISSUE_NUMBER, BASE_BRANCH, GITHUB_TOKEN,
#           EXPO_TOKEN_SIMULATOR, CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY
# Optional: GH_REPO (owner/repo; default: package.json "repository")
#           INSTRUCTION (guidance from the @expo-bot comment)
#           BUILD_STATUS, REPACK_STATUS (upstream job statuses)
#           AUTO_VERIFY (default true: fix-issue.sh dispatches expo-bot-verify
#           on the PR; "false" skips it)
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh
APP_ID=$(app_id)
EVIDENCE_DIR="evidence"

use_simulator_token
require_env GITHUB_TOKEN "add a GitHub token with issues, contents, and pull-request write access in the production EAS environment."
use_claude_token

# The session bills until stopped, and a run that dies before commenting
# would leave the issue silent; the trap covers both. On the success path
# `evidence_tool run --stop` below stops the session itself, so the trap
# only stops it on an exit before that point.
COMMENT_POSTED=""
SESSION_STOPPED=""
cleanup() {
  code=$?
  if [ -z "$SESSION_STOPPED" ]; then
    eas simulator:stop --non-interactive >/dev/null 2>&1 || true
  fi
  if [ "$code" -ne 0 ] && [ -z "$COMMENT_POSTED" ]; then
    if [ -s /tmp/issue-verdict.md ]; then
      node scripts/agent/gh.mjs comment "$ISSUE_NUMBER" "## 🤖 Agent triage

**Verdict:** $(verdict_badge "$(normalize_verdict "$(head -n 1 /tmp/issue-verdict.md)" INCONCLUSIVE)")

⚠️ **A later step failed after the verdict** — the full report is in the expo-bot-issue run logs on EAS.

_Posted by the expo-bot-issue EAS workflow._" || true
    else
      node scripts/agent/gh.mjs comment "$ISSUE_NUMBER" "## 🤖 Agent triage

⚠️ **Triage errored before a verdict** — see the expo-bot-issue run logs on EAS, then comment \`@expo-bot\` here to retry.

_Posted by the expo-bot-issue EAS workflow._" || true
    fi
  fi
}
trap cleanup EXIT

require_build "simulator binary to validate against"

mkdir -p "$EVIDENCE_DIR"

# Issue context for the replication prompt and the session name.
node scripts/agent/gh.mjs get-issue "$ISSUE_NUMBER" > /tmp/issue-info.json
ISSUE_TITLE=$(node -e "console.log(JSON.parse(require('fs').readFileSync('/tmp/issue-info.json','utf8')).title)")

echo "Replicating issue #$ISSUE_NUMBER against binary $BUILD_ID (repacked or built with $BASE_BRANCH JS)"

# Name the session so the dashboard reads like a triage history.
# --build-id installs and launches the binary before the session is ready.
SESSION_NAME_FULL=$(printf 'Issue #%s expo-bot: %s' "$ISSUE_NUMBER" "$ISSUE_TITLE")
SESSION_NAME=${SESSION_NAME_FULL:0:50}
eas simulator:start --platform ios --type argent \
  --build-id "$BUILD_ID" \
  --max-duration-minutes 30 --non-interactive --name "$SESSION_NAME"

wait_for_session

load_argent_session

argent_device

# The binary is already installed and launched (simulator:start
# --build-id) and carries the base branch's JS as its embedded bundle, so
# no update download is needed (same reasoning as the PR verify flow).
sleep 15

# Deterministic floor beneath the AI replicator: the Tasks screen ("Add
# a task") is on screen (polls, relaunches once; comment-lib.sh).
wait_for_home "Add a task"

# The replication prompt lives in the repo (YAML has a 16 kB server limit).
cp .eas/expo-bot-issue-prompt.md /tmp/issue-prompt.md
printf '\nThe issue under triage is #%s: "%s".\n' "$ISSUE_NUMBER" "$ISSUE_TITLE" >> /tmp/issue-prompt.md
printf '\nThe device udid for every argent command is: %s\n' "$UDID" >> /tmp/issue-prompt.md
printf 'The app id (<app-id>) for every --bundleId flag is: %s\n' "$APP_ID" >> /tmp/issue-prompt.md
if [ -n "${INSTRUCTION:-}" ]; then
  printf '\nGuidance for this run (from the @expo-bot comment): %s\n' "$INSTRUCTION" >> /tmp/issue-prompt.md
fi

echo "Running Claude replicator..."
# The verdict file is the contract; Claude's own exit code is not. timeout
# is the hard backstop: a hung agent gets killed, leaves no verdict, and
# the run reports inconclusive.
rm -f /tmp/issue-verdict.md
timeout 20m npx --yes @anthropic-ai/claude-code@latest \
  -p "$(cat /tmp/issue-prompt.md)" \
  --model claude-sonnet-5 \
  --max-turns 120 \
  --output-format stream-json --verbose \
  --allowedTools "Bash(bash scripts/agent/argent.sh*),Read,Glob,Grep,Write" \
  | node scripts/agent/claude-log-format.js || true

if [ ! -s /tmp/issue-verdict.md ]; then
  echo "INCONCLUSIVE: the replicator produced no verdict (agent error, timeout, or runaway)." > /tmp/issue-verdict.md
fi
# normalize_verdict collapses a doubled keyword ("CONFIRMED: REPLICATED: ...")
# to the one the agent meant; an unreadable line becomes INCONCLUSIVE.
VERDICT_LINE=$(normalize_verdict "$(head -n 1 /tmp/issue-verdict.md)" INCONCLUSIVE)
echo "================ VERDICT ================"
cat /tmp/issue-verdict.md
echo "========================================="

# The evidence site, by eas-simulator-evidence: the session's own
# artifacts (cpu/mem samples, the action timeline, the full screen
# recording) plus the screenshots and the replicator's report, deployed
# under a per-issue alias. --stop: the tool stops the session as soon as
# the verdict is in (it bills until then; the id is in the environment
# from .env.eas-simulator), then waits for its artifacts. A missing
# artifact never fails triage; a build or deploy failure does. --json
# puts the summary on the last stdout line; its url is the stable alias
# address.
RUN_JSON=$(evidence_tool run "$EVIDENCE_DIR" --stop \
  --subject "Issue #${ISSUE_NUMBER}" \
  --verdict "$VERDICT_LINE" --verdict-file /tmp/issue-verdict.md \
  --agent expo-bot --lane "Issue #${ISSUE_NUMBER}" --build-id "$BUILD_ID" \
  --deploy-alias "issue-${ISSUE_NUMBER}-evidence" --json)
SESSION_STOPPED=1
EVIDENCE_URL=$(node -e "
  const last = process.argv[1].trim().split('\n').pop();
  console.log(JSON.parse(last).url ?? '');
" "$RUN_JSON")
echo "Evidence site: $EVIDENCE_URL"
export EVIDENCE_URL VERDICT_LINE

# Comment ingredients shared by every branch below.
VERDICT_SHOWN=$(verdict_badge "$VERDICT_LINE")
THUMBS=$(evidence_thumbs "$EVIDENCE_DIR" "$EVIDENCE_URL")
REPORT=$(tail -n +2 /tmp/issue-verdict.md)
PR_URL=""
VERIFY_RUN_URL=""

if [[ "$VERDICT_LINE" == REPLICATED* || "$VERDICT_LINE" == CONFIRMED* ]]; then
  # Replicated bug or confirmed feature gap: attempt an automated PR. A
  # fix failure must not eat the verdict — fall through to a
  # replicated-but-unfixed comment.
  if [[ "$VERDICT_LINE" == CONFIRMED* ]]; then
    PR_WORD="Implementation"
  else
    PR_WORD="Fix"
  fi
  bash scripts/agent/fix-issue.sh || true
  PR_URL=$(cat /tmp/fix-pr-url 2>/dev/null || true)

  # fix-issue.sh dispatches expo-bot-verify on the PR unless AUTO_VERIFY is
  # "false"; tell the reporter where that verdict will land.
  VERIFY_RUN_URL=$(cat /tmp/fix-verify-run-url 2>/dev/null || true)
  VERIFY_LINE=""
  if [ -n "$VERIFY_RUN_URL" ]; then
    VERIFY_LINE="
- 🧪 **Verifying** — code review + a second cloud simulator; results and the PR's own update channel land on the PR ([run](${VERIFY_RUN_URL}))"
  elif [ -n "$PR_URL" ]; then
    VERIFY_LINE="
- ⚠️ **Not verified** — comment \`@expo-bot\` on the PR to review and check it on a cloud simulator"
  fi

  # Comment shape shared by every bot post: "## 🤖 <stage>", a verdict
  # line, a short list, the report folded away, a "_Posted by_" footer.
  if [ -n "$PR_URL" ]; then
    node scripts/agent/gh.mjs comment "$ISSUE_NUMBER" "## 🤖 Agent triage

**Verdict:** ${VERDICT_SHOWN}

- 🔧 **${PR_WORD} PR** — ${PR_URL}${VERIFY_LINE}
- 🖼️ **Evidence** — ${EVIDENCE_URL}

${THUMBS}

<details>
<summary>Full report</summary>

${REPORT}

</details>

_Posted by the expo-bot-issue EAS workflow._"
  else
    # The fix agent's line 1 is "No fix: <reason>"; the bullet already
    # says no PR was opened, so keep just the reason. The file is missing
    # when the agent hit its turn limit without writing it: under
    # set -e + pipefail a bare `head file | sed` then
    # exited this script and the issue got a "later step failed" comment
    # instead of this one, so test the file first.
    NO_FIX_REASON=""
    if [ -s /tmp/fix-summary.md ]; then
      NO_FIX_REASON=$(head -n 1 /tmp/fix-summary.md | sed -E 's/^No fix:[[:space:]]*//')
    fi
    [ -n "$NO_FIX_REASON" ] || NO_FIX_REASON="the fix agent errored or timed out; see the workflow logs."
    node scripts/agent/gh.mjs comment "$ISSUE_NUMBER" "## 🤖 Agent triage

**Verdict:** ${VERDICT_SHOWN}

- ⚠️ **No PR opened** — ${NO_FIX_REASON} A human needs to pick this up.
- 🖼️ **Evidence** — ${EVIDENCE_URL}

${THUMBS}

<details>
<summary>Full report</summary>

${REPORT}

</details>

_Posted by the expo-bot-issue EAS workflow._"
  fi
else
  node scripts/agent/gh.mjs comment "$ISSUE_NUMBER" "## 🤖 Agent triage

**Verdict:** ${VERDICT_SHOWN}

- 🖼️ **Evidence** — ${EVIDENCE_URL}

${THUMBS}

<details>
<summary>Full report</summary>

${REPORT}

</details>

_Posted by the expo-bot-issue EAS workflow. Missed something? Comment \`@expo-bot <hint>\` to retry._"
fi
COMMENT_POSTED=1

set-output evidence_url "$EVIDENCE_URL"
set-output verdict "$VERDICT_LINE"
# The same line with its status emoji, for the workflow's report doc.
set-output verdict_shown "$VERDICT_SHOWN"
set-output pr_url "${PR_URL:-none}"
set-output verify_run_url "${VERIFY_RUN_URL:-none}"
