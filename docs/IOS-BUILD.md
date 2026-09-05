# SENTRY — SOC · build runbook

The native SwiftUI iPhone app in `ios/`. This file is the whole story: what to install, what
to run, why the build is shaped the way it is, and the six steps only the founder can do.

Architecture lives in [`docs/ios/SPEC.md`](ios/SPEC.md); where that file and
[`docs/ios/SPEC-ADDENDUM.md`](ios/SPEC-ADDENDUM.md) disagree, **the addendum wins**. Product
design is [`docs/ios/DESIGN.md`](ios/DESIGN.md). The App Store package is
[`docs/APPSTORE.md`](APPSTORE.md). The founder's sign-off checklist and the open visual
defects are [`docs/PLAYTEST-ios.md`](PLAYTEST-ios.md).

---

## 1 · The short version

```bash
git clone https://github.com/arvindjuneja/link26.git && cd link26
npm ci
make                     # the whole gate: export → tests → engine → app → shots → guard
```

`make` runs the ten steps of SPEC §7 in order and stops at the first failure. Individual
steps:

| target | what it runs |
|---|---|
| `make export` | `npm run soc:export` — regenerate the bundle and the seven fixtures |
| `make contract` | `npm test` (with the drift guard) · `tsc --noEmit` · `next build` · the D1 diff |
| `make engine` | `swift test --package-path ios/SentryCore` — the parity gate |
| `make project` | `xcodegen generate --spec ios/project.yml` |
| `make build` / `make test` / `make app` | simulator build, then `xcodebuild test` (86 cases / 8 suites) |
| `make shots` | 13 screens × 3 Dynamic Type sizes + the narrow pass → `docs/screenshots/ios/gate/` |
| `make guard` | `ios/scripts/verify.sh` — the nine release checks |
| `make clean` | drop `ios/.build`, `ios/.build-release` and the generated `.xcodeproj` |

The release guard alone, and one check at a time:

```bash
bash ios/scripts/verify.sh              # all nine
bash ios/scripts/verify.sh s1 pay d1    # by name: export hash qa fonts colours s1 profanity pay d1
```

**`bash`, not `sh`.** Both scripts need `set -o pipefail`, which is not POSIX; ubuntu's
`/bin/sh` is dash and rejects it outright, killing the run before a single check executes.
The scripts re-exec themselves under bash if you forget, but write `bash` in CI and in the
`Makefile` so the intent is on the page.

---

## 2 · Toolchain (pinned)

| tool | version | note |
|---|---|---|
| Xcode | **26.2 (17C52)** | iOS 26 SDK. Mandatory for App Store uploads since 2026-04-28. |
| Swift | **6.2.3** (`swiftlang-6.2.3.3.21`) | `swift-tools-version: 6.2`, `.swiftLanguageMode(.v6)` |
| XcodeGen | **2.44.1** | `brew install xcodegen`. `project.yml` pins `minimumXcodeGenVersion: 2.44.0`. |
| Node | **≥ 22** | measured on 25.1.0 / npm 11.6.2; CI runs 24 |
| tsx | **4.23.13** | exact, in `devDependencies` (B5) |
| Python | **3.9+** | `ios/scripts/swiftlex.py`, the guard's Swift lexer. macOS ships it. |
| idb | optional | only `shots.sh`'s `evidence` capture needs it (`brew install idb-companion`) |
| Simulator | iPhone 17 Pro Max, iOS 26.2 | resolved by name; falls back to `C2136147-45C8-42DD-8E3A-EDE974B97154` |

```bash
sudo xcode-select -s /Applications/Xcode_26.2.app    # if you keep several Xcodes
xcodebuild -version && swift --version && xcodegen --version && node --version
```

