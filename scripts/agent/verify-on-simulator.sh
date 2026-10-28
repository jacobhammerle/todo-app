#!/usr/bin/env bash
# Boots an EAS cloud simulator with the binary the workflow repacked (or
# built) with this PR's JS, lets an agent verify the PR (screenshots
# into evidence/), deploys the evidence to EAS Hosting, comments the result
# on the PR, and emits step outputs.
# Requires: BUILD_ID, PR_NUMBER, GITHUB_TOKEN,
#           the agent runner's credentials (scripts/agent/run-agent.sh)
# Optional: EXPO_TOKEN_SIMULATOR (used first when set; comment-lib.sh)
#           GH_REPO (owner/repo; default: package.json "repository")
#           INSTRUCTION (reviewer guidance from the @expo-bot comment)
#           BUILD_STATUS, REPACK_STATUS (upstream job statuses)
#           UPDATE_CHANNEL (channel the workflow published the PR's JS to;
#           default pr-<PR_NUMBER>), UPDATE_GROUP_ID (that publish's update
#           group, for a deep link) — echoed back as the channel to surf to
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh
BOT=$(bot_handle)
APP_ID=$(app_id)
# app.json owner + slug; used to build expo.dev links.
EXPO_ACCOUNT=$(node -p "require('./app.json').expo.owner")
EXPO_SLUG=$(node -p "require('./app.json').expo.slug")
EVIDENCE_DIR="evidence"

