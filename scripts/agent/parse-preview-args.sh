#!/usr/bin/env bash
# Parses the text after "@expo-bot preview" into the pr-live-preview
# workflow inputs. Prints three lines: duration=<minutes>, platform=<ios|android>,
# device=<name or empty>.
#
#   @expo-bot preview                         30 min, iOS, runner default device
#   @expo-bot preview 45                      45 min
#   @expo-bot preview iPhone 16 Pro           device "iPhone 16 Pro"
#   @expo-bot preview 45 iPhone 16 Pro        both
#   @expo-bot preview iPhone 16 Pro for 45    both, natural order
#   @expo-bot preview android                 Android emulator, default device
#   @expo-bot preview pixel_7                 Android inferred from the AVD id
#   @expo-bot preview android pixel_7 20m     all three
#
# Rules, in order, per word:
#   - "ios" / "android" (any case) picks the platform
#   - a bare number is the duration while no device word has been read yet;
#     "for N", "Nm", "Nmin", or "N minutes" is the duration anywhere
#     (so the 16 in "iPhone 16 Pro" stays part of the device name)
#   - filler words "on", "for", "device", "minute(s)", "min(s)" are dropped
#   - every other word joins the device name
# Platform is inferred from the device when not given: iphone*/ipad* -> ios,
# pixel*/nexus*/anything with an underscore (an AVD hardware profile id) ->
# android, else ios.
#
# Usage: parse-preview-args.sh "<text after preview>"
# PREVIEW_DEFAULT_MINUTES overrides the 30-minute default duration.
set -euo pipefail

TEXT="${1:-}"
DEFAULT_DURATION="${PREVIEW_DEFAULT_MINUTES:-30}"

DURATION=""
PLATFORM=""
DEVICE=""
EXPECT_DURATION=""

# Normalize quotes and commas so `preview "iPhone 16 Pro", 45` also works.
TEXT=$(printf '%s' "$TEXT" | tr '",\047' '   ')
# shellcheck disable=SC2206
WORDS=($TEXT)

for w in ${WORDS[@]+"${WORDS[@]}"}; do
  lower=$(printf '%s' "$w" | tr '[:upper:]' '[:lower:]')
  if [ -n "$EXPECT_DURATION" ] && [[ "$lower" =~ ^([0-9]+)(m|min|mins|minute|minutes)?$ ]]; then
    DURATION="${BASH_REMATCH[1]}"; EXPECT_DURATION=""; continue
  fi
  EXPECT_DURATION=""
  case "$lower" in
    ios) PLATFORM=ios; continue ;;
    android) PLATFORM=android; continue ;;
    for) EXPECT_DURATION=1; continue ;;
    on|device|minute|minutes|min|mins) continue ;;
  esac
  if [[ "$lower" =~ ^([0-9]+)(m|min|mins|minute|minutes)$ ]]; then
    DURATION="${BASH_REMATCH[1]}"; continue
  fi
  if [[ "$lower" =~ ^[0-9]+$ ]] && [ -z "$DEVICE" ]; then
    DURATION="$lower"; continue
  fi
  DEVICE="${DEVICE:+$DEVICE }$w"
done

if [ -z "$PLATFORM" ]; then
  dl=$(printf '%s' "$DEVICE" | tr '[:upper:]' '[:lower:]')
  case "$dl" in
    iphone*|ipad*|"") PLATFORM=ios ;;
    pixel*|nexus*|*_*) PLATFORM=android ;;
    *) PLATFORM=ios ;;
  esac
fi
[ -n "$DURATION" ] || DURATION="$DEFAULT_DURATION"
# A zero-minute session is meaningless; treat it as the default.
[ "$DURATION" -gt 0 ] 2>/dev/null || DURATION="$DEFAULT_DURATION"

echo "duration=$DURATION"
echo "platform=$PLATFORM"
echo "device=$DEVICE"
