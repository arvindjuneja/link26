#!/usr/bin/env bash
#
# SENTRY — SOC · release guard (C11).
#
# Every condition of `docs/ios/SPEC.md` §7 step 6, as amended by `SPEC-ADDENDUM.md`
# (B3 · B4/R12 · B7 · §6 signing · S1 · S7). Run it before any archive:
#
#   bash ios/scripts/verify.sh            # all nine checks
#   bash ios/scripts/verify.sh d1         # one check by name (or number)
#   bash ios/scripts/verify.sh s1 pay     # several
#
# Run it with **bash**, not `sh`: it needs `set -o pipefail`, which dash (ubuntu's
# /bin/sh) rejects outright. It re-execs itself under bash if you forget.
#
# It runs **all** the checks it was asked for and exits non-zero at the end if any
# failed, because a release guard that stops at the first red line makes you run it
# nine times.
#
#   1 export  the committed export is byte-identical to a fresh run          (X3)
#   2 hash    one contentHash across all ten generated files                 (X6)
#   3 qa      SentryQAScreen absent from Release, present in Debug        (B7/§6)
#   4 fonts   every shipped .ttf has its OFL text                          (X10)
#   5 colours no hex colour or font name outside Design/                   (§4.6)
#   6 s1      no player copy authored as a Swift literal                      (S1)
#   7 profanity  the 4+ age-rating grep, with its allowlist                   (B3)
#   8 pay     no salary / pay band / currency figure in a shipped string  (B4/R12)
#   9 d1      the protected web tree and Cloudflare pipeline are untouched (S7/D1)
#
# `npm ls tailwindcss` is deliberately absent: it was a Capacitor-era check on the
# web bundle a WKWebView shipped, and there is no web view (SPEC §8).
#
# Environment:
#   SENTRY_SKIP_BUILD=1   reuse an existing Release build instead of rebuilding
#   SENTRY_D1_BASE=<ref>  override the D1 web-engine baseline (ios/scripts/d1-base.txt)

set -u

# Invoke it as `bash ios/scripts/verify.sh`. If something still calls it with `sh`,
# re-exec under bash rather than dying: on ubuntu-latest /bin/sh is dash, dash rejects
# the non-POSIX `set -o pipefail` below, and the script aborts with exit 2 before a
# single check runs — a required CI job that fails as a guard malfunction (C11 review
# finding 2). Dropping pipefail instead would silently weaken every `$LEX … | grep`.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -o pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 2

SCRIPTS="ios/scripts"
LEX="python3 $SCRIPTS/swiftlex.py"
APP_SOURCES="ios/SentrySOC/Sources"
RESOURCES="ios/SentrySOC/Resources"
EXPORTED="ios/SentryCore/Sources/SentryContent/Resources"
FIXTURES="ios/SentryCore/Sources/SentryFixtures/Resources"
DERIVED_RELEASE="ios/.build/release"
DERIVED_DEBUG="ios/.build"

FAILURES=0
RAN=0
CHECK=""

step()  { CHECK="$1"; RAN=$((RAN + 1)); printf '\n── %s\n' "$1"; }
ok()    { printf '   PASS · %s\n' "$1"; }
note()  { printf '   note · %s\n' "$1"; }
fail()  { FAILURES=$((FAILURES + 1)); printf '   FAIL · %s\n     %s\n' "$CHECK" "$1"; }
body()  { grep . | cut -c1-200 | sed 's/^/        /'; }

# The B3 age-rating grep, verbatim from SPEC-ADDENDUM B3.
PROFANITY='\b(damn|shit|fuck|hostage|weapon)\b|\bkill(s|ed|ing)?\b'
# The B4 pay-figure regex, verbatim. R12: literals only, never raw Swift.
PAY='(\$[[:space:]]?[0-9])|(\bsalar(y|ies)\b)|(\bper year\b)|(\bpay\b[[:space:]]*(range|band))|(\b(USD|EUR|PLN)\b)'

swift_sources() { find "$APP_SOURCES" -name '*.swift' | sort; }
copy_sources()  { find "$APP_SOURCES/Screens" "$APP_SOURCES/Components" -name '*.swift' | sort; }

# ── 1 · the export is not dirty against a fresh run ──────────────────────────
check_export() {
  step '1 · export is byte-identical to a fresh run (X3)'
  if npm run --silent soc:check > /tmp/sentry-soc-check.log 2>&1; then
    ok 'npm run soc:check'
  else
    fail 'the committed export differs from a fresh run — see /tmp/sentry-soc-check.log'
    tail -20 /tmp/sentry-soc-check.log | body
  fi
}

