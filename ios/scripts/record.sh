#!/usr/bin/env bash
#
# SENTRY — SOC · sequence recorder (F2a, `docs/ios/FEEL.md` §11).
#
#   sh ios/scripts/record.sh <sequence> [seconds] [qa-screen]
#   sh ios/scripts/record.sh smoke                      # 3 s of whatever is on screen
#   sh ios/scripts/record.sh call 3 debrief             # record the debrief's own entry
#
# "Motion can't be judged from a still" (§11). So: record the simulator around a
# sequence, cut it into a frame every 100 ms, and leave a strip a reviewer can read
# against the timelines in §1/§2/§4/§8 — which are themselves asserted in
# `SessionTests/SequenceTests`, so this is the *second* check and not the only one.
#
# Frames land in `docs/screenshots/ios/feel/<sequence>/f-001.png …`, ten per second,
# which is the ±60 ms tolerance §11 asks for: a 100 ms grid resolves a 260 ms step
# unambiguously and a 120 ms one to within a frame.
#
# **The QA launch happens INSIDE the recording**, not before it. A sequence's most
# interesting 500 ms are its first, and a script that settles the screen before
# rolling would record every one of them as a still.
#
# **ffmpeg is optional.** With it, one `simctl recordVideo` is cut into frames — the
# accurate path, because the frames come off the compositor rather than off a shell
# loop. Without it (or when the capture turns out to be static, see below) the script
# bursts `simctl io screenshot` at ~10 Hz instead: wall-clock paced rather than
# frame-accurate, so a 120 ms beat may land a frame either side. The manifest beside
# the strip says which path ran.
#
# Environment:
#   SENTRY_UDID    the simulator to record (default: the first booted device)
#   SENTRY_BUNDLE  bundle id (default: pl.oumm.sentry.soc)
#   SENTRY_KEEP    1 to keep the .mp4 next to the frames
#   SENTRY_WIDTH   frame width in px (default 440 — the logical point grid)

set -u
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi
set -o pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 2

SEQUENCE="${1:-smoke}"
SECONDS_TO_RECORD="${2:-3}"
QA_SCREEN="${3:-}"
BUNDLE="${SENTRY_BUNDLE:-pl.oumm.sentry.soc}"

UDID="${SENTRY_UDID:-}"
if [ -z "$UDID" ]; then
  UDID=$(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -1)
fi
if [ -z "$UDID" ]; then
  echo "no booted simulator — boot one, or set SENTRY_UDID" >&2
  exit 2
fi

OUT="docs/screenshots/ios/feel/$SEQUENCE"
rm -rf "$OUT"
mkdir -p "$OUT"
VIDEO="$OUT/$SEQUENCE.mp4"
FRAME_WIDTH="${SENTRY_WIDTH:-440}"

sleep_for() { python3 -c "import time,sys; time.sleep(float(sys.argv[1]))" "$1"; }

# Relaunch onto the screen whose sequence is being recorded. Runs while the camera is
# already rolling, so frame 1 is the launch and not its aftermath.
launch_qa() {
  [ -n "$QA_SCREEN" ] || return 0
  xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1
  xcrun simctl launch "$UDID" "$BUNDLE" -SentryQAScreen "$QA_SCREEN" -hapticTrace > /dev/null 2>&1 \
    || echo "   launch failed — is the app installed?" >&2
}

