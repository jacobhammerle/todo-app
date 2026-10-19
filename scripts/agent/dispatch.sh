#!/usr/bin/env bash
# Dispatches the EAS workflow behind a bot-mention mode and posts the
# status comment, or the failure comment when the dispatch does not start.
#   full, review -> expo-bot-verify.yml  review the diff + verify on a cloud simulator
#   preview      -> pr-live-preview.yml  a cloud simulator streamed to the browser
#   issue        -> expo-bot-issue.yml   replicate the issue, fix it, verify the fix
# Run from the project root: `eas workflow:run` uploads this checkout, so
# every EAS job sees the code that is checked out here.
#
# Requires: MODE and INSTRUCTION (from parse-bot-comment.sh), ISSUE_NUMBER,
#           ACTOR, ACTION_RUN_URL (this Action run, for the failure comment),
#           EXPO_TOKEN, GH_TOKEN, GH_REPO; BASE_BRANCH in issue mode.
# Writes run_url=<EAS run> to GITHUB_OUTPUT when that file is set.
# DRY_RUN=1 prints the eas command and the comment instead of running them.
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh   # eas (pinned eas-cli)

: "${MODE:?MODE is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${ACTOR:?ACTOR is required}"
INSTRUCTION="${INSTRUCTION:-}"
BOT=$(bot_handle)
ACTION_RUN_URL="${ACTION_RUN_URL:-}"

INPUTS=()
case "$MODE" in
  full|review)
    WORKFLOW=.eas/workflows/expo-bot-verify.yml
    NAME=verification
    HEADING="🤖 Agent verification"
    STATUS="Reviewing the diff and checking this PR's app on an EAS cloud simulator"
    NOTE="Review, verdict, evidence, and this PR's \`pr-${ISSUE_NUMBER}\` update channel land here as they complete."
    RETRY="${BOT} review"
    INPUTS=(--input "pr_number=${ISSUE_NUMBER}" --input "instruction=${INSTRUCTION}")
    ;;
  preview)
    # "preview [minutes] [ios|android] [device]", words in any order.
    PARSED=$(bash scripts/agent/parse-preview-args.sh "$INSTRUCTION")
    echo "$PARSED"
    DURATION=$(printf '%s\n' "$PARSED" | sed -n 's/^duration=//p')
    PLATFORM=$(printf '%s\n' "$PARSED" | sed -n 's/^platform=//p')
    DEVICE=$(printf '%s\n' "$PARSED" | sed -n 's/^device=//p')
    TARGET_TEXT="EAS cloud iOS simulator"
    [ "$PLATFORM" = "android" ] && TARGET_TEXT="EAS cloud Android emulator"
    [ -n "$DEVICE" ] && TARGET_TEXT="${TARGET_TEXT} (${DEVICE})"
    WORKFLOW=.eas/workflows/pr-live-preview.yml
    NAME=preview
    HEADING="🤖 Live preview"
    STATUS="Booting an ${TARGET_TEXT} with this PR's app (${DURATION}-minute session)"
    NOTE="The browser link lands here once the session is live."
    RETRY="${BOT} preview [minutes] [ios|android] [device]"
    INPUTS=(--input "pr_number=${ISSUE_NUMBER}" --input "duration_minutes=${DURATION}" --input "platform=${PLATFORM}")
    # The device input is only sent when set, so the workflow default applies otherwise.
    [ -n "$DEVICE" ] && INPUTS+=(--input "device=${DEVICE}")
    ;;
  issue)
    : "${BASE_BRANCH:?BASE_BRANCH is required in issue mode}"
    WORKFLOW=.eas/workflows/expo-bot-issue.yml
    NAME=triage
    HEADING="🤖 Agent triage"
    STATUS="Replicating the report on an EAS cloud simulator"
    NOTE="Verdict and evidence land here; if it replicates, a fix PR follows and is verified on a second simulator."
    RETRY="${BOT}"
    # auto_verify is the workflow default; passed explicitly so the
    # dispatch reads the same as the TestFlight intake's.
    INPUTS=(--input "issue_number=${ISSUE_NUMBER}" --input "instruction=${INSTRUCTION}" \
            --input "base_branch=${BASE_BRANCH}" --input "auto_verify=true")
    ;;
  *)
    echo "dispatch.sh: unknown mode '${MODE}'." >&2
    exit 1
    ;;
esac

CMD=(eas workflow:run "$WORKFLOW" "${INPUTS[@]}" --non-interactive)
RUN_URL=""
if [ "${DRY_RUN:-}" = "1" ]; then
  echo "--- would run (dry run) ---"
  # `eas` is the comment-lib wrapper; show the version it resolves to.
  printf '%q ' "eas-cli@${EAS_CLI_VERSION}" "${CMD[@]:1}"; echo
  STARTED=1
elif OUT=$("${CMD[@]}" 2>&1 | tee /dev/stderr); then
  # pipefail is on, so a failed dispatch is not hidden by `tee`.
  RUN_URL=$(printf '%s' "$OUT" | grep -oE 'https://expo\.dev[^[:space:]]*' | head -n 1 || true)
  STARTED=1
else
  STARTED=0
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "run_url=${RUN_URL}" >> "$GITHUB_OUTPUT"
fi

if [ "$STARTED" = "1" ]; then
  RUN_LINE=""
  [ -n "$RUN_URL" ] && RUN_LINE=" — [follow the run](${RUN_URL})"
  bash scripts/agent/bot-comment.sh "$HEADING" \
    "**Status:** 🔄 ${STATUS}${RUN_LINE}" "$NOTE"
else
  bash scripts/agent/bot-comment.sh "$HEADING" \
    "⚠️ **Could not start the ${NAME} workflow** — see the [bridge Action logs](${ACTION_RUN_URL}), then comment \`${RETRY}\` to retry."
  exit 1
fi
