#!/usr/bin/env bash
# Shared pieces of the bot comment shape. Source it; do not run it.
#   evidence_tool <cmd> [args...]         -> the eas-simulator-evidence CLI
#   normalize_verdict "<line>" [FALLBACK] -> line 1 of a verdict file, made unambiguous
#   verdict_badge "<verdict line>"        -> the line with a leading status emoji
#   evidence_thumbs <dir> <site_url>      -> an HTML row of screenshot thumbnails
# plus the helpers every simulator-driving script shares: eas, require_env,
# require_build, use_simulator_token, use_agent_token, wait_for_session,
# json_field, load_argent_session, argent_device, wait_for_home, cap_diff,
# fmt_dur (defined below).
# Every bot post shares one layout: "## 🤖 <stage>", a bold Verdict or
# Status line, a short bullet list (PR, evidence, channel), a thumbnail
# row, the full report folded away, and a "_Posted by_" footer.
#
# The verdict grammar, the thumbnails, the evidence site itself, and the
# PR comment shape live in the eas-simulator-evidence package (a
# devDependency; it grew out of this repo's scripts). This file keeps the
# function names the scripts and deploy-gated.yml already use.

# --no-install: run the copy in node_modules and fail loudly when it is
# missing, instead of fetching a floating version from the registry.
evidence_tool() { npx --no-install eas-simulator-evidence "$@"; }

# Project identity, read from the checkout so a fork edits app.json and
# package.json only (run from the project root):
#   app_id    -> the iOS bundle id, which is also the Android package
#   repo_slug -> "owner/repo": GH_REPO when set, else package.json "repository"
app_id() { node -p "require('./app.json').expo.ios.bundleIdentifier"; }
repo_slug() { node scripts/agent/gh.mjs repo; }
# bot_handle -> the mention that drives the bot ("@expo-bot" by default).
# One spot to change it: "botHandle" in package.json. BOT_HANDLE in the
# environment overrides it (the bridge passes the parsed value along).
bot_handle() {
  if [ -n "${BOT_HANDLE:-}" ]; then printf '%s' "$BOT_HANDLE"; return; fi
  node -p "require('./package.json').botHandle || '@expo-bot'"
}

# Line 1 of a verdict file decides the lane result, and agents do not
# always write it cleanly. Seen so far:
#   "PASS: no — FAIL: ..."  an Android lane
#   "PASS: FAIL: ..."       a PR verify lane, where the prompt's
#                           '"PASS: ..." or "FAIL: ..."' copied as one line
# Every reader of a verdict file goes through this function. The package
# collapses a chain of leading keywords to the LAST one, turns a PASS line
# that still mentions FAIL into a FAIL, passes PASS / FAIL / REPLICATED /
# NOT-REPLICATED / CONFIRMED / INCONCLUSIVE through unchanged, and makes
# anything else "<fallback>: malformed verdict line: ...". <fallback> is
# $2 (default FAIL; the issue flow passes INCONCLUSIVE, its own "no
# verdict" word).
normalize_verdict() {
  if [ -n "${2:-}" ]; then
    evidence_tool verdict "$1" --fallback "$2"
  else
    evidence_tool verdict "$1"
  fi
}

# The verdict keyword picks the emoji; the evidence site uses the same
# mapping for its badge color.
verdict_badge() { evidence_tool verdict "$1" --badge; }

# Up to four screenshots from <dir>, in capture order, as linked
# thumbnails served by the evidence site (files sit at the site root).
# Prints nothing when there are no images, so callers can drop it in.
evidence_thumbs() { evidence_tool thumbs "$1" "$2" --max 4; }

# ---------------------------------------------------------------------
# Shared by the simulator-driving scripts (validate-issue, verify-on-
# simulator, qa-flow, pr-live-preview) and the agent runners.

# eas <args...> -> eas-cli, one pinned version for every call: a floating
# @latest can change simulator:* behavior between runs. 26.0.0 is the
# version eas-simulator-evidence 0.2.4 was checked against; exported so
# eas-simulator-evidence (collect, deploy) and intake-testflight.mjs run
# the same one. Set EAS_CLI_VERSION to override.
export EAS_CLI_VERSION="${EAS_CLI_VERSION:-26.0.0}"
eas() { npx --yes "eas-cli@${EAS_CLI_VERSION}" "$@"; }

# require_env NAME "<how to fix>" -> exit 1 with the hint when NAME is empty.
require_env() {
  if [ -z "${!1:-}" ]; then
    echo "$1 is not set; $2"
    exit 1
  fi
}

# require_build "<what>" -> exit 1 when the upstream build or repack job
# failed (BUILD_STATUS / REPACK_STATUS, workflow job statuses) or BUILD_ID
# is empty. <what> names the missing binary, e.g. "ios binary to test".
require_build() {
  if [ "${BUILD_STATUS:-}" = "failure" ]; then
    echo "Upstream build failed; no $1."
    exit 1
  fi
  if [ "${REPACK_STATUS:-}" = "failure" ]; then
    echo "Repacking the binary with this checkout's JS failed; no $1."
    exit 1
  fi
  if [ -z "${BUILD_ID:-}" ]; then
    echo "BUILD_ID is empty; no $1."
    exit 1
  fi
}

