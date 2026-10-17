#!/usr/bin/env bash
# Parses an @expo-bot comment into two GITHUB_OUTPUT lines:
#   mode=<full|change|review|preview|issue>
#   instruction=<text after the keyword>
# Only the first line of the comment counts.
#
# On a pull request (target "pr"):
#   @expo-bot <instruction>          mode=full    apply the change, then review + verify
#   @expo-bot change <instruction>   mode=change  apply the change only (instruction required)
#   @expo-bot review [instruction]   mode=review  review + verify only
#   @expo-bot preview [args]         mode=preview args parsed later by parse-preview-args.sh
#   @expo-bot                        mode=review  a bare mention
# On an issue (target "issue"): mode=issue, and everything after @expo-bot
# is guidance for the replication agent.
# "@expo-bot" must be a whole word: followed by whitespace or the end of
# the line. Anything else ("@expo-bottle x") prints nothing and exits 1.
#
# Usage: parse-bot-comment.sh "<comment body>" <pr|issue>
set -euo pipefail

BODY="${1:-}"
TARGET="${2:?second argument must be pr or issue}"

FIRST_LINE=$(printf '%s' "$BODY" | head -n 1 | tr -d '\r')
if ! printf '%s' "$FIRST_LINE" | grep -qE '^@expo-bot([[:space:]]|$)'; then
  echo "parse-bot-comment.sh: the comment does not start with the word '@expo-bot'." >&2
  exit 1
fi
FIRST_LINE=$(printf '%s' "$FIRST_LINE" \
  | sed -E 's/^@expo-bot[[:space:]]*//; s/[[:space:]]+$//')

if [ "$TARGET" = "issue" ]; then
  MODE=issue
  INSTRUCTION="$FIRST_LINE"
else
  MODE=full
  INSTRUCTION="$FIRST_LINE"
  # The first word may be a mode keyword; the rest is the instruction.
  read -r KEYWORD REST <<< "$FIRST_LINE" || true
  case "$KEYWORD" in
    review|change|preview)
      MODE=$KEYWORD
      INSTRUCTION="${REST:-}"
      ;;
  esac
  if [ "$MODE" = "change" ] && [ -z "$INSTRUCTION" ]; then
    echo "change mode needs an instruction after the keyword." >&2
    exit 1
  fi
  if [ "$MODE" = "full" ] && [ -z "$INSTRUCTION" ]; then
    MODE=review
  fi
fi

echo "mode=$MODE"
echo "instruction=$INSTRUCTION"