**Fonts** are committed, with their URLs, PostScript names, the step of the type scale each
one serves, and a SHA256 per file, in
[`ios/SentrySOC/Resources/FONTS.md`](../ios/SentrySOC/Resources/FONTS.md). Verify with
`shasum -a 256 -c` from that directory. Never Fontsource: those packages ship woff/woff2
only and iOS cannot register them. Six faces — IBM Plex Mono Regular/Medium/SemiBold and
Space Grotesk Regular/Medium/**Bold**; `SpaceGrotesk-SemiBold` named by SPEC §6 does not
exist upstream (R8/R11).

---

## 3 · Reproducing from a clean clone

Measured on 2026-09-06 in a temp directory, from `git clone` through a green simulator build.
Nothing outside the clone is needed — no Apple account, no `Package.resolved`, no network
after `npm ci` (`SentryCore` has **zero** remote dependencies by design).

```bash
cd "$(mktemp -d)"
git clone https://github.com/arvindjuneja/link26.git && cd link26
npm ci

# 1 · the parity gate — no Xcode project, no simulator, ~6 s
swift test --package-path ios/SentryCore
#   → Test run with 186 tests in 17 suites passed

# 2 · the app — generate the project, then build it unsigned
xcodegen generate --spec ios/project.yml
xcodebuild build -project ios/SentrySOC.xcodeproj -scheme SentrySOC -configuration Debug \
  -destination 'platform=iOS Simulator,id=C2136147-45C8-42DD-8E3A-EDE974B97154' \
  -derivedDataPath ios/.build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
#   → ** BUILD SUCCEEDED **
```

**The two signing flags are not optional** (SPEC-ADDENDUM §6). `project.yml` sets
`CODE_SIGN_STYLE: Automatic` with `DEVELOPMENT_TEAM: "${SENTRY_DEV_TEAM}"`, because the
earlier setting — signing disabled in the project — made Xcode install an *unsigned* binary
on a physical iPhone and the device rejected it (`LaunchExecutableValidationErrorDomain`,
"No code signature found"). Signing therefore stays on in the project and is turned off on
the **command line** for simulator, CI and release-guard builds. A build without the flags
and without `SENTRY_DEV_TEAM` needs a Team and will fail on a bare clone.

---

## 4 · Why the build is shaped this way

### Rule #1 · all project configuration lives in `ios/project.yml`

`ios/SentrySOC.xcodeproj` and `ios/SentrySOC/Info.plist` are **generated and gitignored**
(D24). Every build setting, every Info.plist key, every font entry, the scheme and the test
target are declared in `project.yml`. A setting changed in the Xcode UI survives until the
next `xcodegen generate` and then vanishes — so change `project.yml` and regenerate, always.
The file was written once, by C6, and declares directories that did not exist yet; every
source path is a whole-tree recursive glob, which is why four later tickets added files
without touching it (§7.2).

### The parity contract

The web app is the source of truth for content and for engine behaviour. `npm run soc:export`
walks `app/lib/soc/**` and writes **ten** JSON files — three into
`ios/SentryCore/Sources/SentryContent/Resources/` (the shipped bundle) and seven into
`ios/SentryCore/Sources/SentryFixtures/Resources/` (test-only, never linked by the app).
All ten carry the same `contentHash`, a sha256 over the canonical bytes, so a re-encode
anywhere breaks the check.

`SentryCore` then re-implements the engine in Swift, file-for-file against the TypeScript
(SPEC §3.2), and `swift test` asserts the Swift output **equals** the fixtures — exact
equality, not a tolerance, because JS emits shortest-round-trip IEEE-754 and Swift's
`JSONDecoder` reconstructs the identical bit pattern (verified: `0.8571428571428571 == 6.0/7.0`).
186 named cases across 17 suites: golden grades, the 12 synthetic rows that reach all 11
`OutcomeKey`s, trace, shift runs, scoring, tuning, career, inbox, integrity, lenient schema,
the reducer, effects, heartbeat and the haptic patterns.

The app layer has its own suite — `xcodebuild test` runs **86 cases in 8 suites**
(`SentrySOCTests`): fonts, the save store, the effect schedule, the hub's Dock ladder, career
reset and sheet dismissal, plus the component behaviour and snapshot suites. Both suites are
Swift Testing, not XCTest, so `xcodebuild`'s legacy summary line prints *"Executed 0 tests"*
right before `** TEST SUCCEEDED **` — read the `Test run with N tests … passed` line above it
instead.

`OutcomeKey` is a **closed** enum, deliberately against the lenient decoding used everywhere
else: a new branch added in TypeScript fails to decode the bundle at load, naming the key,
before any test runs. There is no path where the web logic changes and Swift stays quietly
green.

The **openness policy**, in one line: everything the content can extend is lenient
(`SocArchetype`, `ToolSeverity`, `EvidenceWeight`, `Tone`, `HandlerTone` — `RawRepresentable`
structs that decode anything and fall back to a documented default), and everything the
*engine* branches on is closed (`Disposition`, `SocVerdict`, `OutcomeKey`,
`InvestigationQuality`, `ShiftGrade`).

### What is deliberately **not** shared

- **The session reducer.** `SentryCore/Session/` is new Swift with no TypeScript counterpart
  and no fixtures (DV-5). The web's console is a React component with its state inline; the
  app needed a real 17-action machine, and porting the component would have imported its
  presentation.
- **All presentation.** No colour, type, motion, layout or haptic decision crosses the
  boundary. `SentrySOC/Design/` is the only place a hex value or a font name is written down,
  and the guard enforces it.
- **Player copy is shared but not authored twice.** Every string a player reads comes out of
  `copy.json`; a Swift string literal containing a letter in `Sources/Screens/**` or
  `Sources/Components/**` fails the guard (S1). New copy goes through
  `app/lib/soc/exporter/chrome.ts`, never a Swift literal.
- **iOS-only save fields** are documented divergences, not drift: `dailyDoneOn` (DV-6) and
  `clearedShiftIDs` (DV-9). The web tracks neither.

### The release guard

`ios/scripts/verify.sh` is nine checks (§7 step 6, amended). Three of them are lexical rather
than textual and go through `ios/scripts/swiftlex.py`, a small Swift lexer, because a plain
`grep` gets them wrong: it counts doc comments and `#Preview` fixtures as copy, it cannot see
a `#if SENTRY_QA` region, and `\$\s?\d` matches every `$0` closure argument (R12). Three
allowlists are committed, each line carrying its reason:

| file | what it excuses |
|---|---|
| `ios/scripts/s1-allow.txt` | copy-pack address accessors, diagnostics, and C9's `MetaIdentifiers.swift` |
| `ios/scripts/profanity-allow.txt` | the one accepted B3 hit — "don't kill the rule that catches the real thing" |
| `ios/scripts/d1-base.txt` | the baseline for the web half of the D1 diff, and why it is not the merge base |

Two of the nine read **string literals as well as comment-stripped code**: check 5 (colours
and font names) has to, because a CSS hex and every font face name only ever exist inside a
literal — reading `swiftlex code` alone left both halves of that check dead. And check 7
(profanity) writes its hits to a temp file rather than piping them into a heredoc-fed
`python3 -`: the heredoc owns fd 0, so anything piped in reads as EOF and the filter passes
everything. Both were dead guards until C11's review; do not undo either.

The `d1-base.txt` pin is **self-retiring**. Once this branch lands, `origin/main` contains the
pinned commit, the merge base moves past it, and the guard prints `pin retired` and measures
from the merge base — which is then both correct and stricter. Asserting the pin must always
be a *descendant* of the merge base would flip the guard red on the first checkpoint push.

The QA-jump check has a **positive control**: the Release binary must not contain
`SentryQAScreen` *and* the Debug binary must. Measured on Xcode 26.2, `ENABLE_DEBUG_DYLIB`
defaults to `YES`, so a Debug build puts the code in `SentrySOC.app/SentrySOC.debug.dylib`
and leaves a ~40 KB stub as `SentrySOC.app/SentrySOC` — read the dylib for the control and
the plain binary for the assertion, or the guard passes while proving nothing.

---

## 5 · The kill-and-relaunch check (manual)

The mid-shift-snapshot acceptance test. Do it by hand after any change to `SaveStore`,
`GameModel` or the reducer's effects:

```bash
make build
xcrun simctl install  C2136147-45C8-42DD-8E3A-EDE974B97154 \
  ios/.build/Build/Products/Debug-iphonesimulator/SentrySOC.app
xcrun simctl launch   C2136147-45C8-42DD-8E3A-EDE974B97154 pl.oumm.sentry.soc
```

1. Clock in to Shift 1.
2. Pull two sources on the first alert.
3. File one call and read the debrief.
4. `xcrun simctl terminate C2136147-45C8-42DD-8E3A-EDE974B97154 pl.oumm.sentry.soc`
5. Relaunch.

**Pass:** the Hub shows a **Resume** card, and resuming restores the exact `ShiftState` —
the same alert index, the same `queried` sources, the same breach-risk and noise meters, the
same time used. A cold Hub with no Resume card is a failure, and so is a Resume that restores
the board but not the meters.

`SentrySOCTests/SaveStoreTests` and `CareerResetTests` cover seed → reset → kill → relaunch in
CI; this check covers the part only a person can see.

### Driving the app by hand

`-SentryQAScreen <name>` jumps straight to a screen in a **Debug** build (D19; compiled only
under `SENTRY_QA`). Every jump *plays* the board through the reducer, so the screen shows a
session the machine actually produced:

```bash
xcrun simctl launch C2136147-45C8-42DD-8E3A-EDE974B97154 pl.oumm.sentry.soc \
  -SentryQAScreen debrief
```

Names: `hub · intro · board · case · source · call · abandon · debrief · debrief-readonly ·
summary · rankup · settings · firstrun · kit`. **`evidence` is not one of them** — it is a
tab of the case screen, and asking for it trips an assertion in Debug (DEF-1 in
`docs/PLAYTEST-ios.md`). `shots.sh` reaches it the way a player does.

---

## 6 · CI

`.github/workflows/ios.yml`, four jobs, every checkout at `fetch-depth: 0` because both the
drift guard and the D1 diff read history.

| job | runner | required | runs |
|---|---|---|---|
| `contract` | ubuntu | **yes** | `npm ci` · export-is-idempotent · `npm test` · `tsc` · `next build` · the D1 diff |
| `engine` | macOS | **yes** | `swift test --package-path ios/SentryCore` — needs no Xcode project and no simulator |
| `guards` | ubuntu | **yes** | `verify.sh export hash fonts colours s1 profanity pay d1` |
| `app` | macOS | no (`continue-on-error`) | Xcode 26.x · `xcodegen` · `xcodebuild build` + `test` · `verify.sh qa` · upload the screenshots |

`app` is allowed to fail because whether a GitHub-hosted macOS image carries Xcode 26.x is
outside our control (X16). When it does not, the founder's Mac is the app gate — and the
parity gate was designed to need no Xcode precisely so that this is survivable. `verify.sh qa`
runs inside `app` rather than `guards` because it is the one check that needs both built
binaries.

---

## 7 · FOUNDER STEPS

Six things no agent can do. 1–2 are unblocked today; 3 is blocking submission.

### 1 · Run it on your own iPhone

```bash
export SENTRY_DEV_TEAM=<YOUR TEAM ID>        # Apple Developer → Membership
xcodegen generate --spec ios/project.yml
open ios/SentrySOC.xcodeproj
```

Pick your iPhone in the scheme's destination menu and press **Run**. Automatic signing
registers the App ID `pl.oumm.sentry.soc` and a development profile by itself — **no App
Store Connect step is needed to run on your own device** (measured; ASC matters only for
TestFlight and the store). On the phone, first launch only:
**Settings → General → VPN & Device Management → trust the developer certificate.**

Setting the Team in Xcode → Signing & Capabilities also works, but only until the next
`xcodegen generate` overwrites the project — `SENTRY_DEV_TEAM` is the durable form.

### 2 · The ADP and App Store Connect record

1. Apple Developer Program membership active; **all agreements accepted** in App Store
   Connect (a lapsed agreement blocks an upload with a message that does not say so).
2. Register the bundle id **`pl.oumm.sentry.soc`**. Do this early — the ASC record and an
   internal TestFlight group can exist long before the first archive.
3. Create the App Store Connect app record: name **SENTRY — SOC**, primary language English,
   SKU your choice. The full metadata sheet is `docs/APPSTORE.md`.
4. Create an **internal TestFlight group** and add yourself. Internal testing needs no
   Beta App Review, so the first build is installable within minutes of processing.

### 3 · Deploy the web app so `/privacy` is live, then confirm the About link

Guideline 5.1.1(i) wants a privacy-policy link **in ASC metadata and inside the app**, even
at zero collection. The app already prints the policy summary inline and the URL as
selectable text under the link (P1-4), and the page exists in this repo as
`app/privacy/page.tsx` — `npm run build` prerenders it as `○ /privacy`.

What is missing is the deploy. Measured: the Cloudflare account is `arvind@oumm.pl`
(`3acdf223fcda4fc096af1e98dedac3ba`), the Worker `link26` is deployed, and the account's
workers.dev subdomain is `arvind` — but `https://link26.arvind.workers.dev/privacy` answers
**404 · error code 1042** because the Worker has no workers.dev route enabled.

```bash
npx wrangler whoami        # confirm the account
npm run deploy             # with workers.dev routing enabled
open https://link26.arvind.workers.dev/privacy
```

Then launch the app → **Settings → About → Privacy policy** and confirm the
`SFSafariViewController` opens that page. Paste the same URL into the ASC privacy-policy
field.

*If you would rather serve it from `link26.oumm.pl`, that host needs a certificate first:
re-measured, it resolves to `2.57.137.2` presenting `CN=*.zenbox.pl`, so **every** URL on it
opens Safari's "This Connection Is Not Private" interstitial. Changing the host afterwards is
one line — `MetaID.privacyPolicy`.*

### 4 · The device haptics pass — **blocking before submission**

The Simulator has no haptic hardware (X7), so every curve in `SentryCore/Feel/` is verified
only by `swift test`'s exact event times, intensities and control points. Wrong sharpness or a
dub 40 ms late reads as a cheap buzz and undoes the premium feel the design is built on.

With the app running on the phone, feel for four things:

- **The heartbeat at HUNT, then at LOCKDOWN.** A lub-dub, not a buzz: a 90 ms continuous lub
  with its intensity curve, a transient dub 120 ms later. HUNT is 0.536 s per beat at 0.75
  intensity; LOCKDOWN is 0.400 s at 1.00. **The escalation must gain *weight*, not only speed
  and sharpness** — that is exactly what P1-8 changed (the loop is now authored at the
  loudest band and scaled down for HUNT, because Core Haptics dynamic parameters are a 0…1
  multiplier and a loop authored at HUNT had no headroom left). It must be silent at CALM and
  ALERT.
- **Filing a call.** The hold-to-file ring's completion: the `file` pattern, a firm settle,
  not a click.
- **The breach thud.** Missing a real threat. Low, heavy, single.
- **Rank-up.** The four-event promotion pattern under the badge draw.

Also confirm the guards by feel: nothing beats outside `investigating`, nothing beats while
the app is backgrounded, and the Settings switch silences everything.

Log what you feel in `docs/PLAYTEST-ios.md` — that checklist is the sign-off.

### 5 · Screenshots and metadata

`make shots` writes the gate set; the App Store needs the 6.9″ set from the iPhone 17 Pro Max
listed in `docs/APPSTORE.md` §5. The status bar is already pinned to 09:41 with full bars and
a charged battery, which is what the store wants.

### 6 · Archive → Distribute

```bash
export SENTRY_DEV_TEAM=<YOUR TEAM ID>
xcodegen generate --spec ios/project.yml
```

Then **Product → Archive** in Xcode (the scheme's archive action is already the Release
config), **Distribute App → App Store Connect → Upload**. Or on the command line:

```bash
xcodebuild archive -project ios/SentrySOC.xcodeproj -scheme SentrySOC \
  -destination 'generic/platform=iOS' -archivePath build/SentrySOC.xcarchive
xcodebuild -exportArchive -archivePath build/SentrySOC.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
```

**Run `bash ios/scripts/verify.sh` and get a green line before every archive.** It is the last
thing between a QA jump and the App Store.