# use_simulator_token [optional] -> picks the token for simulator sessions.
# A personal access token stored as the secret EXPO_TOKEN_SIMULATOR is used
# first when it is set. Otherwise the token already in the environment is
# used: on an EAS worker that is the EXPO_TOKEN every workflow run gets,
# on a laptop the eas-cli login. The worker token starts sessions on its
# own; no extra secret is needed for that. A "Not authorized" from
# simulator:start means Expo Simulators is not enabled on the account the
# active token belongs to (check with `eas simulator:availability`), which
# is the one reason to set EXPO_TOKEN_SIMULATOR: a token from an account
# that has access. See SETUP.md. The "optional" argument is accepted for
# older callers and changes nothing.
use_simulator_token() {
  if [ -n "${EXPO_TOKEN_SIMULATOR:-}" ]; then
    export EXPO_TOKEN="$EXPO_TOKEN_SIMULATOR"
  elif [ -n "${EAS_BUILD_RUNNER:-}" ]; then
    echo "EXPO_TOKEN_SIMULATOR is not set; using the workflow run's own EXPO_TOKEN for simulator sessions."
  else
    echo "EXPO_TOKEN_SIMULATOR is not set; using the local eas-cli login for simulator sessions."
  fi
}

# use_agent_token [optional] -> the agent runner's credentials must be
# present (scripts/agent/run-agent.sh check, which knows the runner's
# variable names). With "optional", AGENT_AVAILABLE is exported as 1 or 0
# instead of failing, so a caller can skip the agent step.
use_agent_token() {
  if [ "${1:-}" = "optional" ]; then
    if bash scripts/agent/run-agent.sh check optional; then
      export AGENT_AVAILABLE=1
    else
      export AGENT_AVAILABLE=0
      echo "No agent credentials: the agent step is skipped."
    fi
    return 0
  fi
  bash scripts/agent/run-agent.sh check
}

# start_simulator_session <simulator:start args...> -> up to three attempts
# with a pause between them. Seen in practice: a session that errors
# before its tool-server is ready, and a "Service Unavailable" on the
# retry straight after it; the pause lets the service settle.
start_simulator_session() {
  local attempt
  for attempt in 1 2 3; do
    if eas simulator:start "$@"; then
      return 0
    fi
    if [ "$attempt" -eq 3 ]; then
      echo "simulator:start failed three times; giving up."
      return 1
    fi
    echo "simulator:start failed (attempt ${attempt}); starting a fresh session in 30s..."
    sleep 30
  done
}

# wait_for_session [session-id] -> poll simulator:get (up to 16 min) until
# the session is IN_PROGRESS and has its remoteConfig; exit 1 when it
# stopped or errored. Without an id, the dotenv default session is polled.
wait_for_session() {
  local i s id=()
  [ -n "${1:-}" ] && id=(--id "$1")
  for i in $(seq 1 64); do
    s=$(eas simulator:get ${id[@]+"${id[@]}"} --json --non-interactive 2>/dev/null || true)
    if echo "$s" | grep -q '"status": "IN_PROGRESS"' && echo "$s" | grep -q remoteConfig; then
      return 0
    fi
    if echo "$s" | grep -qE '"status": "(STOPPED|ERRORED)"'; then
      echo "Simulator session failed to boot."
      exit 1
    fi
    sleep 15
  done
  echo "Session not ready in time."
  exit 1
}

# json_field <path> -> reads JSON on stdin (eas-cli --json output, which
# may carry a text preamble) and prints the dotted field; exit 1 when the
# field is missing or null.
json_field() {
  node -e "
    let d = '';
    process.stdin.on('data', c => d += c);
    process.stdin.on('end', () => {
      const j = JSON.parse(d.slice(d.indexOf('{')));
      const v = process.argv[1].split('.').reduce((o, k) => (o ?? {})[k], j);
      if (v === undefined || v === null) process.exit(1);
      console.log(v);
    });
  " "$1"
}

