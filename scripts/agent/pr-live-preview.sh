#!/usr/bin/env bash
# Boots an EAS cloud iOS simulator or Android emulator running this PR's
# app and comments the browser preview link on the PR. The binary is
# fingerprint-matched (and repacked with the PR's JS) or freshly built by
# the pr-live-preview workflow before this script runs. The session stays
# up until it hits DURATION_MINUTES, so the reviewer can drive the app in
# the browser.
# Requires: BUILD_ID, PR_NUMBER, GITHUB_TOKEN, EXPO_TOKEN_SIMULATOR
# Optional: GH_REPO (owner/repo; default: package.json "repository")
#           DURATION_MINUTES (default 30)
#           PLATFORM (ios|android, default ios)
#           DEVICE   (passed to `simulator:start --device`; iOS Simulator
#                     device name such as "iPhone 16 Pro", or an Android
#                     AVD hardware profile id such as "pixel_7")
#           IOS_BUILD_STATUS, IOS_REPACK_STATUS, ANDROID_BUILD_STATUS,
#           ANDROID_REPACK_STATUS (upstream job statuses; the pair for
#           PLATFORM is used), or BUILD_STATUS / REPACK_STATUS directly
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh

PLATFORM="${PLATFORM:-ios}"
DEVICE="${DEVICE:-}"
DURATION_MINUTES="${DURATION_MINUTES:-30}"
case "$PLATFORM" in
  ios) PLATFORM_LABEL="iOS simulator" ;;
  android) PLATFORM_LABEL="Android emulator" ;;
  *) echo "PLATFORM must be ios or android, got '$PLATFORM'."; exit 1 ;;
esac
# What the PR comment calls the device: the requested name when given,
# else the platform.
DEVICE_LABEL="$PLATFORM_LABEL"
if [ -n "$DEVICE" ]; then
  DEVICE_LABEL="$DEVICE ($PLATFORM_LABEL)"
fi
# The retry hint mirrors the comment that started this run.
RETRY_CMD="@expo-bot preview ${DURATION_MINUTES}"
if [ "$PLATFORM" = "android" ]; then RETRY_CMD="$RETRY_CMD android"; fi
if [ -n "$DEVICE" ]; then RETRY_CMD="$RETRY_CMD $DEVICE"; fi

use_simulator_token
require_env GITHUB_TOKEN "add a GitHub token with pull-request write access as a secret env var in the production EAS environment."