# ── 2 · one contentHash across all ten generated files (X6) ──────────────────
check_hash() {
  step '2 · contentHash identical across the 10 generated files'
  local count hashes distinct
  count=$(ls "$EXPORTED"/*.json "$FIXTURES"/*.json 2>/dev/null | grep -c .)
  [ "$count" -eq 10 ] || fail "expected 10 generated JSON files, found $count"
  hashes=$(python3 - "$EXPORTED" "$FIXTURES" <<'PY'
import glob, json, sys
for root in sys.argv[1:]:
    for path in sorted(glob.glob(root + "/*.json")):
        with open(path, encoding="utf-8") as handle:
            print(json.load(handle).get("contentHash", "MISSING"), path)
PY
)
  distinct=$(printf '%s\n' "$hashes" | awk '{print $1}' | sort -u | grep -c .)
  if [ "$distinct" -eq 1 ] && ! printf '%s\n' "$hashes" | grep -q MISSING; then
    ok "contentHash $(printf '%s\n' "$hashes" | head -1 | awk '{print $1}') across $count files"
  else
    fail 'contentHash differs (or is missing) across the generated files:'
    printf '%s\n' "$hashes" | body
  fi
}

# ── 3 · the QA jump is absent from Release and present in Debug (B7) ────────
check_qa() {
  step '3 · SentryQAScreen absent from Release, present in Debug (positive control)'
  if [ "${SENTRY_SKIP_BUILD:-0}" != "1" ]; then
    note 'building Release for the simulator (CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)'
    if ! xcodebuild build \
        -project ios/SentrySOC.xcodeproj -scheme SentrySOC -configuration Release \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED_RELEASE" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
        > /tmp/sentry-release-build.log 2>&1; then
      fail 'the Release build failed — see /tmp/sentry-release-build.log'
      tail -20 /tmp/sentry-release-build.log | body
    fi
  fi

  # Measured on Xcode 26.2 and documented on `Services/QAJump.swift`: ENABLE_DEBUG_DYLIB
  # defaults to YES, so a Debug build leaves a ~40 KB stub at SentrySOC.app/SentrySOC and
  # puts the code in SentrySOC.debug.dylib. The guard therefore reads the dylib for the
  # positive control and the plain binary for the assertion.
  local release debug hits control
  release="$DERIVED_RELEASE/Build/Products/Release-iphonesimulator/SentrySOC.app/SentrySOC"
  debug="$DERIVED_DEBUG/Build/Products/Debug-iphonesimulator/SentrySOC.app/SentrySOC.debug.dylib"

  if [ ! -f "$release" ]; then
    fail "no Release binary at $release"
  else
    hits=$(strings -a "$release" | grep -c -e 'SentryQAScreen' -e 'SENTRY_QA')
    if [ "$hits" -eq 0 ]; then
      ok 'Release binary carries no SentryQAScreen / SENTRY_QA literal'
    else
      fail "the Release binary contains the QA jump literal ($hits lines) — SENTRY_QA leaked out of Debug"
    fi
  fi

  if [ ! -f "$debug" ]; then
    fail "no Debug binary at $debug — run 'make build' first; without it the grep is unproven"
  else
    control=$(strings -a "$debug" | grep -c 'SentryQAScreen')
    if [ "$control" -gt 0 ]; then
      ok "positive control: the Debug binary contains SentryQAScreen ($control lines)"
    else
      fail 'grep broken — the Debug binary does NOT contain SentryQAScreen, so this check proves nothing'
    fi
  fi
}

# ── 4 · every shipped face has its licence text (X10) ────────────────────────
check_fonts() {
  step '4 · every Resources/*.ttf has a matching OFL text'
  local faces=0 before=$FAILURES family matched stem
  for ttf in "$RESOURCES"/*.ttf; do
    [ -f "$ttf" ] || continue
    faces=$((faces + 1))
    family=$(basename "$ttf" .ttf | sed 's/-.*//')
    matched=""
    for ofl in "$RESOURCES"/OFL-*.txt; do
      [ -f "$ofl" ] || continue
      stem=$(basename "$ofl" .txt | sed 's/^OFL-//')
      case "$family" in "$stem"*) matched="$ofl" ;; esac
    done
    if [ -z "$matched" ]; then
      fail "$(basename "$ttf") has no OFL-<family>.txt beside it"
    elif ! grep -qi 'SIL OPEN FONT LICENSE\|Copyright' "$matched"; then
      fail "$(basename "$matched") is not a licence text"
    fi
  done
  [ "$faces" -gt 0 ] || fail "no .ttf found under $RESOURCES"
  [ "$FAILURES" -eq "$before" ] && ok "$faces faces, each with its OFL text"
}

