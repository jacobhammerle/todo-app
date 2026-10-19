#!/usr/bin/env bash
# Thin wrapper for the TestFlight intake job: picks the token, runs the
# intake script, and publishes its result as step outputs.
# Requires: FEEDBACK_KIND (screenshot|crash), GITHUB_TOKEN,
#           BASE_BRANCH, EXPO_TOKEN_SIMULATOR (or an EXPO_TOKEN that can
#           read the project's App Store Connect API key)
# Optional: GH_REPO (owner/repo; default: package.json "repository"),
#           ASC_FEEDBACK_ID (trigger context),
#           the agent runner's credentials (agent triage; run-agent.sh)
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh
# The personal token can read credentials and dispatch workflows, so it is
# preferred here too; the intake still runs on the worker's own token.
use_simulator_token optional
require_env GITHUB_TOKEN "add a GitHub token with issues write access as a secret env var in the production EAS environment."
# Without agent credentials the issue is filed from the submission alone.
use_agent_token optional

node scripts/agent/intake-testflight.mjs

RESULT=/tmp/testflight/result.json
if [ ! -s "$RESULT" ]; then
  echo "intake-testflight.mjs wrote no result file."
  exit 1
fi
field() { node -e "console.log(JSON.parse(require('fs').readFileSync('$RESULT','utf8')).$1 ?? '')"; }

set-output issue_number "$(field issue_number)"
set-output issue_url "$(field issue_url)"
set-output run_url "$(field run_url)"
set-output kind "$(field kind)"

# A duplicate submission was added to the existing issue; nothing to
# dispatch, and the job is green.
if [ "$(field duplicate)" = "true" ]; then
  echo "Duplicate of issue #$(field issue_number); no new issue or triage run."
  exit 0
fi

# A filed issue with no triage run is a partial success: the issue
# comment says how to retry, and the job goes red so it is noticed.
if [ -z "$(field run_url)" ]; then
  echo "Issue filed but the expo-bot dispatch failed; see above."
  exit 1
fi
