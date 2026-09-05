#!/usr/bin/env bash
#
# SENTRY — SOC · the screenshot gate (C11, `SPEC.md` §7 step 5).
#
#   bash ios/scripts/shots.sh          # build Debug, install, capture everything
#   SENTRY_SKIP_BUILD=1 bash ios/scripts/shots.sh
#   bash ios/scripts/shots.sh debrief  # one screen, all sizes — for a fix loop
#
# Run it with **bash**, not `sh`: `set -o pipefail` below is not POSIX and dash
# rejects it. It re-execs itself under bash if you forget.
#
# 13 screens × 3 Dynamic Type sizes on the iPhone 17 Pro Max, plus hub/case/debrief
# on a 375-pt-class device (the iPhone 16e SPEC §7 names) to catch narrow overflow.
# PNGs land in `docs/screenshots/ios/gate/<screen>-<size>.png` and are committed:
# they are the founder sign-off artefact, and §11 rule 11 says the aesthetic bar is
# verified by looking.
#
# **State is reset before every shot.** Each jump replays real actions through the
# reducer, so a `rankup` capture leaves a promoted career behind it and the next
# `hub` shot would be a different screen. Uninstall + install per shot costs about a
# second and buys a set of images that mean the same thing on every run.

set -u

# See the header: dash aborts on `set -o pipefail`, so a `sh …` call would die here.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -o pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 2

BUNDLE="pl.oumm.sentry.soc"
OUT="docs/screenshots/ios/gate"
DERIVED="ios/.build"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/SentrySOC.app"
FALLBACK_UDID="C2136147-45C8-42DD-8E3A-EDE974B97154"   # SPEC §7's booted 17 Pro Max
SETTLE="${SENTRY_SETTLE:-2.5}"

# SPEC §7's thirteen. `evidence` is a *tab* of the case screen (§5.6), not a phase,
# and `QAJump` has no name for it — see `reach_evidence` below.
SCREENS="hub intro board case source evidence call debrief summary rankup settings firstrun kit"
SIZES="extra-small medium accessibility-medium"
NARROW_SCREENS="hub case debrief"

FAILURES=0
note() { printf '   %s\n' "$1"; }
warn() { FAILURES=$((FAILURES + 1)); printf '   !! %s\n' "$1"; }

# ── device resolution ────────────────────────────────────────────────────────

# S11: resolve by name from `simctl list devices available`, fall back to the
# hardcoded UDID, so the script survives a wiped or renamed simulator set.
udid_for() {
  xcrun simctl list devices available -j 2>/dev/null | python3 -c '
import json, sys
wanted = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
exact, loose = [], []
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    for device in entries:
        if not device.get("isAvailable", True):
            continue
        if device["name"] == wanted:
            exact.append(device["udid"])
        elif wanted in device["name"]:
            loose.append(device["udid"])
print((exact + loose or [""])[0])
' "$1"
}

boot() {
  xcrun simctl bootstatus "$1" -b > /dev/null 2>&1 \
    || { xcrun simctl boot "$1" > /dev/null 2>&1; xcrun simctl bootstatus "$1" -b > /dev/null 2>&1; }
  # Pin the status bar, or the wall clock and the carrier name change every PNG and every
  # run shows 42 files modified with nothing behind it. This is also Apple's own
  # marketing time, which is what the App Store screenshots want (docs/APPSTORE.md).
  xcrun simctl status_bar "$1" override \
    --time '09:41' --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 \
    > /dev/null 2>&1
}

SIM="$(udid_for 'iPhone 17 Pro Max')"
if [ -z "$SIM" ]; then
  SIM="$FALLBACK_UDID"
  note "no 'iPhone 17 Pro Max' in simctl — falling back to $SIM"
fi

# The narrow pass. SPEC §7 names the iPhone 16e, but the 16e is **390 × 844 pt** — it is
# the narrowest *current* iPhone, not a 375-pt device, and measured here it misses the
# defect a real 375 × 667 screen shows (DEF-2: the case screen's tab strip disappears
# under the coach inset). So the script creates an iPhone SE (3rd gen) — 375 × 667, the
# smallest screen iOS 18 supports — and falls back to the 16e when that device type is
# not installed.
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and "iOS" in r["name"]]
print(runtimes[-1]["identifier"] if runtimes else "")')
SE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation
NARROW="$(udid_for 'SENTRY-375')"
if [ -z "$NARROW" ] && [ -n "$RUNTIME" ]; then
  NARROW=$(xcrun simctl create 'SENTRY-375' "$SE_TYPE" "$RUNTIME" 2>/dev/null)
  [ -n "$NARROW" ] && note 'created SENTRY-375 (iPhone SE 3rd gen · 375 × 667 pt)'
fi
if [ -z "$NARROW" ]; then
  NARROW="$(udid_for 'iPhone 16e')"
  if [ -z "$NARROW" ] && [ -n "$RUNTIME" ]; then
    note 'no SE device type — creating an iPhone 16e instead'
    NARROW=$(xcrun simctl create 'iPhone 16e' 'iPhone 16e' "$RUNTIME" 2>/dev/null)
  fi
fi

# ── build and install ────────────────────────────────────────────────────────