# ── 5 · colours and font names live only in Design/ (§4.6) ───────────────────
check_colours() {
  step '5 · no hex colour or font name outside Design/'
  local names outside pattern code_hits comment_hits
  names=$(ls "$RESOURCES"/*.ttf 2>/dev/null | xargs -n1 basename 2>/dev/null \
          | sed 's/-.*//' | sort -u | paste -sd'|' -)
  [ -n "$names" ] || names='IBMPlexMono|SpaceGrotesk'
  outside=$(swift_sources | grep -v "^$APP_SOURCES/Design/")
  pattern="0x[0-9a-fA-F]{6}|#[0-9a-fA-F]{6}\b|($names)-"
  # Comments are excluded by the C11 ruling, so the guard reads comment-stripped source —
  # and the STRING LITERALS too, because `code` mode strips them: a CSS hex and every font
  # face name only ever exist inside a literal, so reading `code` alone left both halves of
  # this check dead (C11 review finding 4). `Font.custom("SpaceGrotesk-Bold", …)` outside
  # Design/ is the case S1 cannot see either — S1 covers only Screens/ and Components/.
  code_hits=$( { $LEX code $outside; $LEX literals $outside; } | grep -E "$pattern")
  if [ -z "$code_hits" ]; then
    ok 'no colour or font-name literal outside Design/'
  else
    fail 'a colour or font name is written outside Design/Theme.swift and Design/Typography.swift:'
    printf '%s\n' "$code_hits" | body
  fi
  comment_hits=$($LEX comments $outside | grep -E "0x[0-9a-fA-F]{6}|#[0-9a-fA-F]{6}\b" | cut -d: -f1-2)
  if [ -n "$comment_hits" ]; then
    note 'hex values written in comments (excluded by ruling; P1-6 removed one by hand):'
    printf '%s\n' "$comment_hits" | body
  fi
}

# ── 6 · S1 · no player copy as a Swift literal ───────────────────────────────
check_s1() {
  step '6 · S1 · no copy literal in Screens/ or Components/'
  local hits
  hits=$($LEX s1 --allow "$SCRIPTS/s1-allow.txt" $(copy_sources))
  if [ -z "$hits" ]; then
    ok "$(copy_sources | wc -l | tr -d ' ') files clean against $SCRIPTS/s1-allow.txt"
  else
    fail 'a string literal containing a letter is authored in Swift — it belongs in chrome.ts:'
    printf '%s\n' "$hits" | body
  fi
}

# ── 7 · B3 · the age-rating grep ─────────────────────────────────────────────
check_profanity() {
  step '7 · B3 · profanity / violence grep (the 4+ questionnaire evidence)'
  local raw left hits tmp
  raw=$(grep -inE "$PROFANITY" \
        "$EXPORTED/copy.json" "$EXPORTED/content.json" $(swift_sources) 2>/dev/null)
  hits=$(printf '%s\n' "$raw" | grep -c .)
  # The hits go to a temp FILE, not down a pipe: a heredoc-fed `python3 -` already
  # owns fd 0 for the script itself, so anything piped in is read as EOF and the
  # filter silently passes everything. C11 review finding 1 — do not reintroduce.
  tmp=$(mktemp "${TMPDIR:-/tmp}/sentry-profanity.XXXXXX") || { fail 'mktemp failed'; return; }
  printf '%s\n' "$raw" > "$tmp"
  left=$(python3 - "$SCRIPTS/profanity-allow.txt" "$tmp" <<'PY'
import sys
allowed = []
with open(sys.argv[1], encoding="utf-8") as handle:
    for raw in handle:
        body = raw.split("  # ", 1)[0].strip()
        if body and not body.startswith("#"):
            allowed.append(body)
with open(sys.argv[2], encoding="utf-8") as handle:
    for line in handle:
        line = line.rstrip("\n")
        if line and not any(entry in line for entry in allowed):
            print(line)
PY
)
  rm -f "$tmp"
  if [ -z "$left" ]; then
    ok "no unlisted hit ($hits accounted for by $SCRIPTS/profanity-allow.txt)"
  else
    fail 'unlisted profanity/violence hits — rewrite the copy or add a reasoned allowlist line:'
    printf '%s\n' "$left" | body
  fi
}

# ── 8 · B4/R12 · the pay-figure guard ────────────────────────────────────────
check_pay() {
  step '8 · B4/R12 · no pay figure in a Swift literal or the exported JSON'
  # R12: over STRING LITERALS extracted from Swift, never raw Swift, so `$0`/`$1`
  # closure arguments cannot trip `\$\s?\d` — and interpolations are stripped, so
  # `"\($0.min)"` cannot either.
  local in_swift in_json
  in_swift=$($LEX literals $(swift_sources) | grep -inE "$PAY")
  in_json=$(grep -inE "$PAY" "$EXPORTED"/*.json "$FIXTURES"/*.json 2>/dev/null)
  if [ -z "$in_swift" ] && [ -z "$in_json" ]; then
    ok 'no salary, pay band or currency figure anywhere in the shipped strings'
  else
    fail 'a pay figure reached a player-facing string (§11 rule 10):'
    printf '%s\n%s\n' "$in_swift" "$in_json" | body
  fi
}

# ── 9 · D1 · the protected web tree and the Cloudflare pipeline ──────────────
check_d1() {
  step '9 · D1 · protected web tree untouched (merge-base diff)'
  local pipeline web base merge_base pipe_diff pipe_dirty web_diff web_dirty
  pipeline='next.config.ts open-next.config.ts wrangler.jsonc app/api'
  web='app/lib/soc app/lib/career app/lib/game app/components/soc'

  if ! git rev-parse --verify --quiet origin/main > /dev/null; then
    fail 'origin/main is not fetched — run `git fetch origin main` (CI: actions/checkout fetch-depth 0)'
    return
  fi
  merge_base=$(git merge-base origin/main HEAD)
  note "merge-base origin/main HEAD = $(git rev-parse --short "$merge_base")"

  # 9a · the pipeline, always against the merge base (§11 rule 9).
  pipe_diff=$(git diff --name-only "$merge_base"...HEAD -- $pipeline)
  pipe_dirty=$(git status --porcelain -- $pipeline)
  if [ -z "$pipe_diff" ] && [ -z "$pipe_dirty" ]; then
    ok 'next.config.ts · open-next.config.ts · wrangler.jsonc · app/api untouched'
  else
    fail 'the protected Cloudflare pipeline was modified:'
    printf '%s\n%s\n' "$pipe_diff" "$pipe_dirty" | body
  fi

  # 9b · the web engine, from the iOS branch point (see ios/scripts/d1-base.txt).
  base="${SENTRY_D1_BASE:-$(grep -v '^#' "$SCRIPTS/d1-base.txt" | grep . | head -1)}"
  if ! git rev-parse --verify --quiet "$base^{commit}" > /dev/null; then
    fail "$SCRIPTS/d1-base.txt names $base, which is not a commit in this repository"
    return
  fi
  # The pin is self-retiring. Take whichever of the two is NEWER as the ruler:
  # once this branch lands, origin/main contains the pinned commit and the merge base
  # moves past it — the pre-iOS web commits d1-base.txt excuses are then behind the
  # merge base, so the merge base is both correct and stricter. Asserting the pin is
  # always the descendant would flip the guard red on the first push after this stage,
  # as a malfunction rather than a real D1 violation (C11 review finding 3).
  if git merge-base --is-ancestor "$base" "$merge_base" 2>/dev/null; then
    note "d1-base.txt pin $(git rev-parse --short "$base") is an ancestor of the merge base — pin retired, measuring from the merge base"
    base="$merge_base"
  elif ! git merge-base --is-ancestor "$merge_base" "$base" 2>/dev/null; then
    fail "$SCRIPTS/d1-base.txt names $base, which is neither an ancestor nor a descendant of the merge base"
    return
  elif [ -n "$(git diff --name-only "$merge_base" "$base" -- $pipeline)" ]; then
    fail "the ratified range $merge_base..$base touches the pipeline — it may not"
    return
  fi
  note "web-engine baseline $(git rev-parse --short "$base") ($(git log -1 --format=%s "$base" | cut -c1-56))"
  web_diff=$(git diff --name-only "$base"...HEAD -- $web ':(exclude)app/lib/soc/exporter')
  web_dirty=$(git status --porcelain -- $web | grep -v 'app/lib/soc/exporter')
  if [ -z "$web_diff" ] && [ -z "$web_dirty" ]; then
    ok 'app/lib/soc · app/lib/career · app/lib/game · app/components/soc untouched by the iOS stages'
  else
    fail 'an iOS ticket edited the read-only web tree (D1 / §11 rule 2):'
    printf '%s\n%s\n' "$web_diff" "$web_dirty" | body
  fi
}

# ── dispatch ─────────────────────────────────────────────────────────────────

ALL='export hash qa fonts colours s1 profanity pay d1'
WANTED="${*:-$ALL}"

printf 'SENTRY — SOC release guard · %s\n' "$(date '+%Y-%m-%d %H:%M')"
for NAME in $WANTED; do
  case "$NAME" in
    1|export)    check_export ;;
    2|hash)      check_hash ;;
    3|qa)        check_qa ;;
    4|fonts)     check_fonts ;;
    5|colours)   check_colours ;;
    6|s1)        check_s1 ;;
    7|profanity) check_profanity ;;
    8|pay)       check_pay ;;
    9|d1)        check_d1 ;;
    *) printf 'unknown check "%s" — one of: %s\n' "$NAME" "$ALL"; exit 2 ;;
  esac
done

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  printf 'RELEASE GUARD GREEN — %s check(s), 0 failures.\n' "$RAN"
  exit 0
fi
printf 'RELEASE GUARD RED — %s of %s check(s) failing. Do not archive.\n' "$FAILURES" "$RAN"
exit 1
