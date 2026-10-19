#!/usr/bin/env bash
# Runs one QA swarm lane: boots its own EAS cloud simulator (iOS) or
# emulator (Android) with the repacked or freshly built binary
# preinstalled and launched (--build-id), lets an agent
# execute the flow in .eas/qa-flows/<FLOW>.md, deploys the screenshot
# evidence to EAS Hosting at alias qa-<PLATFORM>-<FLOW>-evidence, emits
# timing metrics, and exits with the verdict (PASS -> 0, else 1) so the
# lane's job status mirrors the QA result.
# Requires: BUILD_ID, FLOW, EXPO_TOKEN_SIMULATOR,
#           the agent runner's credentials (scripts/agent/run-agent.sh)
# Optional: PLATFORM (ios | android; default ios)
#           BUILD_STATUS, REPACK_STATUS (upstream job statuses)
#           PR_NUMBER (names the session after the PR when set)
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh   # eas (pinned), normalize_verdict, ...
BOT=$(bot_handle)

APP_ID=$(app_id)   # from app.json; the bundle id is also the Android package
EVIDENCE_DIR="evidence"
PLATFORM=${PLATFORM:-ios}
: "${FLOW:?FLOW env is required (tasks | add | done)}"
case "$PLATFORM" in ios|android) ;; *) echo "PLATFORM must be ios or android, got '${PLATFORM}'."; exit 1 ;; esac
# A platform-specific flow file (<flow>.<platform>.md) wins over the shared
# one; the Android tasks lane uses this.
FLOW_FILE=".eas/qa-flows/${FLOW}.${PLATFORM}.md"
[ -f "$FLOW_FILE" ] || FLOW_FILE=".eas/qa-flows/${FLOW}.md"
[ -f "$FLOW_FILE" ] || { echo "Unknown flow: ${FLOW}"; exit 1; }
LANE="${PLATFORM}-${FLOW}"
case "$PLATFORM" in
  ios) LANE_LABEL="iOS · ${FLOW}"; DEVICE_KIND="simulator" ;;
  android) LANE_LABEL="Android · ${FLOW}"; DEVICE_KIND="emulator" ;;
esac
# An uninterpolated "${{ inputs.pr_number }}" or an empty string both mean
# "no PR".
if ! [[ "${PR_NUMBER:-}" =~ ^[0-9]+$ ]]; then PR_NUMBER=""; fi

# Wall clock for the metrics line. T0 is lane start; the session bills
# from simulator:start until simulator:stop.
T0=$(date +%s)
use_simulator_token
use_agent_token

# The session bills until stopped; stop it on every exit path. Each lane
# runs on its own worker, so the dotenv default targets this lane's
# session only.
cleanup() {
  eas simulator:stop --non-interactive >/dev/null 2>&1 || true
}
trap cleanup EXIT

require_build "${PLATFORM} binary to test against"

# The evidence folder is uploaded as the lane's artifact even when the lane
# fails, and an empty folder fails the upload step. The marker names the
# lane; the evidence site reads only images and clips, so it is ignored there.
mkdir -p "$EVIDENCE_DIR"
printf 'lane=%s\nplatform=%s\nbuild=%s\n' "$LANE" "$PLATFORM" "$BUILD_ID" > "$EVIDENCE_DIR/lane.txt"

mkdir -p "$EVIDENCE_DIR"

echo "QA lane '${LANE}' against binary $BUILD_ID (repacked or built with this checkout's JS)"

# --build-id installs and launches the binary before the session is ready.
# --tag groups the five lanes on the expo.dev Simulator sessions page.
if [ -n "$PR_NUMBER" ]; then
  SESSION_NAME="PR #${PR_NUMBER} QA swarm: ${LANE_LABEL}"
else
  SESSION_NAME="QA swarm: ${LANE_LABEL}"
fi
T_START=$(date +%s)
# eas-cli waits at most 15 min for the session to be ready and stops it
# on timeout (seen in practice: Android boots of 3m19s, 6m35s, and one
# over 15m). start_simulator_session (comment-lib.sh) retries with a
# fresh session, which rescues a slow boot or a service hiccup.
start_simulator_session --platform "$PLATFORM" --type argent \
      --build-id "$BUILD_ID" \
      --tag qa-swarm \
      --max-duration-minutes 30 --non-interactive --name "${SESSION_NAME:0:50}" || exit 1

wait_for_session
T_LIVE=$(date +%s)
echo "Session live after $(fmt_dur $((T_LIVE - T_START)))"

load_argent_session

argent_device

# The binary is already installed and launched (simulator:start
# --build-id) and carries this checkout's JS as its embedded bundle, so
# no update download is needed. The describe poll below waits for the
# home screen, so only a short settle pause is needed here.
sleep 3

# Deterministic floor beneath the AI tester: the Tasks screen ("Add a
# task") is on screen (polls, relaunches once; comment-lib.sh).
wait_for_home "Add a task"