# ~10 Hz of `simctl io screenshot`. Each shot costs 60–120 ms on this machine, so the
# loop paces itself against a deadline rather than sleeping a fixed 100 ms and
# drifting further behind on every frame.
burst() {
  python3 - "$UDID" "$OUT" "$SECONDS_TO_RECORD" <<'PY'
import subprocess, sys, time
udid, out, seconds = sys.argv[1], sys.argv[2], float(sys.argv[3])
start = time.monotonic()
index = 1
while time.monotonic() - start <= seconds:
    due = start + (index - 1) * 0.1
    delay = due - time.monotonic()
    if delay > 0:
        time.sleep(delay)
    subprocess.run(
        ["xcrun", "simctl", "io", udid, "screenshot", f"{out}/f-{index:03d}.png"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    index += 1
PY
  # Same point grid as the video path. `ffmpeg` where it exists — its PNG encoder
  # gets a flat dark UI down to ~25 KB a frame, where `sips` leaves the same picture
  # near 220 KB — and `sips` (which ships with macOS) as the fallback, so a machine
  # without ffmpeg still gets a strip that is 1x rather than @3x.
  for shot in "$OUT"/f-*.png; do
    [ -e "$shot" ] || continue
    if command -v ffmpeg > /dev/null 2>&1; then
      ffmpeg -loglevel error -y -i "$shot" -vf "scale=$FRAME_WIDTH:-1" \
        -compression_level 100 "$shot.tmp.png" 2> /dev/null \
        && mv "$shot.tmp.png" "$shot"
    else
      sips --resampleWidth "$FRAME_WIDTH" "$shot" > /dev/null 2>&1
    fi
  done
}

frame_count() { ls "$OUT"/f-*.png 2> /dev/null | wc -l | tr -d ' '; }

echo "SENTRY — SOC · recording '$SEQUENCE' for ${SECONDS_TO_RECORD}s on $UDID"
[ -n "$QA_SCREEN" ] && echo "   -SentryQAScreen $QA_SCREEN, launched inside the recording"

MODE="burst"
command -v ffmpeg > /dev/null 2>&1 && MODE="video"

if [ "$MODE" = "video" ]; then
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$VIDEO" > /dev/null 2>&1 &
  RECORDER=$!
  # The recorder needs a moment to attach before it is worth launching into it.
  sleep_for 0.4
  launch_qa
  sleep_for "$SECONDS_TO_RECORD"
  # SIGINT, not SIGKILL: `recordVideo` finalises the container on an interrupt and
  # leaves an unplayable file on a kill.
  kill -INT "$RECORDER" 2> /dev/null
  wait "$RECORDER" 2> /dev/null
  sleep_for 1.0          # the moov atom lands a beat after the interrupt

  if [ ! -s "$VIDEO" ]; then
    echo "   recordVideo produced nothing — falling back to a screenshot burst" >&2
    MODE="burst"
  else
    # Scaled to the **logical point grid** (440 pt wide), not to the @3x capture. A
    # strip is read for timing — which beat landed on which 100 ms frame — and a
    # 1320 px frame is 500 KB of evidence for a question that 50 KB answers. Sixty
    # @3x frames are 25 MB in a repository that a reviewer clones; at 1x they are
    # under three, and every word on the screen is still legible.
    ffmpeg -loglevel error -y -i "$VIDEO" -vf "fps=10,scale=$FRAME_WIDTH:-1" "$OUT/f-%03d.png" || {
      echo "   ffmpeg could not cut the video" >&2
      exit 2
    }
    [ "${SENTRY_KEEP:-0}" = "1" ] || rm -f "$VIDEO"
  fi
fi

# **A static screen defeats `recordVideo`.** It is a variable-frame-rate capture: a
# screen that never changes writes ONE frame with a 0.07 s duration, and `fps=10` over
# a 0.07 s timeline is one frame however long the wall clock ran. Correct behaviour
# for a codec, useless for a strip — so an extraction that comes back far short of the
# grid is redone as a burst, which is paced by the clock and cannot collapse. A real
# sequence produces frames and keeps the accurate path.
EXPECTED=$(python3 -c "print(int(float('$SECONDS_TO_RECORD') * 10))")
FRAMES=$(frame_count)
if [ "$MODE" = "video" ] && [ "$FRAMES" -lt $((EXPECTED / 2)) ]; then
  echo "   only $FRAMES frame(s) over ${SECONDS_TO_RECORD}s — the screen was static; bursting instead"
  rm -f "$OUT"/f-*.png
  MODE="burst (the video capture was static)"
fi

case "$MODE" in
  burst*)
    if [ -n "$QA_SCREEN" ]; then
      burst &
      BURSTER=$!
      sleep_for 0.2
      launch_qa
      wait "$BURSTER"
    else
      burst
    fi
    ;;
esac

FRAMES=$(frame_count)
if [ "$FRAMES" = "0" ]; then
  echo "   no frames were written" >&2
  exit 2
fi

# The contact sheet: every frame in reading order, six to a row. It is the artefact a
# reviewer actually opens — one image, the whole sequence, left to right and top to
# bottom at 100 ms a step — with the individual frames beside it for anything that
# needs a closer look.
if command -v ffmpeg > /dev/null 2>&1 && [ "$FRAMES" -gt 1 ]; then
  ROWS=$(python3 -c "import math; print(max(1, math.ceil($FRAMES / 6)))")
  ffmpeg -loglevel error -y -framerate 1 -start_number 1 -i "$OUT/f-%03d.png" \
    -vf "tile=6x${ROWS}:padding=4:margin=4:color=0x161b22" -compression_level 100 \
    -frames:v 1 "$OUT/strip.png" \
    2> /dev/null || rm -f "$OUT/strip.png"
fi

# A manifest beside the strip, so a reviewer reading the PNGs a week later knows what
# they are looking at and on what grid.
{
  echo "sequence   : $SEQUENCE"
  echo "device     : $UDID"
  echo "mode       : $MODE (100 ms grid)"
  echo "seconds    : $SECONDS_TO_RECORD"
  echo "frames     : $FRAMES at ${FRAME_WIDTH}px wide"
  echo "contact    : $([ -s "$OUT/strip.png" ] && echo "strip.png (6 per row)" || echo "none")"
  echo "qa screen  : ${QA_SCREEN:-none}"
  echo "recorded   : $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "f-001 is t=0; each frame after it is +100 ms. Read against docs/ios/FEEL.md"
  echo "§1 handover · §2 arrival · §4 pull · §8 call — the numbers SequenceTests asserts."
} > "$OUT/manifest.txt"

echo "   $FRAMES frames → $OUT (100 ms grid, mode=$MODE)"