# A run that dies before commenting would leave the PR silent.
COMMENT_POSTED=""
cleanup() {
  code=$?
  if [ "$code" -ne 0 ] && [ -z "$COMMENT_POSTED" ]; then
    node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🤖 Live preview

⚠️ **The $DEVICE_LABEL preview errored before it came alive** — details are in the pr-live-preview run logs on EAS. Comment \`$RETRY_CMD\` to try again, or \`@expo-bot preview\` for the default iOS device.

_Posted by the pr-live-preview EAS workflow._" || true
  fi
}
trap cleanup EXIT

# The workflow passes both platforms' job statuses; pick this platform's.
if [ -z "${BUILD_STATUS:-}" ]; then
  if [ "$PLATFORM" = "android" ]; then
    BUILD_STATUS="${ANDROID_BUILD_STATUS:-}"
    REPACK_STATUS="${ANDROID_REPACK_STATUS:-}"
  else
    BUILD_STATUS="${IOS_BUILD_STATUS:-}"
    REPACK_STATUS="${IOS_REPACK_STATUS:-}"
  fi
fi
require_build "$PLATFORM binary to preview"

# Name the session so the dashboard reads like a history of previewed PRs.
PR_TITLE=$(node scripts/agent/gh.mjs get-pr "$PR_NUMBER" | json_field title)
SESSION_NAME_FULL=$(printf 'PR #%s preview: %s' "$PR_NUMBER" "$PR_TITLE")
SESSION_NAME=${SESSION_NAME_FULL:0:50}

# --build-id installs and launches the binary before the session is
# ready — no artifact download, upload, or manual launch needed.
# --device is only sent when requested; the runner otherwise picks one.
# Seen in practice: the runner does not reject an unknown device name —
# the session still boots — so the name is reported as requested.
START_ARGS=(--platform "$PLATFORM" --type agent-device
  --build-id "$BUILD_ID"
  --max-duration-minutes "$DURATION_MINUTES"
  --name "$SESSION_NAME" --json --non-interactive)
if [ -n "$DEVICE" ]; then
  START_ARGS+=(--device "$DEVICE")
fi
echo "Starting a $DURATION_MINUTES-minute $DEVICE_LABEL session with build $BUILD_ID"
START_JSON=$(eas simulator:start "${START_ARGS[@]}")
SESSION_ID=$(printf '%s' "$START_JSON" | json_field id)
echo "Session $SESSION_ID created; waiting for it to come alive..."

# Polls this session by id (several previews can run at once).
wait_for_session "$SESSION_ID"
PREVIEW_URL=$(eas simulator:get --id "$SESSION_ID" --json --non-interactive | json_field remoteConfig.webPreviewUrl || true)
[ -n "$PREVIEW_URL" ] || { echo "Session is live but reports no webPreviewUrl."; exit 1; }

# Advisory: ask the session's agent-device daemon which device booted.
# simulator:get does not report it. The devices JSON shape has not been
# observed against a cloud session yet, so the raw output goes to the run
# log and the comment only gains a line when a name can be read.
BOOTED_DEVICE=""
DEVICES_JSON=$(eas simulator:exec npx --yes agent-device@latest devices --json 2>/dev/null || true)
if [ -n "$DEVICES_JSON" ]; then
  echo "agent-device devices: $DEVICES_JSON"
  BOOTED_DEVICE=$(printf '%s' "$DEVICES_JSON" | node -e "
    let d = '';
    process.stdin.on('data', c => d += c);
    process.stdin.on('end', () => {
      try {
        const j = JSON.parse(d.slice(d.indexOf('{')));
        const list = (j.data && j.data.devices) || j.devices || [];
        const names = list
          .map(x => x.name || x.model || x.deviceName || '')
          .filter(Boolean);
        console.log(names.join(', '));
      } catch (e) { /* leave empty */ }
    });
  " || true)
fi
DEVICE_LINE=""
if [ -n "$DEVICE" ]; then
  DEVICE_LINE="- 📱 **Device** — requested \`$DEVICE\`"
  if [ -n "$BOOTED_DEVICE" ]; then
    DEVICE_LINE="$DEVICE_LINE; the runner reports \`$BOOTED_DEVICE\`"
  else
    DEVICE_LINE="$DEVICE_LINE; an unknown name is not rejected, so check the device in the preview"
  fi
  DEVICE_LINE="$DEVICE_LINE
"
elif [ -n "$BOOTED_DEVICE" ]; then
  DEVICE_LINE="- 📱 **Device** — \`$BOOTED_DEVICE\` (runner default)
"
fi

node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🤖 Live preview

**Status:** ✅ Ready — **[open the $PLATFORM_LABEL in your browser]($PREVIEW_URL)**

This PR's app is installed and running on an EAS cloud $DEVICE_LABEL.

${DEVICE_LINE}- ⏱️ **Session length** — stops by itself after $DURATION_MINUTES minutes; stop it early with \`eas simulator:stop --id $SESSION_ID\`
- 🔁 **Fresh session** — comment \`@expo-bot preview [minutes] [ios|android] [device]\` again, e.g. \`@expo-bot preview iPhone 16 Pro for 45\` or \`@expo-bot preview android pixel_7\`

_Posted by the pr-live-preview EAS workflow._"
COMMENT_POSTED=1

set-output preview_url "$PREVIEW_URL"
set-output session_id "$SESSION_ID"
set-output device_label "$DEVICE_LABEL"
echo ""
echo "🌐 Live preview ($DEVICE_LABEL): $PREVIEW_URL"