use_simulator_token
require_env GITHUB_TOKEN "add a GitHub token with pull-request write access as a secret env var in the production EAS environment."
use_agent_token
# The session bills until stopped, and a run that dies before commenting
# would leave the PR silent; the trap covers both. It is installed before
# every remaining exit path, and it tells the truth: a reached verdict is
# reported as the verdict even when a later step (evidence deploy, comment)
# failed.
COMMENT_POSTED=""
cleanup() {
  code=$?
  eas simulator:stop --non-interactive >/dev/null 2>&1 || true
  if [ "$code" -ne 0 ] && [ -z "$COMMENT_POSTED" ]; then
    if [ -s /tmp/verify-verdict.md ]; then
      node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🤖 Agent verification

**Verdict:** $(verdict_badge "$(normalize_verdict "$(head -n 1 /tmp/verify-verdict.md)")")

⚠️ **A later step failed after the verdict** — the full report is in the expo-bot-verify run logs on EAS.

_Posted by the expo-bot-verify EAS workflow._" || true
    else
      node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🤖 Agent verification

⚠️ **Verification errored before a verdict** — see the expo-bot-verify run logs on EAS, then comment \`${BOT} review\` to retry.

_Posted by the expo-bot-verify EAS workflow._" || true
    fi
  fi
}
trap cleanup EXIT

require_build "simulator binary to verify against"

mkdir -p "$EVIDENCE_DIR"

# PR context for the verifier prompt and the session name.
node scripts/agent/gh.mjs get-pr "$PR_NUMBER" > /tmp/pr-info.json
PR_TITLE=$(node -e "console.log(JSON.parse(require('fs').readFileSync('/tmp/pr-info.json','utf8')).title)")
node scripts/agent/gh.mjs get-pr-diff "$PR_NUMBER" > /tmp/pr.diff
cap_diff /tmp/pr.diff

echo "Verifying binary $BUILD_ID (repacked or built with this PR's JS)"

# Name the session so the dashboard reads like a history of verified PRs.
# --build-id installs and launches the binary before the session is
# ready — no artifact download, upload, or manual launch needed.
SESSION_NAME_FULL=$(printf 'PR #%s expo-bot: %s' "$PR_NUMBER" "$PR_TITLE")
SESSION_NAME=${SESSION_NAME_FULL:0:50}
start_simulator_session --platform ios --type argent \
  --build-id "$BUILD_ID" \
  --max-duration-minutes 30 --non-interactive --name "$SESSION_NAME" || exit 1

wait_for_session

load_argent_session

argent_device

# The binary is already installed and launched (simulator:start
# --build-id) and carries this PR's JS as its embedded bundle, so no
# update download is needed. Its baked-in channel is still checked on
# launch; expo-updates keeps the newest update, and the repack is newer
# than anything on that channel unless something published there in the
# minutes since the repack. Give the launch a moment to settle.
sleep 15

# Deterministic floor beneath the AI verifier: the Tasks screen ("Add a
# task") is on screen (polls, relaunches once; comment-lib.sh).
wait_for_home "Add a task"

# The verifier prompt lives in the repo (YAML has a 16 kB server limit).
cp .eas/expo-bot-verify-prompt.md /tmp/verify-prompt.md
printf '\nThe PR under test is #%s: "%s".\n' "$PR_NUMBER" "$PR_TITLE" >> /tmp/verify-prompt.md
printf '\nThe device udid for every argent command is: %s\n' "$UDID" >> /tmp/verify-prompt.md
printf 'The app id (<app-id>) for every --bundleId flag is: %s\n' "$APP_ID" >> /tmp/verify-prompt.md
if [ -n "${INSTRUCTION:-}" ]; then
  printf "\nReviewer guidance for this run (from the ${BOT} comment): %s\n" "$INSTRUCTION" >> /tmp/verify-prompt.md
fi

echo "Running the verifier agent..."
# The verdict file is the contract; the agent's exit code is not. The
# timeout is the hard backstop: a hung agent is killed, leaves no verdict,
# and the run fails closed.
bash scripts/agent/run-agent.sh run --prompt-file /tmp/verify-prompt.md \
  --profile simulator --max-turns 120 --timeout 20m

if [ ! -s /tmp/verify-verdict.md ]; then
  echo "FAIL: verifier produced no verdict file (agent error, timeout, or runaway)." > /tmp/verify-verdict.md
fi
# normalize_verdict makes line 1 unambiguous: "PASS: FAIL: ..." (seen in
# practice) is a FAIL, not the PASS a plain glob would read.
VERDICT_LINE=$(normalize_verdict "$(head -n 1 /tmp/verify-verdict.md)")
echo "================ VERDICT ================"
cat /tmp/verify-verdict.md
echo "========================================="

# The evidence site, by eas-simulator-evidence: the session's own
# artifacts (cpu/mem samples, the action timeline, the full screen
# recording) plus the screenshots and the verifier's report, deployed to
# EAS Hosting under a per-PR alias. --stop: the tool stops the session
# as soon as the verdict is in (it bills until then; the id is in the
# environment from .env.eas-simulator), then waits for its artifacts. A
# missing artifact never fails verification; a build or deploy failure
# does. --json puts the summary on the last stdout line; its url is the
# stable alias address.
RUN_JSON=$(evidence_tool run "$EVIDENCE_DIR" --stop \
  --subject "PR #${PR_NUMBER}" \
  --verdict "$VERDICT_LINE" --verdict-file /tmp/verify-verdict.md \
  --agent "${BOT#@}" --lane "PR #${PR_NUMBER}" --build-id "$BUILD_ID" \
  --deploy-alias "pr-${PR_NUMBER}-evidence" --json)
EVIDENCE_URL=$(node -e "
  const last = process.argv[1].trim().split('\n').pop();
  console.log(JSON.parse(last).url ?? '');
" "$RUN_JSON")
echo "Evidence site: $EVIDENCE_URL"

# The workflow's update job published this PR's JS to its own channel.
# That channel is the answer to "where do I see this?": the Admin tab on
# any release build (the TestFlight install included) can surf to it
# live. The group id gives a deep link to the exact update; it is skipped
# when the expression arrived uninterpolated or empty.
UPDATE_CHANNEL=${UPDATE_CHANNEL:-pr-${PR_NUMBER}}
UPDATE_URL=""
if [[ "${UPDATE_GROUP_ID:-}" =~ ^[0-9a-fA-F-]{20,}$ ]]; then
  UPDATE_URL="https://expo.dev/accounts/${EXPO_ACCOUNT}/projects/${EXPO_SLUG}/updates/${UPDATE_GROUP_ID}"
fi
echo "Channel to surf to: $UPDATE_CHANNEL ${UPDATE_URL:+($UPDATE_URL)}"
CHANNEL_LINE="- 📡 **Channel** — \`${UPDATE_CHANNEL}\`: surf to it from the Admin tab on your TestFlight build"
if [ -n "$UPDATE_URL" ]; then
  CHANNEL_LINE="${CHANNEL_LINE} ([update](${UPDATE_URL}))"
fi

# Same shape as every bot post: "## 🤖 <stage>", a verdict line, a short
# list (evidence, channel), the thumbnails, the report folded away, a
# "_Posted by_" footer. The package prints it: the verdict line is the
# normalized one above, and the rest of the verdict file is the report.
node scripts/agent/gh.mjs comment "$PR_NUMBER" "$(evidence_tool comment "$EVIDENCE_DIR" "$EVIDENCE_URL" \
  --verdict "$VERDICT_LINE" --verdict-file /tmp/verify-verdict.md \
  --title "Agent verification" \
  --line "$CHANNEL_LINE" \
  --agent "the expo-bot-verify EAS workflow")"
COMMENT_POSTED=1

set-output evidence_url "$EVIDENCE_URL"
set-output verdict "$VERDICT_LINE"
# The same line with its status emoji, for the workflow's report doc.
set-output verdict_shown "$(verdict_badge "$VERDICT_LINE")"
set-output update_channel "$UPDATE_CHANNEL"
set-output update_url "${UPDATE_URL:-(update group id not captured)}"