# Prompts live in the repo (YAML has a 16 kB server limit).
cp .eas/qa-swarm-prompt.md /tmp/qa-prompt.md
# Seen in practice: Android screenshots fail at --scale 1 ("wrong data
# size"); 0.9 gives 648x1440 on the EAS emulator. iOS is fine at 1.
case "$PLATFORM" in ios) SHOT_SCALE=1 ;; android) SHOT_SCALE=0.9 ;; esac
printf '\nThis lane runs on: %s (%s %s)\n' "$PLATFORM" "$PLATFORM" "$DEVICE_KIND" >> /tmp/qa-prompt.md
printf 'The device udid for every argent command is: %s\n' "$UDID" >> /tmp/qa-prompt.md
printf 'The app id (<app-id>) for every --bundleId flag is: %s\n' "$APP_ID" >> /tmp/qa-prompt.md
printf 'The screenshot --scale for this lane is: %s (never use another value)\n' "$SHOT_SCALE" >> /tmp/qa-prompt.md
printf '\n--- The flow this lane must execute ---\n\n' >> /tmp/qa-prompt.md
cat "$FLOW_FILE" >> /tmp/qa-prompt.md

# argent.sh appends every `argent run <tool>` name here; the metrics line
# counts device commands and taps from it.
export ARGENT_CALL_LOG=/tmp/qa-argent-calls.log
rm -f "$ARGENT_CALL_LOG"

echo "Running QA agent for lane '${LANE}'..."
# The verdict file is the contract; the agent's exit code is not.
rm -f /tmp/qa-verdict.md
bash scripts/agent/run-agent.sh run --prompt-file /tmp/qa-prompt.md \
  --profile simulator --max-turns 50 --timeout 10m
T_VERDICT=$(date +%s)

if [ ! -s /tmp/qa-verdict.md ]; then
  echo "FAIL: QA agent produced no verdict (agent error, timeout, or runaway)." > /tmp/qa-verdict.md
fi
# normalize_verdict makes line 1 unambiguous: a line that mentions FAIL is a
# FAIL even when it starts with "PASS:" (seen in practice).
VERDICT_LINE=$(normalize_verdict "$(head -n 1 /tmp/qa-verdict.md)")
echo "================ VERDICT (${LANE}) ================"
cat /tmp/qa-verdict.md
echo "==================================================="

# The session stops inside `evidence_tool run --stop` below, right after
# the metrics line is computed; it bills until then.
T_STOP=$(date +%s)

# Metrics: lane wall clock (start -> verdict), boot, agent flow time,
# device command counts, and billed session minutes.
TOTAL=$((T_VERDICT - T0))
BOOT=$((T_LIVE - T_START))
FLOW_S=$((T_VERDICT - T_LIVE))
CMDS=0; TAPS=0
if [ -f "$ARGENT_CALL_LOG" ]; then
  CMDS=$(wc -l < "$ARGENT_CALL_LOG" | tr -d ' ')
  TAPS=$(grep -c '^gesture-tap$' "$ARGENT_CALL_LOG" || true)
fi
SIM_MIN=$(awk "BEGIN { printf \"%.1f\", ($T_STOP - $T_START) / 60 }")
METRICS="⏱ $(fmt_dur "$TOTAL") lane (boot $(fmt_dur "$BOOT"), agent $(fmt_dur "$FLOW_S")) · ${CMDS} device commands, ${TAPS} taps · ${SIM_MIN} ${DEVICE_KIND}-min"
echo "Metrics: $METRICS"

# The evidence site, by eas-simulator-evidence: the session's own
# artifacts (per-second cpu/mem, the action timeline, the full screen
# recording) become its timeline and performance sections, the rest of
# the verdict file becomes its report, and it deploys under a stable
# per-lane alias. --stop: the tool stops the session (the id is in the
# environment from .env.eas-simulator), then waits for its artifacts. A
# missing artifact never fails the lane; a build or deploy failure does.
# --json puts the summary on the last stdout line.
RUN_JSON=$(evidence_tool run "$EVIDENCE_DIR" --stop \
  --subject "QA swarm · ${LANE_LABEL}" \
  --verdict "$VERDICT_LINE" --verdict-file /tmp/qa-verdict.md \
  --agent "${BOT#@}" --lane "$LANE_LABEL" --build-id "$BUILD_ID" \
  --extra "metrics=${METRICS}" \
  --deploy-alias "qa-${LANE}-evidence" --json)
EVIDENCE_URL=$(node -e "
  const last = process.argv[1].trim().split('\n').pop();
  console.log(JSON.parse(last).url ?? '');
" "$RUN_JSON")
echo "Evidence site: $EVIDENCE_URL"

# Two thumbnails per lane; the swarm report stitches five lanes into one
# row on the PR comment. Single line, so it survives set-output.
THUMBS=$(evidence_tool thumbs "$EVIDENCE_DIR" "$EVIDENCE_URL" --max 2 | tr -d '\n')

set-output verdict "$VERDICT_LINE"
set-output evidence_url "$EVIDENCE_URL"
set-output metrics "$METRICS"
set-output seconds "$TOTAL"
set-output sim_minutes "$SIM_MIN"
set-output thumbs "$THUMBS"

# The lane's job status is the QA result.
case "$VERDICT_LINE" in
  PASS:*) exit 0 ;;
  *) exit 1 ;;
esac
