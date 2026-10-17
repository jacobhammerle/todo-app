#!/usr/bin/env bash
# Stitches the five QA swarm lanes into one report: per-lane verdict
# lines, the parallel-vs-serial wall clock, the fleet's simulator minutes,
# and a thumbnail row. Prints it, emits step outputs for the doc job, and
# (when PR_NUMBER is set) posts it as one PR comment.
# Requires, for lanes 1..5 (order: iOS tasks, iOS add, iOS done,
#   Android tasks, Android add):
#   L<n>_STATUS, L<n>_VERDICT, L<n>_EVIDENCE, L<n>_METRICS, L<n>_SECONDS,
#   L<n>_SIM_MIN, L<n>_THUMBS
# Optional: PR_NUMBER + GITHUB_TOKEN (post the PR comment; the repo comes
#           from GH_REPO or package.json "repository")
set -euo pipefail

# shellcheck disable=SC1091
. scripts/agent/comment-lib.sh

LABELS=("iOS · Tasks" "iOS · Add" "iOS · Done" "Android · Tasks" "Android · Add")
FLEET="3 iOS simulators + 2 Android emulators"

# An uninterpolated "${{ ... }}" or an empty value both mean "not set".
clean() { case "$1" in *'${{'*) printf '' ;; *) printf '%s' "$1" ;; esac; }

PR_NUMBER=$(clean "${PR_NUMBER:-}")
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then PR_NUMBER=""; fi

PASSED=0
SERIAL=0
PARALLEL=0
TIMED=0
SIM_TOTAL=0
THUMBS=""
EVIDENCE_LINKS=""
LANE_LINES=()

for n in 1 2 3 4 5; do
  label=${LABELS[$((n - 1))]}
  status=$(clean "$(eval "printf '%s' \"\${L${n}_STATUS:-}\"")")
  verdict=$(clean "$(eval "printf '%s' \"\${L${n}_VERDICT:-}\"")")
  evidence=$(clean "$(eval "printf '%s' \"\${L${n}_EVIDENCE:-}\"")")
  metrics=$(clean "$(eval "printf '%s' \"\${L${n}_METRICS:-}\"")")
  seconds=$(clean "$(eval "printf '%s' \"\${L${n}_SECONDS:-}\"")")
  sim_min=$(clean "$(eval "printf '%s' \"\${L${n}_SIM_MIN:-}\"")")
  thumbs=$(clean "$(eval "printf '%s' \"\${L${n}_THUMBS:-}\"")")

  # A lane that died before writing a verdict still has a job status.
  [ -n "$verdict" ] && verdict=$(normalize_verdict "$verdict")
  if [ -z "$verdict" ]; then
    case "$status" in
      success) verdict="PASS: lane finished (no verdict text captured)" ;;
      *) verdict="FAIL: lane ended with status '${status:-unknown}' before writing a verdict" ;;
    esac
  fi
  case "$verdict" in PASS:*) PASSED=$((PASSED + 1)) ;; esac

  if [[ "$seconds" =~ ^[0-9]+$ ]]; then
    TIMED=$((TIMED + 1))
    SERIAL=$((SERIAL + seconds))
    [ "$seconds" -gt "$PARALLEL" ] && PARALLEL=$seconds
  fi
  if [[ "$sim_min" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    SIM_TOTAL=$(awk "BEGIN { printf \"%.1f\", $SIM_TOTAL + $sim_min }")
  fi

  line="$(verdict_badge "$verdict")"
  line="**${label}** — ${line}"
  [ -n "$metrics" ] && line="${line}  ·  ${metrics}"
  if [ -n "$evidence" ]; then
    line="${line}  ·  [Evidence](${evidence})"
    EVIDENCE_LINKS="${EVIDENCE_LINKS:+${EVIDENCE_LINKS} · }[${label}](${evidence})"
  fi
  LANE_LINES+=("$line")
  [ -n "$thumbs" ] && THUMBS="${THUMBS:+${THUMBS} }${thumbs}"
done

# Headline verdict.
if [ "$PASSED" -eq 5 ]; then
  HEADLINE="PASS: 5 of 5 lanes passed"
else
  HEADLINE="FAIL: $((5 - PASSED)) of 5 lanes failed"
fi

# Parallel vs serial: the swarm's wall clock is its slowest lane; running
# the same lanes one after another would take their sum.
if [ "$TIMED" -gt 0 ] && [ "$PARALLEL" -gt 0 ]; then
  SPEEDUP=$(awk "BEGIN { printf \"%.1f\", $SERIAL / $PARALLEL }")
  TIMING="$(fmt_dur "$PARALLEL") wall clock in parallel vs $(fmt_dur "$SERIAL") one lane after another (${SPEEDUP}× faster)"
  [ "$TIMED" -lt 5 ] && TIMING="${TIMING}; ${TIMED} of 5 lanes reported timings"
else
  TIMING="no lane reported timings"
fi
TOTALS="${PASSED}/5 lanes passed · ${TIMING} · ${FLEET}, ${SIM_TOTAL} device-minutes total"

echo "================ QA SWARM ================"
echo "$HEADLINE"
echo "$TOTALS"
for l in "${LANE_LINES[@]}"; do echo "- $l"; done
echo "=========================================="

set-output headline "$HEADLINE"
set-output timing "$TIMING"
set-output fleet "${FLEET}, ${SIM_TOTAL} device-minutes"
for n in 1 2 3 4 5; do
  set-output "lane_${n}" "${LANE_LINES[$((n - 1))]}"
done

if [ -z "$PR_NUMBER" ]; then
  echo "No PR number; skipping the PR comment."
  exit 0
fi
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "GITHUB_TOKEN is not set; cannot post the PR comment."
  exit 1
fi

LANES_MD=""
for l in "${LANE_LINES[@]}"; do LANES_MD="${LANES_MD}- ${l}"$'\n'; done

# Same shape as every bot post: "## 🤖 <stage>", a verdict line, a short
# list, the thumbnails, the detail folded away, a "_Posted by_" footer.
node scripts/agent/gh.mjs comment "$PR_NUMBER" "## 🐝 QA swarm

**Verdict:** $(verdict_badge "$HEADLINE")

- ⏱ **Parallel** — ${TIMING}
- 📱 **Fleet** — ${FLEET}, ${SIM_TOTAL} device-minutes total
- 🖼️ **Evidence** — ${EVIDENCE_LINKS:-none published}

${THUMBS}

<details>
<summary>Lane verdicts and timings</summary>

${LANES_MD}
</details>

_Posted by the QA swarm EAS workflow._"
echo "Posted the swarm report on PR #${PR_NUMBER}."