# load_argent_session -> an argent session's connection config
# (ARGENT_TOOLS_URL / ARGENT_AUTH_TOKEN) lands in .env.eas-simulator;
# exporting it routes every local `argent run` to the session's remote
# tool-server. Falls back to the session's remoteConfig from simulator:get.
load_argent_session() {
  set -a
  # shellcheck disable=SC1091
  . ./.env.eas-simulator
  set +a
  if [ -z "${ARGENT_TOOLS_URL:-}" ] || [ -z "${ARGENT_AUTH_TOKEN:-}" ]; then
    eval "$(eas simulator:get --json --non-interactive | node -e "
      let d = '';
      process.stdin.on('data', c => d += c);
      process.stdin.on('end', () => {
        const found = {};
        (function walk(o) {
          if (!o || typeof o !== 'object') return;
          for (const [k, v] of Object.entries(o)) {
            if ((k === 'ARGENT_TOOLS_URL' || k === 'ARGENT_AUTH_TOKEN') && typeof v === 'string') found[k] = v;
            else walk(v);
          }
        })(JSON.parse(d.slice(d.indexOf('{'))));
        for (const [k, v] of Object.entries(found)) console.log(\`export \${k}=\${JSON.stringify(v)}\`);
      });
    ")"
  fi
  if [ -z "${ARGENT_TOOLS_URL:-}" ] || [ -z "${ARGENT_AUTH_TOKEN:-}" ]; then
    echo "argent connection config not found in .env.eas-simulator or simulator:get."
    exit 1
  fi
  export ARGENT_TOOLS_URL ARGENT_AUTH_TOKEN
}

# argent_device -> exports UDID: the session's iOS simulator ("udid") or
# Android emulator ("serial", e.g. emulator-5554); every other argent tool
# takes either as --udid. An emulator can be reported ready before adb lists
# it, so retry. The output is captured first: under set -e + pipefail an
# empty grep would kill the script before the message below.
argent_device() {
  local attempt devices=""
  for attempt in 1 2 3 4; do
    devices=$(bash scripts/agent/argent.sh run list-devices 2>&1 || true)
    echo "list-devices (attempt ${attempt}):"
    echo "$devices"
    if echo "$devices" | grep -qE '"(udid|serial)" *: *"[^"]+"'; then
      break
    fi
    sleep 15
  done
  UDID=$(echo "$devices" | grep -oE '"(udid|serial)" *: *"[^"]+"' | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/' || true)
  if [ -z "$UDID" ]; then
    echo "No device udid/serial in the argent session's list-devices output (see above)."
    exit 1
  fi
  export UDID
  echo "argent session device: $UDID"
}

# wait_for_home "<marker text>" -> deterministic floor beneath the AI
# agent: poll describe (up to six times) until the marker is in the UI
# tree, relaunching the app once if it stays away; the last tree goes to
# /tmp/home-snapshot.txt, and a missing marker exits 1. Needs UDID
# (argent_device) and APP_ID. Right after boot the tree can still be
# empty (seen in practice: 15 s after ready the accessibility read saw
# no foreground app). Odd attempts pass --bundleId (measures the app's
# connection state on iOS); even attempts do not, in case a platform
# rejects it.
wait_for_home() {
  local marker=$1 attempt snapshot=""
  for attempt in 1 2 3 4 5 6; do
    if [ $((attempt % 2)) -eq 1 ]; then
      snapshot=$(bash scripts/agent/argent.sh run describe --udid "$UDID" --bundleId "$APP_ID" 2>&1 || true)
    else
      snapshot=$(bash scripts/agent/argent.sh run describe --udid "$UDID" 2>&1 || true)
    fi
    if echo "$snapshot" | grep -q "$marker"; then
      break
    fi
    echo "Home screen not visible yet (attempt ${attempt})."
    if [ "$attempt" -eq 3 ]; then
      echo "Relaunching the app once..."
      if bash scripts/agent/argent.sh run restart-app --udid "$UDID" --bundleId "$APP_ID" >/tmp/relaunch.txt 2>&1; then
        echo "Relaunch sent."
      else
        echo "Relaunch failed:"; tail -3 /tmp/relaunch.txt
      fi
      sleep 5
    fi
    sleep 5
  done
  echo "$snapshot" | tee /tmp/home-snapshot.txt
  if ! echo "$snapshot" | grep -q "$marker"; then
    echo "❌ Home screen ('${marker}') not visible after launch and one relaunch."
    # Keep the last tree with the evidence so the uploaded artifact says why.
    [ -d evidence ] && cp /tmp/home-snapshot.txt evidence/home-snapshot.txt
    exit 1
  fi
}

# cap_diff <file> -> keep a diff within the prompt budget (150 kB).
cap_diff() {
  if [ "$(wc -c < "$1")" -gt 150000 ]; then
    head -c 150000 "$1" > "$1.capped"
    printf '\n\n[diff truncated at 150 kB]\n' >> "$1.capped"
    mv "$1.capped" "$1"
  fi
}

# set-output <name> <value> -> an EAS Workflows step output on a worker; on
# a laptop (where the command does not exist) a log line, so a lane can be
# rehearsed locally and still show what it would have reported.
if ! command -v set-output >/dev/null 2>&1; then
  set-output() { echo "output $1=$2"; }
fi

# fmt_dur <seconds> -> "3m 07s" or "42s".
fmt_dur() { local s=$1; if [ "$s" -ge 60 ]; then printf '%dm %02ds' $((s / 60)) $((s % 60)); else printf '%ds' "$s"; fi; }