if [ "${SENTRY_SKIP_BUILD:-0}" != "1" ]; then
  note 'building Debug for the simulator (CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)'
  if ! xcodebuild build \
      -project ios/SentrySOC.xcodeproj -scheme SentrySOC -configuration Debug \
      -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DERIVED" \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      > /tmp/sentry-shots-build.log 2>&1; then
    printf 'BUILD FAILED — see /tmp/sentry-shots-build.log\n'
    tail -20 /tmp/sentry-shots-build.log
    exit 1
  fi
fi
[ -d "$APP" ] || { printf 'no app at %s — drop SENTRY_SKIP_BUILD\n' "$APP"; exit 1; }

mkdir -p "$OUT"

# ── one shot ─────────────────────────────────────────────────────────────────

reset_app() {  # a clean save, so every shot means the same thing on every run
  xcrun simctl terminate "$1" "$BUNDLE" > /dev/null 2>&1
  xcrun simctl uninstall "$1" "$BUNDLE" > /dev/null 2>&1
  xcrun simctl install "$1" "$APP" > /dev/null 2>&1
}

tap() { idb ui tap --udid "$1" --match-key AXLabel "$2" > /dev/null 2>&1; sleep 1.2; }

# EVIDENCE is the case screen's second tab, and `QAJump` has no destination for it
# (DEF-1 in docs/PLAYTEST-ios.md — a C5 defect, reported not fixed). It is reached
# the way a player reaches it: the `call` jump leaves one finding on the board, so
# dismiss the call sheet and switch tabs. Labels come from `copy.json`
# (`callKeepInvestigating`, `caseEvidenceTab`), not from coordinates, so the path
# survives all three Dynamic Type sizes.
reach_evidence() {
  xcrun simctl launch "$1" "$BUNDLE" -SentryQAScreen call > /dev/null 2>&1
  sleep "$SETTLE"
  tap "$1" 'Keep investigating'
  tap "$1" 'EVIDENCE'
}

capture() {  # udid, screen, output path
  reset_app "$1"
  if [ "$2" = "evidence" ]; then
    reach_evidence "$1"
  else
    xcrun simctl launch "$1" "$BUNDLE" -SentryQAScreen "$2" > /dev/null 2>&1
    sleep "$SETTLE"
  fi
  if ! xcrun simctl io "$1" screenshot --type=png "$3" > /dev/null 2>&1; then
    warn "screenshot failed: $3"
    return
  fi
  # A jump that trapped leaves SpringBoard on screen and the PNG still looks like a
  # valid screenshot, so check the app is alive before believing the image. Counted,
  # not `grep -q`: under `pipefail` an early-exiting grep SIGPIPEs `launchctl` and the
  # pipeline reports failure even on a match — which is a flaky false alarm, and the
  # worst possible defect in a defect detector.
  if [ "$(xcrun simctl spawn "$1" launchctl list 2>/dev/null | grep -c "$BUNDLE")" -eq 0 ]; then
    warn "$(basename "$3") — the app is not running; the jump '$2' most likely trapped"
  fi
  printf '   %s\n' "$3"
}

# ── the run ──────────────────────────────────────────────────────────────────

WANTED="${*:-$SCREENS}"

printf 'SENTRY — SOC screenshot gate\n   wide   %s (iPhone 17 Pro Max)\n' "$SIM"
printf '   narrow %s (%s)\n' "${NARROW:-none}" \
  "$(xcrun simctl list devices -j 2>/dev/null | python3 -c '
import json, sys
wanted = sys.argv[1]
for entries in json.load(sys.stdin)["devices"].values():
    for device in entries:
        if device["udid"] == wanted:
            print(device["name"]); raise SystemExit
print("none")' "${NARROW:-none}")"

boot "$SIM"
for SIZE in $SIZES; do
  printf '\n── %s\n' "$SIZE"
  xcrun simctl ui "$SIM" content_size "$SIZE" > /dev/null 2>&1 \
    || warn "content_size $SIZE was refused by this runtime"
  for SCREEN in $WANTED; do
    capture "$SIM" "$SCREEN" "$OUT/$SCREEN-$SIZE.png"
  done
done
xcrun simctl ui "$SIM" content_size large > /dev/null 2>&1   # leave the sim as found

if [ -n "${NARROW:-}" ]; then
  printf '\n── narrow pass (medium)\n'
  boot "$NARROW"
  xcrun simctl ui "$NARROW" content_size medium > /dev/null 2>&1
  for SCREEN in $NARROW_SCREENS; do
    case " $WANTED " in *" $SCREEN "*) capture "$NARROW" "$SCREEN" "$OUT/$SCREEN-narrow.png" ;; esac
  done
else
  warn 'no narrow device — the 375-pt pass did not run'
fi

TOTAL=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
printf '\n%s PNGs in %s\n' "$TOTAL" "$OUT"
if [ "$FAILURES" -gt 0 ]; then
  printf 'SHOTS INCOMPLETE — %s problem(s) above.\n' "$FAILURES"
  exit 1
fi
printf 'SHOTS OK — now LOOK at them (§11 rule 11) and file defects in docs/PLAYTEST-ios.md.\n'
