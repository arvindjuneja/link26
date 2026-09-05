# SENTRY — SOC · native SwiftUI iPhone architecture

**Final spec. Lead decision, 2026-09-05.** Synthesises the parity-first and native-craft proposals.

This document **replaces** `ios-design-spec.md` §1 (Vite/Capacitor build), §8 (tickets) and §9
(verification). It **inherits, unchanged**: §2 (information architecture — the phase/view machine
§2.1, layout and thumb zones §2.2, every wireframe §2.3–§2.13, motion §2.14, haptic cue vocabulary
§2.15, colour/type tokens §2.16), §3 (Shift-4 handoff re-voice + the 0/40/80/120/160 ladder), §4
(campaign + daily algorithm), §6 (App Store package), §7 (risks R1–R25), and the whole of
`ios-design-spec-addendum.md` §C (the 17-action machine), §F, §G. Wireframes are referenced, never
repeated here.

Where this document and either proposal disagree, this document wins. Every conflict is resolved
explicitly in §0 with the reason.

---

## 0 · Decisions (binding)

**Verified on this Mac today, by me, not quoted:** Xcode 26.2 (17C52) · Swift 6.2.3 ·
iOS 26.2 SDK · XcodeGen 2.44.1 · iPhone 17 Pro Max sim `C2136147-45C8-42DD-8E3A-EDE974B97154`
booted · Node 25.1.0 · tsx 4.23.13 · vitest include glob `app/**/*.test.ts`.

### The contract

- **D1 · The web tree is READ-ONLY.** The founder decision — "the web `/soc` route is NOT changed by
  the iOS work" — is enforced literally. No iOS ticket edits `app/lib/soc/{cases,engine,handoff,types}.ts`,
  `app/lib/career/{state,handler}.ts`, `app/lib/game/trace.ts`, or
  `app/components/soc/{SocConsole,SocOnboarding}.tsx`. The web tree gains exactly **one new
  directory** (`app/lib/soc/exporter/`) and nothing else. CI proves it with
  `git diff --exit-code $(git merge-base origin/main HEAD) -- app/lib/soc app/lib/career app/lib/game app/components/soc`.
  *Resolves against the parity proposal's T1, which refactored `SocConsole.tsx`, `engine.ts` and
  `handler.ts` into `copy.ts`/`tuning.ts`. That is a better codebase and a violated constraint.*

- **D2 · `outcomeKey` is derived in the exporter, not added to `engine.ts`.**
  `app/lib/soc/exporter/outcomes.ts` re-derives 11 keys and the export **asserts**
  `gradeCall(c,d).outcome === COPY.outcomes[deriveOutcomeKey(c,d)]` for all 96 (case × disposition)
  pairs. Any wording change in `engine.ts` aborts the export naming the pair. Swift compares a keyed
  enum, never prose. *Follows from D1.*

- **D3 · The 26-source catalogue is derived by de-duplication, not exported from `cases.ts`.**
  I verified: iterating `SOC_CASES[].sources` and keying by `id` yields exactly **26** sources. So
  `export const SOURCES = S` — which both proposals assumed — is **not** needed. *Follows from D1;
  neither proposal spotted that the dedupe is sufficient.*

- **D4 · The blue-only ladder (0/40/80/120/160) and the five §3.2 re-voiced strings are SHA-pinned
  exporter overrides.** `SHIFTS` and `caseFromRedRun` are never mutated and never gain a `voice`
  option, so `state.test.ts`'s two red-run assertions and `handoff.test.ts` stay green untouched.
  An override whose pinned source text has changed aborts the export with
  `stale override: soc-handoff-the-key.why`. *Native-craft's mechanism; it is the only one compatible
  with D1.*

- **D5 · The taxonomy / intro / ladder paragraphs ship as `RichSegment[]` (text + tone run),
  hand-transcribed in the exporter and pinned to the JSX by SHA256 of a delimited source slice.**
  The parity proposal wanted one shared RichText model consumed by React and SwiftUI — correct, but
  it requires editing `SocConsole.tsx`. Native-craft lifted flat strings — safe, but iOS loses the
  cyan/rose/emerald verdict runs that carry the DEF-A teaching. The synthesis: iOS gets real colour
  runs; `sourcePins.ts` hashes the JSX region so an edit to the web copy fails the export and forces
  a human re-transcription. Colour without a silent-drift hole.

- **D6 · The daily board is PRECOMPUTED at export — 730 days — and no PRNG is ported to Swift.**
  `fnv1a32` + `xorshift32` + rejection sampling depend on JS `Math.imul` and `>>> 0` semantics; it
  is the single highest-risk thing in the plan to port bit-for-bit, and it buys nothing, because the
  board is a pure function of the date. The generator lives in `app/lib/soc/exporter/daily.ts` (not
  `app/lib/soc/daily.ts` — D1). Recency is derived from the calendar's own previous three days, so
  every player on a given date gets the same board and the client keeps no ledger. Past the horizon
  the app wraps `(daysSince(horizonStart) mod days.count)` — deterministic and documented.
  *Parity's call, over native-craft's Swift port.*

- **D7 · Every number the engine branches on is read from `content.tuning`; `Sources/SentryCore/Engine/`
  contains no numeric literal.** A designer retune in the exporter's `tuning.ts` is a zero-Swift-change
  operation. Native-craft's counter-argument (a hardcoded Swift constant catches a typo) is already
  covered for free by the 96 golden grade rows, which are computed by the *real TypeScript engine* —
  a wrong transcribed tuning number makes Swift disagree with the fixture. Additionally,
  `EngineTests/TuningExpectationTests` holds a hardcoded table of the 14 tuning numbers so that a
  *silent* exporter change to one of them is loud in review. Belt and braces, both cheap.

- **D8 · `ShiftState.results` is an ordered `[CaseResult]`, and its meters are `public internal(set)`.**
  TS iterates `Object.values()` in insertion order; a Swift `Dictionary` has none. `scoreShift` is
  order-independent *today*, but the board glyph strip, the read-only debrief and any future
  order-dependent rule all want order, and array Codable round-trips are byte-stable for fixtures and
  `session.json`. `internal(set)` (not `private(set)` — that would be file-scoped and the engine lives
  in another file) makes meter arithmetic outside `SentryCore` a **compile error**, which is the
  boundary both proposals asked for and only one specified correctly. Documented as divergence DV-1.

- **D9 · The session reducer and its `[Effect]` list live in `SentryCore`, not the app.** A pure
  `reduce(_:_:content:career:) -> (SessionState, [Effect])` runs in the 4-second macOS `swift test`
  loop instead of an 8-minute simulator `xcodebuild test`. It is **explicitly not parity-guarded** —
  there is no TypeScript counterpart to compare against; it is unit-tested. The effect *schedule* is
  testable, which is where "the debrief buzzed twice" bugs live. *Native-craft's call, over parity's
  app-target `SessionMachine`.*

- **D10 · Closed enums exactly where logic lives; lenient `RawRepresentable` everywhere content grows.**
  Closed: `SocVerdict`, `Disposition`, `ShiftGrade`, `TraceStatus`, `OutcomeKey`, `InvestigationQuality`.
  Lenient (unknown raw values decode and round-trip): `SocArchetype`, `ToolSeverity`, `EvidenceWeight`.
  Unknown JSON keys are ignored. So authoring a 25th case with a new archetype costs **zero Swift**,
  while adding an engine branch **fails to decode** and names the key. *Parity's policy; native-craft
  made everything closed, which breaks the zero-Swift-for-content promise.*

### Verified content facts that shape the plan

- **D11 · The `tp.under-contained` grading branch is DEAD over the shipped corpus. I confirmed it:
  0 of 96 rows produce `breachDelta == 10`.** Every TP whose `correctDisposition` is
  `escalate-ir-isolate` also lists `escalate-tier2` as acceptable (8 of them), and the two whose
  correct call is `escalate-tier2` (`soc-phish-harvest`, `soc-insider-departing`) have **empty**
  acceptables, so isolating them lands in *over*-contained. The 96-row matrix therefore reaches only
  **10 of the 11 outcome strings**. A `grades-synthetic.json` fixture with 3 constructed cases × 4
  dispositions is **mandatory**, not optional. *Native-craft found this; I re-derived it.*

- **D12 · 11 `OutcomeKey`s, 12 branch arms, 7 distinct delta pairs.** The key is a *copy* key: it maps
  1:1 to the 11 outcome strings in `engine.ts`. `fp.escalated` covers two arms
  (`escalate-tier2` → noise 12, `escalate-ir-isolate` → noise 20) because they share one string.
  Deltas therefore come from `tuning`, never from the key. Verified delta pairs across 96 rows:
  `0/0 0/4 0/12 0/14 0/20 0/24 30/0`.

- **D13 · The `?demo=complete` Shift-1 golden run is pinned to values I ran today:**
  `{total:7, verdictCorrect:6, dispositionCorrect:6, missedDetections:0, falseEscalations:1,
  accuracy:0.8571428571428571, blindCalls:1, thoroughCalls:6, investigationRate:0.875,
  grade:"rough", breachRisk:0, noise:12}` → `overallShiftStatus == CALM` →
  `{cashGain:300, standingGain:15, rankUp:null}` → career `{cash:300, standing:15, shiftsCleaned:0}`.
  I also confirmed the float claim on the real probe package: JS `0.8571428571428571` decodes in
  Swift to **exactly** `6.0/7.0`, so fixtures assert `==` on `Double`, not a tolerance.

### Platform

- **D14 · Minimum iOS 18.0.** `@Observable`, `.sensoryFeedback` and `.contentTransition(.numericText())`
  need 17; the two that decide it are **`onScrollGeometryChange`** (the Case screen's collapsing
  header with no GeometryReader-in-a-ScrollView hack) and **`MeshGradient`** (the cold-glass ground
  and the LOCKDOWN tunnel-vision, one view instead of a stack of blurs). Escape hatch, documented:
  dropping to 17.0 costs exactly those two, each with a one-file replacement. Both proposals agreed;
  this overrides `ios-design-spec.md` §6's 16.0.

- **D15 · Swift 6 language mode everywhere.** `SentryCore` is 100 % `Sendable` value types and free
  functions, imports **Foundation only** (no UIKit / SwiftUI / CoreHaptics), and compiles under
  `.swiftLanguageMode(.v6)` with no `@unchecked` and no actors. The app target sets
  `SWIFT_STRICT_CONCURRENCY=complete` **plus** `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` and
  `SWIFT_APPROACHABLE_CONCURRENCY=YES` (I verified both keys exist in Xcode 26.2's `Swift.xcspec`),
  so views, stores and the haptics engine are MainActor by default with no annotation noise. The one
  deliberate off-main hop is `actor SaveStore`, which takes `Sendable` value snapshots.

- **D16 · Navigation: no `NavigationStack` for the shift loop.** A `NavigationStack` hands the player
  an interactive swipe-back out of a completed debrief into the call sheet, breaking both the ceremony
  and the one-call-per-case guarantee. `RootView` is a `PhaseHost` `ZStack` switching on
  `session.phase`; overlays are `.sheet(item:)` with `presentationDetents`; `FirstRun` and `RankUp`
  are `.fullScreenCover`. `NavigationStack` appears in exactly one place: inside `SettingsView`
  (Settings → About → Licences), where swipe-back is correct.

- **D17 · The heartbeat "lub" is a 90 ms `.hapticContinuous` event with an intensity parameter curve
  (0 → 1.0 by 18 ms → 0 by 90 ms), not a transient.** A transient is a click; the curve is what makes
  it a *thump*. Dub is a transient at +120 ms. One `CHHapticAdvancedPatternPlayer` with
  `loopEnabled = true` and `loopEnd = period` — the OS schedules every beat, so there is no `Timer`,
  no drift, no per-beat main-thread wake-up. *Native-craft's pattern, over parity's transient lub.*

- **D18 · Reduce Motion kills visual motion only; it does NOT disable haptics.** Reduce Motion is a
  vestibular setting; the heartbeat is a non-visual channel and is an accessibility *aid* for players
  who cannot track the meter animation. The Settings toggle remains the haptics off-switch, and
  `capabilitiesForHardware().supportsHaptics` gates the hardware. **Documented divergence from
  `ios-design-spec.md` §2.15 guard 5.** Reduce Motion does kill: the ECG scroll, the stamp spring,
  the badge draw, the glow pulse, the meter sweep, the count-ups.

- **D19 · QA screen-jumps compile only under `#if SENTRY_QA`,** a compilation condition set on the
  **Debug** configuration only, driven by launch argument `-SentryQAScreen <name>`. A named condition
  is greppable, so the release guard can prove its absence with `strings` on the Release binary.
  *Native-craft's, over parity's `#if DEBUG` + `-uiTestScreen`.*

- **D20 · `TARGETED_DEVICE_FAMILY` must be set at the TARGET level, not the project level.** I built
  the smoke project and read the settings back: with `TARGETED_DEVICE_FAMILY: "1"` under project
  `settings.base`, `xcodebuild -showBuildSettings` reports **`1,2`** — XcodeGen injects a target-level
  default that wins. This silently ships an iPad-capable binary and breaks the §6 iPhone-only
  positioning. Verified gotcha; neither proposal flagged it, and the parity proposal's `project.yml`
  has the bug.

- **D21 · `UIAppFonts` entries are BARE filenames.** `App/Resources` is added as an XcodeGen resources
  path, which adds each file individually and flattens it into the bundle root — so
  `IBMPlexMono-Regular.ttf`, not `Fonts/IBMPlexMono-Regular.ttf`. This is what the verified smoke
  build used. `FontRegistrationTests` asserting `UIFont(name:size:) != nil` for all six faces is the
  backstop, because the failure mode is a *silent* fallback to system-ui.

- **D22 · `PRODUCT_NAME: SentrySOC` (no space); `CFBundleDisplayName: SENTRY SOC`.** Native-craft's
  `PRODUCT_NAME: SENTRY SOC` produces `SENTRY SOC.app`, a space in every `simctl` path in every
  script. One bundle id, `pl.oumm.sentry.soc`, in **both** configurations — no `.dev` suffix, so
  scripts never pick the wrong one.

- **D23 · Golden fixtures live in their own SPM target (`SentryFixtures`) that only the test targets
  depend on,** so ~200 KB of JSON never ships in the app, and every generated artefact sits in a
  directory owned by exactly one ticket. I verified on the probe package that multi-target SPM
  resources and `Bundle.module` resolve in both a library and a test-only target under
  swift-tools 6.2 with `swift test` green.

- **D24 · The `.xcodeproj` and `Info.plist` are GENERATED and gitignored.** `ios/project.yml` is the
  only place project configuration exists. Crucially, the parity gate
  (`swift test --package-path ios/SentryCore`) needs neither XcodeGen nor the project, so a generation
  problem can never block the contract.

- **D25 · The agent deliverable ends at:** green `npm test` (with the drift guard), green
  `swift test`, green `xcodebuild build`+`test` against the simulator, committed screenshots, and
  `docs/IOS-BUILD.md`. Signing, bundle-id registration, the ASC record, TestFlight, the device
  haptics pass and `Archive → Distribute` are **founder steps**, listed in the runbook.

---

## 1 · Repo layout

All paths absolute under `/Users/arvind/Documents/projekty/link26/`. `[Cn]` = owning ticket (§10).

```
app/lib/soc/exporter/                  ← the ONLY addition to the web tree      [C1]
  schema.ts          the ExportedBundle / ExportedCopy / fixture DTOs — FROZEN in hour 1
  canonical.ts       key-sorted, 2-space, LF, trailing-newline, UTF-8, no-BOM serialiser + sha256
  sourcePins.ts      SHA256 pins over delimited slices of SocConsole.tsx / SocOnboarding.tsx / handoff.ts
  outcomes.ts        OUTCOME_KEYS (11) + deriveOutcomeKey(case, disposition)      (D2)
  tuning.ts          the 14 tuning numbers, transcribed from engine.ts/state.ts/trace.ts (D7)
  copy.ts            every player-facing string + the RichSegment[] paragraphs    (D5)
  blueOnly.ts        the 0/40/80/120/160 ladder + the 5 re-voiced strings         (D4)
  bundle.ts          buildBundle(): SOC_CASES/SHIFTS/RANKS/KIT → ExportedBundle
  daily.ts           dailyCalendar(horizonStart, days=730) — pure, exhaustively tested (D6)
  fixtures.ts        buildFixtures(): the 7 golden files
  diffSummary.ts     the human "what changed" report printed to stdout
  drift.test.ts      the drift guard — MUST live under app/** (vitest include glob, verified)
  daily.test.ts      the §4.2 constraint suite over 730 dates
scripts/
  export-soc-content.ts                thin CLI over bundle.ts/fixtures.ts       [C1]
package.json                           +soc:export, +soc:check; −@capacitor/*, −@fontsource*  [C1]

ios/
  .gitignore          SentrySOC.xcodeproj/ · .build/ · DerivedData/ · SentrySOC/Info.plist  [C2]
  project.yml         the XcodeGen spec (full text in §6)                                   [C6]
  SentryCore/                          ← local Swift Package. ZERO remote deps → no
    Package.swift                        Package.resolved, no network on any build.         [C2]
    Sources/SentryCore/
      Model/     Verdict.swift · Case.swift · Shift.swift · Career.swift · Trace.swift
                 Handler.swift · Tuning.swift · RichText.swift · Lenient.swift              [C2]
      Content/   ContentPack.swift · CopyPack.swift                                          [C2]
      Engine/    Trace.swift · Grading.swift · ShiftOps.swift · Scoring.swift                [C3]
      Career/    CareerOps.swift · Inbox.swift · Templating.swift                            [C4]
      Session/   SessionState.swift · SessionReducer.swift · Effect.swift                    [C5]
      Feel/      SocCue.swift · HapticDSL.swift · HeartbeatPlan.swift · Patterns.swift       [C5]
    Sources/SentryContent/
      SentryContent.swift    6 lines: `public enum SentryContent { public static let bundle = Bundle.module }`
      Resources/content.json · copy.json · daily.json      GENERATED, committed (~290 KB)    [C1]
    Sources/SentryFixtures/                                test-only; never linked by the app (D23)
      SentryFixtures.swift   6 lines, same shape
      Resources/grades.json · grades-synthetic.json · shift-runs.json · trace.json
                career.json · handler.json · scoring.json  GENERATED, committed (~210 KB)    [C1]
    Tests/ContentTests/      decode · schemaVersion · contentHash · integrity · lenient-schema  [C2]
    Tests/EngineTests/       golden grades · synthetic · trace · shift-runs · scoring · tuning  [C3]
    Tests/CareerTests/       golden career · handler inbox                                      [C4]
    Tests/SessionTests/      reducer · effect schedule · heartbeat · haptic patterns            [C5]
  SentrySOC/                           ← the app target
    Info.plist                         GENERATED by XcodeGen; gitignored; never hand-edited
    Sources/
      App/        SentrySOCApp.swift · RootView.swift · PhaseHost.swift                      [C6]
      State/      GameModel.swift · SettingsState.swift · EffectRunner.swift                 [C6]
      Services/   SaveStore.swift · Flags.swift · SafariView.swift · QAJump.swift             [C6]
      Design/     Theme.swift · Typography.swift · Motion.swift · Glyphs.swift                [C6]
      Components/ SystemBar · ECGCanvas · Dock · SheetChrome · MeterView · StatTile · Chip
                  StampView · HoldToFileButton · SourceRow · EvidenceCard · QueueRow
                  InboxCard · RankBadge · CoachBubble · RichTextView · SegmentedTabs          [C7]
      Screens/Play/  ShiftIntroView · CaseView · SourceSheet · EvidenceBoard · CallSheet
                     DebriefView · BoardSheet · AbandonSheet                                  [C8]
      Screens/Meta/  HubView · ShiftSummaryView · RankUpView · SettingsView · FirstRunView
                     KitSheet · LicensesView                                                  [C9]
      Haptics/    HapticsEngine.swift · CHPatterns.swift · HeartbeatPlayer.swift              [C10]
    Resources/
      Assets.xcassets/   AppIcon · AccentColor · LaunchGround · LaunchMark                    [C6]
      IBMPlexMono-{Regular,Medium,SemiBold}.ttf                                               [C6]
      SpaceGrotesk-{Regular,Medium,SemiBold}.ttf                                              [C6]
      OFL-IBMPlex.txt · OFL-SpaceGrotesk.txt                                                  [C6]
    Tests/      FontRegistrationTests · SaveStoreTests · EffectScheduleTests                  [C6]
  scripts/      build.sh · shots.sh · verify.sh · appicon.swift                              [C11]

Makefile                                                                                     [C11]
.github/workflows/ios.yml                                                                    [C11]
docs/IOS-BUILD.md · docs/APPSTORE.md · docs/screenshots/ios/**                               [C11]
```

**Fonts.** Static instances only — never the variable TTF (ambiguous `UIAppFonts` registration) and
never the npm Fontsource packages (woff/woff2 only; iOS cannot register them, and both entries come
out of `package.json` in C1). `IBMPlexMono-*.ttf` from the IBM/plex GitHub release; `SpaceGrotesk-*.ttf`
from `floriankarsten/space-grotesk`, `fonts/ttf/`. Both OFL — `OFL-IBMPlex.txt` and
`OFL-SpaceGrotesk.txt` are committed beside them and rendered in Settings → Licences. `docs/IOS-BUILD.md`
pins the exact URLs and a SHA256 per file; `verify.sh` fails if a `.ttf` has no OFL text.

**Why `SentryContent` and `SentryFixtures` are separate SPM targets:** every generated artefact then
lives in a directory owned solely by C1, physically disjoint from the hand-written engine (C3/C4/C5),
and the 210 KB of fixtures is depended on only by test targets, so it never ships. Verified working
on `.../scratchpad/probe`.

---

## 2 · Content export

### 2.1 The script

`scripts/export-soc-content.ts` is a thin CLI; all logic is in `app/lib/soc/exporter/`. Run:

```bash
npx tsx --tsconfig tsconfig.json scripts/export-soc-content.ts \
  --out      ios/SentryCore/Sources/SentryContent/Resources \
  --fixtures ios/SentryCore/Sources/SentryFixtures/Resources
```

`npm run soc:export`. **Verified:** the `@/*` alias resolves under tsx 4.23.13 without extra config;
I ran probes that imported `cases.ts`, `engine.ts`, `state.ts` and got `cases 24 shifts 5
uniqueSources 26`.

It imports the real modules — no re-implementation, no copy-paste:

| module | what the exporter takes |
|---|---|
| `cases.ts` | `SOC_CASES` (24, incl. `HANDOFF_CASES`), `SOC_CASES_BY_ID`, `SHIFTS`, the four id lists |
| `handoff.ts` | evaluated transitively — `caseFromRedRun` runs **here**, at export time |
| `engine.ts` | `gradeCall` · `applyCall` · `buildCaseResult` · `scoreShift` · `assembleShift` · `overallShiftStatus` |
| `career/state.ts` | `RANKS` · `KIT` · `INITIAL_CAREER` · `awardForShift` · `rankFor` · `nextRank` · `isUnlocked` · `buyKit` · `awardRedRun` |
| `career/handler.ts` | `inboxFor` |
| `game/trace.ts` | `getTraceStatus` · `clampLevel` |
| `types.ts` | `DISPOSITIONS` (order is load-bearing — it is the button order) · `verdictOf` |

**`caseFromRedRun`, `TRADECRAFT_SIGNAL` and `resolvePrimary` are NEVER ported to Swift.**
`HANDOFF_CASES` is already `RED_RUNS.map(...)` at module load, so the three generated cases are
exported as ordinary literal data. That deletes ~270 lines of generator logic from the parity surface
at zero cost, because the generator is pure.

**Canonical serialisation** (`canonical.ts`): recursive key sort, 2-space indent, LF, one trailing
newline, raw UTF-8 with no `\u` escaping and no BOM, `JSON.stringify` default number formatting, and
**no timestamp and no git SHA anywhere** — they would break byte-equality. Numbers are therefore JS
shortest-round-trip IEEE-754 doubles; I verified on the probe package that Swift's `JSONDecoder`
reconstructs `0.8571428571428571` as exactly `6.0/7.0`, so Swift asserts `==`.

### 2.2 Output schema — `app/lib/soc/exporter/schema.ts` (frozen in hour 1)

```ts
export const CONTENT_SCHEMA_VERSION = 1;

/** Colour-run text. Rendered as AttributedString in SwiftUI. (D5) */
export type Tone = "cyan" | "emerald" | "rose" | "amber" | "fuchsia" | "strong" | "em" | "muted";
export interface RichSegment { text: string; tone?: Tone }

export type OutcomeKey =
  | "tp.missed" | "tp.escalated-correct" | "tp.over-contained" | "tp.under-contained"
  | "fp.closed-fp" | "fp.closed-as-benign" | "fp.escalated"
  | "btp.closed-benign" | "btp.closed-as-fp" | "btp.escalated-t2" | "btp.isolated";

export interface ExportedSource   { id: string; label: string; question: string; cost: number }
export interface ExportedEvidence {
  id: string; sourceId: string; label: string; detail: string;
  weight: "decisive" | "supporting" | "neutral" | "noise";
}
export interface ExportedLearn {
  concept: string; mitreId: string | null; mitreName: string | null; pointer: string | null;
}
export interface ExportedCase {
  id: string;
  archetype: string;                       // lenient in Swift (D10)
  alertTitle: string; detectionRule: string;
  toolSeverity: string;                    // lenient in Swift
  trigger: string; asset: string;
  sourceIds: string[];                     // → the top-level catalogue; 135 inline objects → 26 (D3)
  keySourceIds: string[];
  evidence: ExportedEvidence[];
  truth: "true-positive" | "false-positive" | "benign-true-positive";
  correctDisposition: string;
  acceptableDispositions: string[];        // [] never undefined → non-optional in Swift
  why: string;
  learn: ExportedLearn;
  handoff: { fromRun: string; operator: string } | null;   // null, never omitted
}
export interface ExportedShift {
  id: string; label: string; caseIds: string[];
  unlockStanding: number; requiresRedRun: boolean;
  note: string | null; kind: "campaign" | "daily";
}
export interface ExportedTuning {
  trace:  { min: 0; max: 100; alert: 25; hunt: 50; lockdown: 80 };
  bpm:    { CALM: 50; ALERT: 76; HUNT: 112; LOCKDOWN: 150 };
  timeBudgetDefault: 90;
  grade:  {
    tpMissedBreach: 30; tpUnderContainBreach: 10; tpOverContainNoise: 12;
    fpEscalateT2Noise: 12; fpEscalateIsolateNoise: 20;
    btpClosedAsFpNoise: 4; btpEscalateT2Noise: 14; btpIsolateNoise: 24;
  };
  shift:  { cleanAccuracy: 0.8; breachedMissedDetections: 2 };
  career: { cashPerCorrect: 50; cleanBonus: 150; standingClean: 40; standingRough: 15;
            standingBreached: 5; redRunCut: 150 };
  heartbeat: { minPeriodMs: 400; autoSuspendMs: 40000; dubOffsetMs: 120 };
}
export interface ExportedBundle {
  schemaVersion: number;
  contentHash: string;                     // "sha256:<hex>" over the canonical JSON of everything else
  dispositions: string[];                  // DISPOSITIONS order — the button order
  sources: ExportedSource[];               // 26
  cases:   ExportedCase[];                 // 24, incl. the 3 handoff cases
  shifts:  ExportedShift[];                // 5, blue-only ladder applied (D4)
  ranks:   { id: string; label: string; min: number }[];       // 4
  kit:     { id: string; label: string; cost: number; blurb: string }[];  // 1
  tuning:  ExportedTuning;
}

export interface ExportedCopy {
  schemaVersion: number; contentHash: string;
  verdictLabels: Record<string, string>;
  dispositionMeta: Record<string, { label: string; sub: string; tone: Tone }>;
  outcomes: Record<OutcomeKey, string>;                       // 11 (D12)
  debriefHeadlines: { good: string; verdictOnly: string; wrong: string };
  gradeMeta: Record<"clean" | "rough" | "breached", { label: string; line: string; tone: Tone }>;
  intro: {
    eyebrow: string; title: string;                           // "{n} alerts on the board."
    taxonomy: RichSegment[]; severity: RichSegment[];
    meters: { key: "breach" | "noise" | "time"; label: string; fear: string }[];
    handoff: { blueOnly: RichSegment[]; redSeat: RichSegment[] };
    cta: string; disclaimer: string;
  };
  coachSteps: { anchor: "sources" | "evidence" | "call"; title: string; body: string; button: string | null }[];
  ladder: { eyebrow: string; body: RichSegment[]; note: string };
  summary: { eyebrow: string; investigationLine: string; blindLine: string };
  firstRun: { title: string; body: string; cta: string };
  about: { fiction: string; privacy: string; promise: string; credits: string };
  meters: Record<"breach" | "noise" | "time", { label: string; fear: string }>;
  handler: {
    senders: Record<"vale" | "mercer", { from: string; role: string }>;
    templates: Record<string, { subject: string; body: string; tone: string }>;  // {gap} {rank} {cash} {item} {queue}
  };
}

export interface ExportedDaily {
  schemaVersion: number; contentHash: string;
  horizonStart: string;                                       // "2026-09-05"
  days: { date: string; caseIds: string[] }[];                // 730 (D6)
}

/* ── fixtures ─────────────────────────────────────────────────────────── */
export interface GradeRow {
  caseId: string; disposition: string;
  verdictCorrect: boolean; dispositionCorrect: boolean; exact: boolean;
  breachDelta: number; noiseDelta: number;
  outcomeKey: OutcomeKey; outcome: string;
}
export interface SyntheticGradeFile { cases: ExportedCase[]; rows: GradeRow[] }   // 3 × 4 = 12 (D11)
export interface ShiftStateSnapshot {
  index: number; breachRisk: number; noise: number; timeUsed: number;
  results: { caseId: string; chosen: string; verdictCorrect: boolean; dispositionCorrect: boolean;
             queriedSourceIds: string[]; keySourcesPulled: number; timeSpent: number }[];  // ORDERED (D8)
  overallStatus: string;
}
export interface ShiftRun {
  name: string; shiftId: string; caseIds: string[];
  careerBefore: CareerJSON;
  steps: { caseId: string; chosen: string; queriedSourceIds: string[]; timeSpent: number;
           after: ShiftStateSnapshot }[];
  score: ShiftScoreJSON; reward: ShiftRewardJSON;
  unlockedBefore: string[]; unlockedAfter: string[];
  event: HandlerEventJSON; inbox: HandlerMessageJSON[];
}
```

### 2.3 The three safety mechanisms

**(a) `outcomeKey` without touching `engine.ts` (D2).** `deriveOutcomeKey` re-implements the branch
shape; the export asserts `gradeCall(c,d).outcome === COPY.outcomes[deriveOutcomeKey(c,d)]` for all
96 pairs and aborts naming the pair on any mismatch. Swift then compares a keyed enum.

**(b) The dead branch (D11).** `grades-synthetic.json` carries **three constructed `SocCase`
objects inline** — a TP with `acceptableDispositions: []` and `correctDisposition: escalate-ir-isolate`
(reaches `tp.under-contained`), a TP with only `escalate-ir-isolate` acceptable, and a Benign-TP with
an empty acceptables list — × 4 dispositions = 12 rows. Together with the 96 real rows this reaches
all **11** `OutcomeKey`s and all **12** branch arms. Without it, a Swift transcription bug in the
`breachDelta = 10` arm ships undetected and detonates the first time a TP is authored without
acceptables.

**(c) SHA-pinned source slices (D4, D5).** `sourcePins.ts` holds
`{ file, startAnchor, endAnchor, sha256, purpose }` for every region of the web tree that the
exporter hand-transcribes: the briefing taxonomy JSX, `DISPOSITION_META`, `VERDICT_LABEL`, the
debrief headline ternary, `gradeMeta`, `SocOnboarding`'s `STEPS`, `handler.ts`'s message bodies, and
the five §3.2 strings in `handoff.ts` / `cases.ts`. The export slices between the anchors, hashes,
and aborts with `stale pin: SocConsole.tsx#taxonomy` on any change. A human then re-transcribes and
re-pins — the only place drift can enter, and it is loud.

### 2.4 Fixture set (7 files, all carrying the same `contentHash`)

| file | contents |
|---|---|
| `grades.json` | **96** rows = 24 cases × 4 dispositions, every `CallGrade` field + `outcomeKey` + `outcome` |
| `grades-synthetic.json` | 3 inline synthetic cases × 4 = **12** rows; reaches all 11 keys (D11) |
| `shift-runs.json` | **7** scripted runs — Shift 1 clean, Shift 1 `?demo=complete` (verbatim from `SocConsole.tsx:157-176`, pinned per D13), Shift 1 breached (2 missed TPs), one each for Shifts 2–5. Every run carries per-step `ShiftStateSnapshot` + `overallStatus`, then `ShiftScore`, `ShiftReward`, career before/after, the unlock diff and the `HandlerEvent`. |
| `trace.json` | `getTraceStatus` at −1/0/24/25/49/50/79/80/100/101 and every level −5…105; `clampLevel` at −5/−1/0/50/100/101/150 |
| `career.json` | a 12-award ladder walk: after each award `{state, rank, nextRank, unlockedIds[]}`; plus `awardRedRun` and three `buyKit` rows (afford / unafford / already-owned) |
| `handler.json` | **14** `(CareerState, HandlerEvent, features)` triples → full message arrays (id, from, role, tone, subject, rendered body): welcome, clean, rough, breached, rankUp at each of the 4 ranks, unlock(handoff-shift), tip-kit, tip-redrun (blue-only: **suppressed**), the standing ≥ 90 nudge, and the 4-message cap |
| `scoring.json` | 5 hand-built edge shifts the corpus runs never reach: empty shift · all-blind · exactly 2 missed detections · noise pushed to HUNT with perfect accuracy · `breachRisk` at exactly 80 |

Rates carry their numerator and denominator alongside the `Double`, so a Swift failure localises to
the counter rather than printing two long decimals.

### 2.5 Drift guard — `app/lib/soc/exporter/drift.test.ts`

Runs inside the existing `npm test` (vitest `include: ["app/**/*.test.ts"]`, verified — this is why
the file lives under `app/` and not `scripts/`).

1. Re-runs the exporter **in memory** and asserts **byte equality** with each of the 10 committed
   JSON files.
2. Asserts `contentHash` is identical across `content.json`, `copy.json`, `daily.json` and all 7
   fixtures.
3. Asserts `grades.json` has exactly `SOC_CASES.length * DISPOSITIONS.length` = 96 rows.
4. Asserts every one of the 11 `OutcomeKey`s appears at least once across `grades.json` **∪**
   `grades-synthetic.json` — if someone adds a 12th branch and no fixture reaches it, this fails and
   demands a fixture.
5. Asserts every `breachDelta`/`noiseDelta` in every fixture is an integer (protects Swift's `Int`
   meters).
6. Asserts every `case.sourceIds` and `case.keySourceIds` resolves in the 26-source catalogue, and
   every `evidence.sourceId` resolves within its case.
7. **Credibility guardrail on the artefact:** no match for
   `/\$\s?\d|salary|salaries|per year|\bpay\b\s*(range|band)|USD|EUR|PLN/i` anywhere in the exported
   bundle or copy. This is stronger than grepping the source, because it covers the exported text.
8. Every `sourcePins.ts` SHA still matches (D5), and the 96-pair `outcomeKey ↔ prose` assertion holds.
9. `git diff --exit-code -- app/lib/soc app/lib/career app/lib/game app/components/soc` is clean (D1).

The exporter also prints a `diffSummary` to stdout — `3 grade rows changed: soc-ps-patch/escalate-tier2
noiseDelta 0→12` — which the PR template requires pasting. That is the answer to "regenerating
fixtures blesses a mistake": a silent regeneration is visible in review, and the existing
property-based suites (`engine.test.ts`, `cases.test.ts`, `taxonomy.test.ts`, `state.test.ts`) remain
the semantic backstop a snapshot cannot provide.

`npm run soc:check` = `soc:export --check` (exports to a temp dir and diffs) for use in CI without
writing.

---

## 3 · Swift engine — `ios/SentryCore`

### 3.1 Package

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SentryCore",
  platforms: [.iOS(.v18), .macOS(.v14)],          // macOS so the parity gate needs no simulator
  products: [.library(name: "SentryCore", targets: ["SentryCore"])],
  targets: [
    .target(name: "SentryContent",  resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    .target(name: "SentryFixtures", resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),          // test-only (D23)
    .target(name: "SentryCore", dependencies: ["SentryContent"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "ContentTests", dependencies: ["SentryCore", "SentryFixtures"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "EngineTests",  dependencies: ["SentryCore", "SentryFixtures"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "CareerTests",  dependencies: ["SentryCore", "SentryFixtures"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "SessionTests", dependencies: ["SentryCore", "SentryFixtures"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
  ]
)
```

All eight targets are declared on day one by C2, so **no other ticket ever edits `Package.swift`**.
Zero remote dependencies → no `Package.resolved`, no network on any build. `SentryCore` imports
Foundation only (D15).

### 3.2 Module map — mirrors the TypeScript file-for-file

| TypeScript | Swift | contents |
|---|---|---|
| `types.ts` | `Model/Verdict.swift` | `SocVerdict`, `Disposition` (+ `var verdict: SocVerdict`), `InvestigationQuality` — closed `String`-raw enums whose raw values are the TS literals verbatim (`case escalateIRIsolate = "escalate-ir-isolate"`); `Disposition` is `CaseIterable` in exported order |
| `types.ts` | `Model/Lenient.swift` | `SocArchetype`, `ToolSeverity`, `EvidenceWeight` — `RawRepresentable<String>` structs with known statics, decode-anything (D10) |
| `types.ts` | `Model/Case.swift` | `DataSource`, `SocEvidence`, `LearnForReal`, `HandoffRef`, `SocCase`, `ShiftDef` |
| `types.ts`+`engine.ts` | `Model/Shift.swift` | `CaseResult`, `ShiftState`, `ShiftGrade`, `ShiftScore`, `CallGrade`, `OutcomeKey` (11, closed) |
| `career/state.ts` | `Model/Career.swift` | `CareerState`, `Rank`, `KitItem`, `ShiftReward`, `SocFeatures` |
| `game/trace.ts` | `Model/Trace.swift` | `TraceStatus: String, Comparable` — ordered CALM<ALERT<HUNT<LOCKDOWN, which **replaces the rank dictionary** in `overallShiftStatus` |
| `career/handler.ts` | `Model/Handler.swift` | `HandlerMessage`, `HandlerEvent`, `HandlerTone` |
| — | `Model/Tuning.swift`, `Model/RichText.swift` | `Tuning` (D7), `RichSegment`/`Tone` |
| `cases.ts` (data) | `Content/ContentPack.swift` | decodes `content.json` + `daily.json`; builds `casesByID`, `sourcesByID`, `shiftsByID`; expands `sourceIds → [DataSource]` |
| copy | `Content/CopyPack.swift` | decodes `copy.json`; `outcomeText(_:)`; `render(_ template:_ params:)` |
| `engine.ts` | `Engine/Grading.swift` | `gradeCall`, `outcomeKey`, `isEscalate` |
| `engine.ts` | `Engine/ShiftOps.swift` | `assembleShift`, `buildCaseResult`, `applyCall`, `shiftComplete`, `overallShiftStatus` |
| `engine.ts` | `Engine/Scoring.swift` | `investigationOf`, `scoreShift` |
| `game/trace.ts` | `Engine/Trace.swift` | `status(_:)`, `clamp(_:)` |
| `career/state.ts` | `Career/CareerOps.swift` | `rankFor`, `nextRank`, `owns`, `buyKit`, `awardForShift`, `awardRedRun`, `isUnlocked` |
| `career/handler.ts` | `Career/Inbox.swift` + `Templating.swift` | `inboxFor` + named-placeholder interpolation, `.prefix(4)` cap |
| **new** (D9) | `Session/*` | `SessionState`, `SocAction` (17), `Effect`, `reduce` |
| **new** | `Feel/*` | `SocCue` (15), `HapticPattern` value types, `heartbeatPlan`, the 4 bespoke patterns |

### 3.3 Signatures

```swift
// Content
public struct ContentPack: Sendable {
  public static let bundled: ContentPack                      // static let of a Sendable struct
  public let schemaVersion: Int, contentHash: String
  public let sources: [DataSource], cases: [SocCase], shifts: [ShiftDef]
  public let ranks: [Rank], kit: [KitItem], tuning: Tuning, copy: CopyPack
  public let daily: DailyCalendar
  public func `case`(_ id: String) -> SocCase?
  public func shift(_ id: String) -> ShiftDef?
  public func dailyShift(on date: Date, calendar: Calendar = .current) -> ShiftDef   // wraps mod days (D6)
}

// Engine — constructed once from the bundle; no numeric literal anywhere in Engine/ (D7)
public struct SOCEngine: Sendable {
  public init(content: ContentPack)
  public func gradeCall(_ c: SocCase, _ chosen: Disposition) -> CallGrade
  public func outcomeKey(_ c: SocCase, _ chosen: Disposition) -> OutcomeKey
  public func outcomeText(_ key: OutcomeKey) -> String
  public func assembleShift(_ shiftId: String, _ caseIds: [String], timeBudget: Int? = nil) -> ShiftState
  public func buildCaseResult(_ c: SocCase, _ chosen: Disposition,
                              queriedSourceIds: [String], timeSpent: Int) -> CaseResult
  public func applyCall(_ shift: ShiftState, _ c: SocCase, _ chosen: Disposition,
                        queriedSourceIds: [String], timeSpent: Int) -> ShiftState
  public func shiftComplete(_ shift: ShiftState) -> Bool
  public func overallShiftStatus(_ shift: ShiftState) -> TraceStatus
  public func investigationOf(_ r: CaseResult, _ c: SocCase) -> InvestigationQuality
  public func scoreShift(_ shift: ShiftState) -> ShiftScore
}

public enum Trace {
  public static func status(_ level: Int, _ t: Tuning) -> TraceStatus
  public static func clamp(_ level: Int, _ t: Tuning) -> Int
}

public struct CallGrade: Codable, Sendable, Hashable {
  public let verdictCorrect: Bool, dispositionCorrect: Bool, exact: Bool
  public let breachDelta: Int, noiseDelta: Int
  public let outcomeKey: OutcomeKey            // prose is resolved via SOCEngine.outcomeText (D2/D12)
}

// DV-1: ordered results; meters settable only inside SentryCore (D8)
public struct ShiftState: Codable, Sendable, Hashable {
  public let shiftId: String, caseIds: [String], timeBudget: Int
  public internal(set) var index: Int
  public internal(set) var results: [CaseResult]
  public internal(set) var breachRisk: Int, noise: Int, timeUsed: Int
  public func result(for caseId: String) -> CaseResult?
}

// Career
public struct CareerRules: Sendable {
  public init(content: ContentPack)
  public func rankFor(_ standing: Int) -> Rank
  public func nextRank(_ standing: Int) -> Rank?
  public func owns(_ c: CareerState, _ gearId: String) -> Bool
  public func buyKit(_ c: CareerState, _ item: KitItem) -> CareerState
  public func awardForShift(_ c: CareerState, _ score: ShiftScore) -> ShiftReward
  public func awardRedRun(_ c: CareerState, cut: Int? = nil) -> CareerState
  public func isUnlocked(_ c: CareerState, _ shift: ShiftDef) -> Bool
}
public struct HandlerVoice: Sendable {
  public init(content: ContentPack)
  public func inboxFor(_ c: CareerState, _ ev: HandlerEvent = .init(),
                       features: SocFeatures = .iOS) -> [HandlerMessage]     // .iOS = redSeat:false
}

// Session (D9) — pure, NOT parity-guarded
public enum Phase: Codable, Sendable, Hashable {
  case hub, briefing, investigating, debrief(readOnly: Bool), complete, milestone
}
public enum ViewID: Identifiable, Codable, Sendable, Hashable {
  case board, source(String), call, kit, settings, abandon, firstRun
}
public enum SocAction: Sendable {                                   // 17, per addendum §C
  case hydrate, startShift(String), begin, resume
  case openView(ViewID), closeView, pullSource(String)
  case pickDisposition(Disposition), makeCall(Disposition), nextCase
  case viewResult(String), ackMilestone, ackFirstRun, toHub, abandon
  case buy(String), setSetting(SettingKey, Bool)
}
public enum Effect: Equatable, Sendable {
  case haptic(SocCue), persistSession, clearSession, settleShift
  case persistCareer, setFlag(String, Bool), markDailyDone(String)
}
public func reduce(_ s: SessionState, _ a: SocAction,
                   content: ContentPack, career: CareerState) -> (SessionState, [Effect])

// Feel — Foundation only, so it stays in the macOS `swift test` build
public func heartbeatPlan(status: TraceStatus, tuning: Tuning) -> HeartbeatPlan?
public enum CHPatternSpec {                                          // pure descriptions (D17)
  public static func heartbeat(_ status: TraceStatus, _ t: Tuning) -> HapticPattern?
  public static let file: HapticPattern, breachThud: HapticPattern, rankup: HapticPattern
}
```

### 3.4 Codable mapping

Every enum's `rawValue` **is** the TS string, so `Codable` synthesis needs no `CodingKeys`; every
struct uses synthesised `Codable` against the exported field names 1:1 — the schema in §2.2 was
designed to make that true (`sourceIds` flat, `learn.mitreId/mitreName` flattened,
`acceptableDispositions` never absent, `handoff: null` never omitted). Adding a field to the TS
export therefore costs **zero Swift** until Swift wants it.

`ContentPack.bundled` is a `static let` of a `Sendable` struct — thread-safe via `swift_once`,
verified compiling under `.swiftLanguageMode(.v6)` on the probe. A decode failure is a programmer
error and `fatalError`s with the underlying `DecodingError`; `ContentTests` makes that unreachable in
a shipped build.

### 3.5 Documented divergences from the TypeScript

- **DV-1** `ShiftState.results` is ordered (D8). The exporter serialises fixture results in insertion
  order to match.
- **DV-2** Meters are `public internal(set)` (D8). Access control, not convention.
- **DV-3** `TraceStatus` is `Comparable`, so `overallShiftStatus` is `max(a, b)` instead of the TS
  rank dictionary. Pinned by `trace.json` and by every `shift-runs.json` step's `overallStatus`.
- **DV-4** `rankFor` is a literal ascending last-match loop and `nextRank` a literal
  `first(where: { $0.min > standing })` — **ported as written, not as intended**, so an unsorted
  `RANKS` array would behave identically on both sides. A test proves it on a deliberately
  out-of-order array.
- **DV-5** The session reducer has no TS counterpart and is not fixture-guarded (D9).

### 3.6 Parity tests (Swift Testing, `@Test(arguments:)` so each row is a named result)

```swift
@Test("gradeCall matches the TypeScript engine", arguments: try Golden.grades())
func gradeParity(_ row: GradeRow) throws {
  let c = try #require(ContentPack.bundled.case(row.caseId))
  let g = engine.gradeCall(c, row.disposition)
  #expect(g.verdictCorrect     == row.verdictCorrect)
  #expect(g.dispositionCorrect == row.dispositionCorrect)
  #expect(g.exact              == row.exact)
  #expect(g.breachDelta        == row.breachDelta)
  #expect(g.noiseDelta         == row.noiseDelta)
  #expect(g.outcomeKey         == row.outcomeKey)
  #expect(engine.outcomeText(g.outcomeKey) == row.outcome)
}
```

| suite | coverage |
|---|---|
| `EngineTests/GoldenGradeTests` | 96 parameterised rows, every field compared with exact `==`; failure names caseId + disposition |
| `EngineTests/SyntheticGradeTests` | the 12 synthetic rows; reaches all 11 keys and all 12 arms (D11) |
| `EngineTests/GoldenTraceTests` | 111 status rows + clamp edges |
| `EngineTests/GoldenShiftRunTests` | the 7 runs, asserting `ShiftState` after **every step** (not just the end), then `ShiftScore` field-by-field |
| `EngineTests/GoldenScoringTests` | the 5 edge shifts |
| `EngineTests/TuningExpectationTests` | the 14 tuning numbers against a hardcoded table in the *test* target (D7) |
| `CareerTests/GoldenCareerTests` | the 12-award sequence + rank/nextRank/unlock diff + 3 `buyKit` rows + `awardRedRun`; plus the DV-4 unsorted-ranks test |
| `CareerTests/GoldenInboxTests` | all 14 scenarios; message **ids AND rendered bodies**; the blue-only suppression of `tip-redrun`; the 4-message cap |
| `ContentTests/IntegrityTests` | `schemaVersion == 1`; `contentHash` identical across all 10 files; per case: `sourceIds` non-empty, `keySourceIds ⊆ sourceIds`, every `evidence.sourceId ∈ sourceIds`, `verdictOf(correctDisposition) == truth`, `acceptableDispositions ∌ correctDisposition`; every `shift.caseIds` resolves; every campaign shift covers all three verdicts; the two known-long fields have their exact character counts (`soc-insider-departing.why` = 559, `soc-handoff-unsanctioned.why` = 566) so a re-encode breaks |
| `ContentTests/LenientSchemaTests` | decodes a synthetic bundle carrying `archetype: "lateral-movement"`, `toolSeverity: "Informational"`, `weight: "circumstantial"`, an extra top-level key and an extra per-case key — asserts it loads **and grades correctly**; a companion asserts an unknown `outcomeKey` **fails** to decode (D10) |
| `SessionTests/ReducerTests` | all 17 actions; the `MAKE_CALL` re-entrancy guard (`phase == .investigating`); the `OPEN_VIEW(.call)` revealed-evidence guard; `VIEW_RESULT`'s `caseId ∈ results` guard and its return to the originating phase |
| `SessionTests/EffectScheduleTests` | one `MAKE_CALL` emits exactly one `.haptic`; settle order is `settleShift → persistCareer → clearSession` |
| `SessionTests/HeartbeatTests` | nil at CALM/ALERT; `60000/112` and `60000/150`; the 400 ms floor; the 120 ms dub offset; the 40 s suspend and its re-arm |
| `SessionTests/HapticPatternTests` | exact event times, intensities and parameter-curve control points for heartbeat/file/breachThud/rankup — **the only pre-device verification that exists**, because the Simulator has no haptics |

---

## 4 · App — `ios/SentrySOC`

### 4.1 State container

```swift
@Observable @MainActor final class GameModel {
  let content: ContentPack
  let engine:  SOCEngine
  let rules:   CareerRules
  let voice:   HandlerVoice
  private(set) var session: SessionState
  private(set) var career:  CareerState
  private(set) var inbox:   [HandlerMessage]
  var settings: SettingsState              // haptics · holdToFile · coaching
  private let save: SaveStore              // actor
  private let haptics: HapticsEngine

  func send(_ action: SocAction) {
    let (next, effects) = reduce(session, action, content: content, career: career)
    withAnimation(Motion.gated(.smooth(duration: 0.26, extraBounce: 0))) { session = next }
    for e in effects { run(e) }             // EffectRunner is the ONLY interpreter
  }
}
```

Views never construct a `CallGrade`, never touch a meter (D8 makes it a compile error) and never
touch storage or Core Haptics. `settleShift` runs the exact web settlement chain —
`scoreShift → awardForShift → unlock diff → HandlerEvent → persistCareer → clearSession` — and, per
addendum §G7, stamps `career.dailyDoneOn` and suppresses the *standing* award (cash still pays) on a
repeat daily.

### 4.2 Navigation (D16)

- `RootView` → `PhaseHost`: a `ZStack` switching on `session.phase` with
  `.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))`
  animated by `.smooth(duration: 0.26, extraBounce: 0)` — the native form of §2.14's 260 ms
  `cubic-bezier(.2,.8,.2,1)`.
- Overlays: `.sheet(item: $model.session.view)` with
  `.presentationDragIndicator(.visible)`, `.presentationBackground(.clear)` + a hand-painted panel so
  the ground and edge-glow read through, `.presentationCornerRadius(16)`, and per sheet:
  **Board** `[.fraction(0.92)]` · **Source** `[.height(320), .large]` with a bound `selection` so the
  sheet *grows on the pull* (the native form of §2.7's "same sheet, the CTA morphs") ·
  **Call** `[.large]` · **Kit** `[.medium]`.
- `.fullScreenCover` for **FirstRun** (`.interactiveDismissDisabled(true)`) and **RankUp**
  (full-bleed, no SystemBar).
- **Abandon** and **Reset career** are `.confirmationDialog` — the system affordance for destructive
  confirmation, with free VoiceOver and Dynamic Type.
- Every screen mounts its bottom chrome with `.safeAreaInset(edge: .bottom)`, the idiomatic
  replacement for a CSS fixed dock: scroll content gets the correct inset for free, home indicator
  included. The Case screen stacks **two** insets — Coach above Dock — which is why the coach can
  never again overlap the alert header (`PLAYTEST-lookandfeel.md` P2, fixed by construction).

### 4.3 Persistence

| what | where | how |
|---|---|---|
| Career (the save) | `Application Support/SentrySOC/career.json` | Codable + `schemaVersion`; atomic write with a `career.bak.json` rotation before each overwrite; `.completeFileProtectionUnlessOpen`; custom `init(from:)` defaulting every missing key from `CareerState.initial`, mirroring `loadCareer`'s spread so old saves and new fields both load |
| Mid-shift snapshot | `Application Support/SentrySOC/session.json` | written after `PULL_SOURCE`/`MAKE_CALL`, coalesced to ≤1 write per 250 ms, and on `scenePhase == .background`; deleted on settle or abandon |
| Launch-critical flags | `UserDefaults` | `sentry.firstRun.v1`, `sentry.onboarding.v1`, `sentry.haptics`, `sentry.holdToFile`, `sentry.coaching` |

All file I/O goes through `actor SaveStore`; `CareerState`/`SessionState` are `Sendable` value types
so the hop is free. **Hydration is synchronous in `SentrySOCApp.init()` before the first frame**
(a ~4 KB read) — which deletes risk **R6** ("Preferences hydration races React and overwrites a good
save") as a *class*: natively there is no race to lose. Corruption policy: a decode failure renames
the file to `career.corrupt-<epoch>.json`, starts from `INITIAL_CAREER` and sets a one-shot Settings
notice; `saveCareer` never writes `INITIAL_CAREER` except behind the double-confirmed reset.

### 4.4 Haptics (D17, D18)

`@MainActor final class HapticsEngine`: lazy `CHHapticEngine`, `playsHapticsOnly = true`,
`isAutoShutdownEnabled = true`, `resetHandler`/`stoppedHandler` restart it, every call gated on
`CHHapticEngine.capabilitiesForHardware().supportsHaptics` — **false on the Simulator, so it silently
no-ops instead of crashing.**

```swift
func heartbeat(intensity i: Float, sharpness s: Float) throws -> CHHapticPattern {
  let lub = CHHapticEvent(eventType: .hapticContinuous, parameters: [
      .init(parameterID: .hapticIntensity, value: i),
      .init(parameterID: .hapticSharpness, value: s)],
    relativeTime: 0, duration: 0.09)
  let swell = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
      .init(relativeTime: 0.000, value: 0.0),
      .init(relativeTime: 0.018, value: 1.0),   // fast attack — this makes it a THUMP
      .init(relativeTime: 0.090, value: 0.0)],  // and this stops it being a buzz
    relativeTime: 0)
  let dub = CHHapticEvent(eventType: .hapticTransient, parameters: [
      .init(parameterID: .hapticIntensity, value: i * 0.55),
      .init(parameterID: .hapticSharpness, value: max(0, s - 0.10))],
    relativeTime: 0.12)                          // tuning.heartbeat.dubOffsetMs
  return try CHHapticPattern(events: [lub, dub], parameterCurves: [swell])
}
```

Played through one `CHHapticAdvancedPatternPlayer` with `loopEnabled = true` and `loopEnd = period`.
Status changes modulate **live** via
`player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, …)], atTime: .zero)`
rather than rebuilding the pattern.

| status | period | intensity | sharpness |
|---|---|---|---|
| HUNT (112 bpm) | 0.536 s | 0.75 | 0.30 |
| LOCKDOWN (150 bpm) | 0.400 s | 1.00 | 0.55 — *sharper as well as faster; dread, not volume* |

**Cue table — all 15 cues of §2.15.** Twelve route to SwiftUI `.sensoryFeedback(_:trigger:)`
(no engine warm-up, correct behaviour after auto-shutdown); three get bespoke `CHHapticPattern`s
because `.sensoryFeedback` cannot express them.

| §2.15 event | `SocCue` | native |
|---|---|---|
| source tap · disposition pick · queue row · toggle | `select` | `.sensoryFeedback(.selection, trigger:)` |
| hold-to-file ticks at 0 / 180 / 360 ms | `holdTick` | `.selection` |
| a finding lands (max 3 per pull) | `findingLand` | `.impact(weight: .light)` |
| start shift · buy kit · unlock card · payout ends | `commitSoft` | `.impact(flexibility: .solid, intensity: 0.7)` |
| **hold-to-file completes (the stamp)** | `file` | **CH:** transient(0.35, 0.90)@0 → transient(0.45, 0.90)@0.045 → continuous(1.0, 0.25)@0.09 dur 0.14 with a decay curve — *tick-tick-CLUNK* |
| debrief mount — right call | `verdictGood` | `.success` |
| debrief mount — right verdict, off response | `verdictOff` | `.warning` |
| debrief mount — wrong call | `verdictWrong` | `.error` |
| **`grade.breachDelta ≥ 30` as the meter sweeps** | `breachThud` | **CH:** continuous(1.0, 0.15)@0 dur 0.18 + transient(0.8, 0.40)@0.09 — low, sickening, double |
| shift summary clean / rough / breached | `shiftClean/Rough/Breached` | `.success` / `.warning` / `.error` |
| **rank-up beat** | `rankup` | **CH:** 4 events over 700 ms (0/180/420/700) rising in intensity *and* sharpness |
| heartbeat lub + dub | `heartbeat(TraceStatus)` | the looping pattern above |
| locked queue row tap (once per hub visit) | `denied` | `.warning` |
| abandon / reset confirmed | `destructive` | `.error` |

Every pattern is first built by a **pure function in `SentryCore/Feel/`** returning `HapticPattern`
value types; `Haptics/CHPatterns.swift` is a dumb translator to `CHHapticEvent` with no logic. That
is the only way to verify curve timing before a device (`SessionTests/HapticPatternTests`).

Guards, all from the pure `heartbeatPlan`: HUNT/LOCKDOWN only · `phase == .investigating` only ·
400 ms floor · 40 s auto-suspend, re-armed by a status change or `PULL_SOURCE` · stop on
`scenePhase != .active` · Settings toggle. **Silence at CALM/ALERT is the reward.** Reduce Motion
does not disable haptics (D18).

### 4.5 Fonts, Dynamic Type, VoiceOver

`Typography.swift` exposes `Face.mono(_:relativeTo:)` / `Face.grotesk(_:relativeTo:)` over
`Font.custom(_:size:relativeTo:)` so the custom faces scale with Dynamic Type. Root
`.dynamicTypeSize(.xSmall ... .accessibility1)` — a sane clamp, not a refusal to scale. The 11 pt
tracked labels bind `relativeTo: .caption2` with `.minimumScaleFactor(0.9)`; long prose (`why` up to
566 chars, `learn.concept` up to 435) is **never clamped** and always scrolls; `StatTile`s reflow to
one column above `.xxLarge` via `@Environment(\.dynamicTypeSize)`.

A DEBUG launch assertion resolves every family through `UIFont(name:)` and `fatalError`s naming the
missing file — a silent fallback to system-ui (R8) should be loud, not subtle — and
`FontRegistrationTests` asserts the same six faces in CI (D21).

**VoiceOver.** `HoldToFileButton` cannot be held under VoiceOver, so it ships
`.accessibilityAction(named: "File this call")` that commits immediately — the same escape hatch as
the Settings two-tap mode. Source rows read *"\(label). Answers: \(question). Costs \(cost)
shift-minutes."* with `.accessibilityHint("Pulls this log")`; pulled rows add `.isSelected`. Meters
are `.accessibilityValue("\(level) percent, \(status)")` with the fear text as
`.accessibilityHint` — the web's `title=` tooltips become **visible captions** *and* VO hints. The
ECG is `.accessibilityHidden(true)`; the SystemBar exposes one combined element. The debrief stamp is
`.accessibilityLabel("Filed: \(disposition.label)")`.

### 4.6 Tokens and motion

`Design/Theme.swift` — dark-only (`UIUserInterfaceStyle = Dark` in the plist **and**
`.preferredColorScheme(.dark)`, so there is no light flash on launch and no second palette).
Ground `#010409`, panel `#05080c`, scrim `#020408` at 85 %; text `zinc-100/300/400/500` with nothing
meaningful below `zinc-600`; semantic accents **rose** = TP/breach/isolate, **cyan** = FP/neutral/
chrome, **emerald** = Benign-TP/good/primary CTA, **amber** = pressure/Tier-2, **fuchsia** =
crossover/milestone/unlock; `TraceStatus → StatusPalette` for the **CALM cyan** → ALERT amber → HUNT
orange → LOCKDOWN rose ramp with inset-glow opacities .08/.14/.22 (deliberately *not* the red seat's
emerald CALM — design doc §10). Glyphs only — `⬢ ⬡ ¢ ✓ ✗ ▸ ‹ ◉ ◔ ↗` — never emoji, never SF Symbols
in the game chrome (they read as iOS, not as a terminal). Numbers are `.monospacedDigit()`.

`Design/Motion.swift` holds every named `Animation` from §2.14 and **one gate**:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
static func gated(_ a: Animation) -> Animation? { reduceMotion ? nil : a }
```

Every animated view calls through it, so Reduce Motion is correct in exactly one place instead of
thirty. No hardcoded hex or font name may appear outside `Theme.swift`/`Typography.swift` — enforced
by a grep in `ios/scripts/verify.sh`.

---

## 5 · Screens

Wireframes are in `ios-design-spec.md` §2.3–§2.13 **by reference**; only the SwiftUI view names and
the native notes are new.

### 5.1 Hub — "The Desk" (§2.3) · phase `.hub`
`HubView` · `CareerHeader` · `StandingBar` · `ResumeCard` · `InboxCard` · `QueueRow` · `DailyRow` ·
`KitEntryRow` · `Dock` · `SystemBar`

`ScrollView` + `LazyVStack`; the Dock is a `.safeAreaInset(edge: .bottom)` so rows never hide under
it and it never scrolls. Queue rows are 64 pt `Button`s with a custom `ButtonStyle` giving a real
pressed state — the web's `hover:`-only feedback (R11) is structurally absent. Locked rows are
`.disabled(true)` with the reason as **visible text** and an `.accessibilityHint`, never a tooltip; a
tap still fires `denied` once per hub visit. The standing bar animates `.smooth(0.6)` and the number
uses `.contentTransition(.numericText(value:))`. `MeshGradient` ground (iOS 18) instead of a stack of
blurs. Dock label follows the §2.3 rule: `Resume …` / `Clock in · <next open>` / `Daily shift · …`.
SystemBar in hub mode has no ECG.

### 5.2 Shift intro — handover 08:00 (§2.4) · phase `.briefing`
`ShiftIntroView` · `TaxonomyPanel` · `RichTextView` · `HandoffPanel` · `DisclaimerFooter` · `Dock`

Every string from `CopyPack.intro`, including the post-taxonomy-fix DEF-A wording. The three-verdict
block renders `copy.intro.taxonomy` through `RichTextView`, which folds `RichSegment[]` into one
`AttributedString` with per-run `foregroundColor` (D5) — 3 pt rose/cyan/emerald rules on the rows.
`HandoffPanel` selects `.handoff.blueOnly` (iOS `features.redSeat == false`) and swaps the accent to
fuchsia through an `EnvironmentValue` rather than branching in every modifier. The back control is a
44 pt top-left `Button` dispatching `TO_HUB` — legal *only here*, because nothing is committed yet —
and is deliberately **not** a NavigationStack back, so it cannot appear anywhere else by accident.
The disclaimer sits under the Dock CTA at 11 pt, always visible.

### 5.3 Board sheet — queue + pressure (§2.5)
`BoardSheet` · `QueueList` · `QueueStateRow` · `MeterView` · `AbandonSheet`

`.presentationDetents([.fraction(0.92)])` — swipe-to-dismiss is free. Auto-opens exactly once, on the
first case of a shift (`BEGIN` sets it), then never unless asked. Upcoming rows show `alertTitle`
**only** — no severity chip, because the tool's severity is a guess and showing it primes the read.
Done rows dispatch `VIEW_RESULT(caseId)` → read-only debrief (addendum G5). The two `fear` strings
that are `title=` tooltips on the web become visible 11 pt captions **and** VoiceOver hints. Abandon
is a 13 pt text button placed deliberately **outside** the thumb arc behind a `.confirmationDialog`.
§2.17's `lg:` left-rail variant is dropped — iPhone-only.

### 5.4 Case — the read (§2.6) · phase `.investigating`
`CaseView` · `CollapsingCaseHeader` · `SeverityChip` · `SegmentedTabs` · `SourceRow` · `CoachBubble` · `Dock`

Header collapse driven by iOS 18's `.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y }`
→ a `headerCollapsed` Bool animated `.snappy(0.22)` — no GeometryReader preference-key plumbing.
Custom two-button `SegmentedTabs` (a `.segmented` `Picker` cannot carry the live `3/6` and `3` badges).
Source rows are 72 pt: label 15 pt mono, cost 13 pt tabular-trailing, question 13 pt Grotesk italic,
**never truncated**. `asset` gets `.lineLimit(nil)` + `allowsTightening` for
`soc-phish-harvest`'s 33-char unbreakable sender token. **Two stacked `.safeAreaInset(edge: .bottom)`
— Coach above Dock.** Dock CTA is 40 % opacity and disabled until revealed evidence exists.

### 5.5 Source sheet — the commit (§2.7)
`SourceSheet` · `CostPreviewBar` · `QueryProgress` · `EvidenceCard`

`.presentationDetents([.height(320), .large], selection: $detent)`: the sheet **grows to `.large` when
the pull lands** — the native form of "same sheet, the CTA morphs". The `+cost` preview is a second
overlaid `Capsule` at 40 % before commit. 600 ms `QueryProgress`, then findings enter
`.transition(.move(edge: .bottom).combined(with: .opacity))` staggered 45 ms via
`Motion.gated(.smooth.delay(Double(i) * 0.045))`, each firing `findingLand` (capped at 3).
`evidence.detail` is never truncated — it is the puzzle. Pulled sources stay listed and inert.

### 5.6 Evidence board (§2.8) — the EVIDENCE tab of `CaseView`
`EvidenceBoard` · `SourceGroupHeader` · `EvidenceCard` · `EvidenceEmptyState`

Not a separate phase — a tab inside `CaseView`, so header, Dock and haptic context are shared.
`LazyVStack` grouped by pull order under `FROM <source>` headers; tapping a header uses
`ScrollViewReader.scrollTo` to jump back to that row in SOURCES. **`decisive`, `supporting`, `neutral`
and `noise` render identically during play** — weight is a debrief reveal only, which is the
anti-recognition mechanic given a 24-case corpus, and exactly why `EvidenceWeight` is lenient in the
Kit (D10). Empty state is the dashed *"You can't make the call blind."* card.

### 5.7 Call sheet — hold to file (§2.9)
`CallSheet` · `DispositionRow` · `HoldToFileButton` · `KeepInvestigatingLink`

Four 68 pt `DispositionRow`s built from `copy.dispositionMeta` in the exported `dispositions` order —
the taxonomy subtitles are **data**, so the FP/Benign-TP fix propagates with no Swift edit. Selection
= 8 % fill + 1 px ring; others dim to 55 %. `HoldToFileButton`: `DragGesture(minimumDistance: 0)`
records `pressStartedAt` and a `TimelineView(.animation)` reads the `Date` delta, so the conic ring is
driven by a **real clock** and never fights `withAnimation`; ring =
`Circle().trim(from: 0, to: progress).stroke(AngularGradient(…), StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))`.
550 ms; ticks at 0/180/360 ms; release early cancels with **zero** state change; 64 pt target. Reduce
Motion → the ring fills in 3 discrete steps. Settings "Hold to file: off" → two-tap `File ▸` /
`Confirm`. One `MAKE_CALL` per case is guaranteed by the **reducer** guard, not the UI.

### 5.8 Debrief — the hero screen (§2.10) · phase `.debrief`
`DebriefView` · `VerdictTintOverlay` · `StampView` · `MeterView` · `DecisiveFindingsList` ·
`CoverageLine` · `LearnDisclosure` · `Dock`

Entry sequence ~1.1 s as a `@State stage` enum: stamp lands
(`.spring(response: 0.18, dampingFraction: 0.62)`, scale 1.4 → 1, rotation −3°) → outcome fades →
meters sweep. A transparent `.onTapGesture` jumps `stage` to `.done` — tap anywhere to skip.
`MeterView` sweeps `.smooth(0.6)` with `.contentTransition(.numericText(value:))` — the native
odometer, not a manual timer. `grade.outcome` is `engine.outcomeText(grade.outcomeKey)`: **Swift
decides, the bundle speaks.** `verdictGood/Off/Wrong` fires on mount; `breachDelta ≥ 30` additionally
fires the bespoke `breachThud` pattern synchronised to the sweep. Full-bleed 6 % verdict tint. `why`
(≤566) and `learn.concept` (≤435) are **never clamped**; `LearnDisclosure` is a `DisclosureGroup` and
`learn.pointer` stays plain text (R22). **No back control** — a debrief is completed, not browsed.
Re-openable read-only via `VIEW_RESULT`, in which case the entry sequence is skipped.

### 5.9 Shift summary — 16:00 handover (§2.11) · phase `.complete`
`ShiftSummaryView` · `GradeHeadline` · `StatTile` · `InvestigationLine` · `PayoutView` ·
`UnlockCard` · `BoardGlyphRow` · `LadderDisclosure` · `Dock`

**The career is persisted BEFORE this view renders**, so a force-quit here loses nothing. Four
`StatTile`s in a `Grid`; the payout counts up over 800 ms with `.contentTransition(.numericText())`
and `commitSoft` fires at the end; the standing bar sweeps old → new; the ECG flattens and fades out.
`BoardGlyphRow` (`✓ ✓ ✗ …`) is a row of `Button`s → `VIEW_RESULT`. `LadderDisclosure` renders
`copy.ladder.body` as RichText and always carries the addendum-G21 framing — BTL1 / NICE "Cyber
Defense Analyst", explicitly *"not a certification, and it makes no claims about hiring or pay"* — a
credibility guardrail that lives in the exported copy and is asserted by the drift guard. CTA routes
to `.milestone` when `reward.rankUp` or unlocks exist, else `.hub`.

### 5.10 Rank-up / campaign finale (§2.12) · phase `.milestone`
`RankUpView` · `RankBadge` · `LadderTrack` · `HandlerMessageCard`

`.fullScreenCover`, no SystemBar — the one cinematic beat. `RankBadge` is a 6-point
`Path().trim(from: 0, to: progress).stroke()` animated over 900 ms (the native equivalent of
`stroke-dashoffset`), then a 10 % fill fades in; under Reduce Motion it renders finished instantly.
The body is the **actual `ev-rankup` message from `HandlerVoice.inboxFor`**, not a hardcoded string.
`rankup` fires the bespoke 4-event pattern. The `t2` finale variant swaps the eyebrow to
**THE DESK IS YOURS**, the badge to fuchsia, adds the shifts/clean/cases recap, and promotes the
Daily row to the top of the Hub afterwards.

### 5.11 Settings · About · Credits · first-run gate · Kit (§2.13)
`SettingsView` · `FeelSection` · `DeskSection` · `AboutSection` · `LicensesView` ·
`ResetCareerConfirm` · `FirstRunView` · `KitSheet` · `SafariView`

The **one** place `NavigationStack` is correct: Settings → About → Licences is a real drill-down where
swipe-back is right. Toggles are system `Toggle`s (free VO + Dynamic Type). `FirstRunView` is a
blocking `.fullScreenCover` with `.interactiveDismissDisabled(true)` dispatching `ACK_FIRSTRUN`; its
`copy.firstRun` text is **the same block** reprinted under About — the fiction-disclaimer requirement,
enforced by a guardrail test. The privacy policy opens `SFSafariViewController` through a
`UIViewControllerRepresentable` — the app's **only** outbound link, and specifically not an embedded
`WKWebView`, which alone would force a 16+ age rating. `KitSheet` buys through `CareerRules.buyKit`
and no-ops when unaffordable or owned. Reset career is a text button outside the thumb arc behind a
`.confirmationDialog`, firing `destructive`. Credits lists MITRE ATT&CK® attribution and both OFL
texts. Under `#if SENTRY_QA` only (D19), five taps on the version line reveal the screen-jump row that
`ios/scripts/shots.sh` drives.

---

## 6 · `ios/project.yml` (full)

```yaml
# ios/project.yml — the .xcodeproj is generated from this and is gitignored (D24).
name: SentrySOC

options:
  bundleIdPrefix: pl.oumm.sentry
  deploymentTarget: { iOS: "18.0" }
  createIntermediateGroups: true
  generateEmptyDirectories: false
  groupSortPosition: top
  minimumXcodeGenVersion: "2.44.0"
  defaultConfig: Debug

attributes:
  ORGANIZATIONNAME: OUMM

configs:
  Debug: debug
  Release: release

packages:
  SentryCore:
    path: SentryCore          # the LOCAL Swift package — no remote deps, no Package.resolved

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor    # views/stores MainActor by default; SentryCore
    SWIFT_APPROACHABLE_CONCURRENCY: YES         # stays nonisolated (D15)
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    DEAD_CODE_STRIPPING: YES
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: "$(SENTRY_DEV_TEAM)"      # FOUNDER STEP — empty locally; sim builds don't sign
    SWIFT_EMIT_LOC_STRINGS: NO
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"                # CI run number overrides on the archive
  configs:
    Debug:
      SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG SENTRY_QA   # QA jumps compile HERE ONLY (D19)
      ENABLE_TESTABILITY: YES
      ONLY_ACTIVE_ARCH: YES
    Release:
      SWIFT_COMPILATION_MODE: wholemodule
      VALIDATE_PRODUCT: YES

targets:
  SentrySOC:
    type: application
    platform: iOS
    deploymentTarget: "18.0"
    sources:
      - path: SentrySOC/Sources        # whole-tree recursive: C7/C8/C9/C10 add directories
      - path: SentrySOC/Resources      # with ZERO edits to this file
        buildPhase: resources
    dependencies:
      - package: SentryCore
        product: SentryCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: pl.oumm.sentry.soc   # FOUNDER STEP: register on day 1
        PRODUCT_NAME: SentrySOC                         # binary name, no space (D22)
        TARGETED_DEVICE_FAMILY: "1"                     # iPhone only — MUST be target-level (D20)
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        GENERATE_INFOPLIST_FILE: NO
      configs:
        Debug:
          CODE_SIGNING_ALLOWED: NO      # simulator builds need no signing — this is what lets
          CODE_SIGNING_REQUIRED: NO     # CI and a fresh clone build with no Apple account at all
    info:
      path: SentrySOC/Info.plist        # GENERATED by XcodeGen — never hand-edited, gitignored
      properties:
        CFBundleDisplayName: SENTRY SOC
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        CFBundleDevelopmentRegion: en
        LSApplicationCategoryType: public.app-category.puzzle-games
        ITSAppUsesNonExemptEncryption: false     # skips the export questionnaire every upload
        UIUserInterfaceStyle: Dark               # no light-mode flash on launch
        UIRequiresFullScreen: true
        UIStatusBarStyle: UIStatusBarStyleLightContent
        UIViewControllerBasedStatusBarAppearance: true
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UILaunchScreen:
          UIColorName: LaunchGround              # #010409 — native splash, no white flash
          UIImageName: LaunchMark
          UIImageRespectsSafeAreaInsets: true
        UIAppFonts:                              # BARE filenames — resources flatten (D21)
          - IBMPlexMono-Regular.ttf
          - IBMPlexMono-Medium.ttf
          - IBMPlexMono-SemiBold.ttf
          - SpaceGrotesk-Regular.ttf
          - SpaceGrotesk-Medium.ttf
          - SpaceGrotesk-SemiBold.ttf

  SentrySOCTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "18.0"
    sources: [SentrySOC/Tests]
    dependencies:
      - target: SentrySOC
      - package: SentryCore
        product: SentryCore
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGNING_ALLOWED: NO
        BUNDLE_LOADER: $(TEST_HOST)
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/SentrySOC.app/SentrySOC

schemes:
  SentrySOC:
    build:
      targets:
        SentrySOC: all
        SentrySOCTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      gatherCoverageData: false
      targets: [SentrySOCTests]
    archive:
      config: Release
```

Companion `ios/.gitignore`:

```
SentrySOC.xcodeproj/
SentrySOC/Info.plist
.build/
DerivedData/
*.xcuserdatad
```

Two properties worth calling out, both deliberate: `sources` are **whole-tree recursive**, so
C7/C8/C9/C10 add new subdirectories without editing `project.yml` — which is what makes the
file-ownership in §10 genuinely disjoint; and `TARGETED_DEVICE_FAMILY` is at the **target** level per
the verified D20 gotcha.

---

## 7 · Build and verify

`SIM=C2136147-45C8-42DD-8E3A-EDE974B97154` (iPhone 17 Pro Max, iOS 26.2, booted).

```bash
cd /Users/arvind/Documents/projekty/link26

# ── 1. Content contract (TypeScript) ────────────────────────────────────────
npm run soc:export            # npx tsx scripts/export-soc-content.ts ; prints the diffSummary
npm test                      # vitest: engine · cases · handoff · state · taxonomy · daily · DRIFT
npx tsc --noEmit -p tsconfig.json
npm run build                 # next build — proves the additive exporter broke nothing
git diff --exit-code -- app/lib/soc app/lib/career app/lib/game app/components/soc   # D1

# ── 2. Engine parity — no simulator, no .xcodeproj, ~6 s ────────────────────
swift test --package-path ios/SentryCore
#   ~250 named cases: 96 golden grades + 12 synthetic + trace + 7 shift runs + scoring
#   + tuning + career + inbox + integrity + lenient-schema + reducer + effects
#   + heartbeat + haptic patterns.
#   VERIFIED today on .../scratchpad/probe: multi-target SPM resources, Bundle.module in both a
#   library and a test-only fixture target, Swift Testing under `swift test`, swift-tools 6.2 +
#   .swiftLanguageMode(.v6), and exact JS→Swift Double round-trip (0.8571428571428571 == 6.0/7.0).

# ── 3. Project generation ───────────────────────────────────────────────────
/opt/homebrew/bin/xcodegen generate --spec ios/project.yml     # writes ios/SentrySOC.xcodeproj

# ── 4. Simulator build + app-layer tests — no signing, no Apple account ─────
xcodebuild build -project ios/SentrySOC.xcodeproj -scheme SentrySOC -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath ios/.build
xcodebuild test  -project ios/SentrySOC.xcodeproj -scheme SentrySOC \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath ios/.build
#   VERIFIED today: xcodegen 2.44.1 → local package → ** BUILD SUCCEEDED ** on this destination,
#   and `-showBuildSettings` confirmed SWIFT_STRICT_CONCURRENCY=complete, SWIFT_VERSION=6.0,
#   IPHONEOS_DEPLOYMENT_TARGET=18.0 — and exposed the D20 TARGETED_DEVICE_FAMILY gotcha.

# ── 5. Install, launch, screenshot  (ios/scripts/shots.sh) ──────────────────
APP=ios/.build/Build/Products/Debug-iphonesimulator/SentrySOC.app
xcrun simctl install "$SIM" "$APP"
for S in hub intro board case source evidence call debrief summary rankup settings firstrun kit; do
  xcrun simctl terminate "$SIM" pl.oumm.sentry.soc 2>/dev/null
  xcrun simctl launch    "$SIM" pl.oumm.sentry.soc -SentryQAScreen "$S"
  sleep 1.5
  xcrun simctl io "$SIM" screenshot "docs/screenshots/ios/$S.png"
done
#   × three Dynamic Type sizes via `xcrun simctl ui "$SIM" content-size {extra-small,medium,
#   accessibility-medium}`, and hub/case/debrief re-captured on an iPhone 16e-class device to
#   catch 375 pt overflow.
#   VERIFIED today: install + launch with a custom argument + `simctl io screenshot` all work.

# ── 6. Release guard (ios/scripts/verify.sh), before any archive ────────────
#   fails if: the export is dirty vs a fresh run
#   fails if: contentHash differs across any of the 10 generated files
#   fails if: `strings` on a Release binary contains SENTRY_QA / SentryQAScreen
#   fails if: any Resources/*.ttf has no matching OFL text
#   fails if: a hex colour or a font name appears outside Design/Theme.swift or Typography.swift
#   fails if: grep -inE "damn|shit|fuck|kill|hostage|weapon" over cases.ts + the exported JSON hits
#             (the 4+ age-rating questionnaire answer)
#   fails if: the merge-base diff touches next.config.ts open-next.config.ts wrangler.jsonc app/api
```

**Makefile:** `make export` (1) · `make kit` (2) · `make project` (3) · `make build` (3+4) ·
`make shots` (5) · `make verify` (1+2+4+6) · `make` = `make verify`.

**Kill-and-relaunch check** (manual, in the runbook): launch → start Shift 1 → pull two sources →
file one call → `simctl terminate` → relaunch → the Hub shows a Resume card restoring the exact
`ShiftState`, `queried` and meters. That is the mid-shift-snapshot acceptance test.

### CI — `.github/workflows/ios.yml`

| job | runner | runs | gate |
|---|---|---|---|
| `contract` | `ubuntu-latest`, ~2 min | `npm ci && npm test && npx tsc --noEmit && npm run build` | **REQUIRED** — the drift guard runs here, so a content-only PR gets fast feedback and cannot merge with a stale export |
| `engine` | macOS, ~3 min | `swift test --package-path ios/SentryCore` | **REQUIRED** — needs no Xcode project and no simulator, which is why the parity gate can be mandatory on every PR |
| `app` | macOS, ~8 min | `brew install xcodegen`; `xcodegen generate`; `xcodebuild build` + `test`; upload `docs/screenshots/ios/**` | required on `ios/**` paths |
| `guards` | `ubuntu-latest` | the D1 merge-base diff (`actions/checkout` with `fetch-depth: 0`), the pay-figure regex over the exported JSON, and the SENTRY_QA string check | **REQUIRED** |

**Unverified:** whether a GitHub-hosted macOS runner image carries Xcode 26.2. `docs/IOS-BUILD.md`
pins `sudo xcode-select -s /Applications/Xcode_26.2.app` and the workflow tries `macos-26` then
`macos-latest`. If neither has it, the **`app` job goes `continue-on-error: true`** and the founder's
Mac is the app gate — `contract` and `engine` still gate merges, which is precisely why the parity
gate was designed to need no Xcode.

### Founder-only steps (D25) — `docs/IOS-BUILD.md` § "Founder steps"

1. Apple Developer Program membership active; all agreements accepted in App Store Connect.
2. Register the bundle id `pl.oumm.sentry.soc` (do this on day 1 — the ASC record and an internal
   TestFlight group can exist long before the first archive).
3. Set the Team: `export SENTRY_DEV_TEAM=<TEAMID>` and re-run `xcodegen generate`, or set it in
   Xcode → Signing & Capabilities.
4. Create the App Store Connect record + internal TestFlight group.
5. **A device pass to feel the haptics** — the Simulator has no haptic hardware, so the lub-dub
   curve, the stamp and the breach thud are unverifiable until this. Blocking before submission,
   not before the simulator build.
6. Product → Archive → Distribute (or `xcodebuild archive` + `-exportArchive`).

---

## 8 · App Store package

From `ios-design-spec.md` §6, adjusted: **there is no WKWebView anywhere, so the 4.2
"repackaged website" concern is gone.**

| field | value |
|---|---|
| App Store name | **SENTRY — SOC** |
| Subtitle | Tier-1 SOC analyst shifts |
| Home-screen name | SENTRY SOC |
| Bundle id | `pl.oumm.sentry.soc` |
| Category | **Games › Puzzle**, secondary Education |
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = 1`, target-level per D20), portrait, **iOS 18.0+** (was 16.0 — D14) |
| Version / build | 1.0 / CI run number |
| Price | **Paid up-front** (Tier 5, $4.99) — zero StoreKit, zero restore flow, and it keeps "Data Not Collected" trivially true. No ads, no timers, no consumables, no loot, stated in-app under "Our promise". |

**Age rating.** Text-only fictional security alerts trigger no Violence / Mature / Medical /
Gambling / Unrestricted-Web-Access descriptor → computes **4+**. `verify.sh` runs the profanity grep
over `cases.ts` **and the exported JSON** before the answers are filed. The privacy link opens
`SFSafariViewController`, which does not force 16+; an embedded browser would.

**Privacy.** Label **Data Not Collected** — true because v1 ships no analytics, no crash SDK, no
account and no network call. Guideline 5.1.1(i) still requires a privacy-policy link in ASC metadata
**and** inside the app at zero collection → Settings › Privacy policy → `https://<worker>/privacy`
on the existing Cloudflare deploy. *(The static `app/privacy/page.tsx` route is a founder/web task,
not an iOS ticket — D1 keeps iOS out of the web tree. Until it exists the link points at the site
root and `docs/APPSTORE.md` flags it as a submission blocker.)*

**Info.plist.** `ITSAppUsesNonExemptEncryption = NO`, `UIStatusBarStyle = UIStatusBarStyleLightContent`,
`UIViewControllerBasedStatusBarAppearance = YES`, portrait-only, `UIRequiresFullScreen = YES`,
`UIUserInterfaceStyle = Dark`. Built with Xcode 26.2 / iOS 26 SDK — mandatory for uploads since
2026-04-28, satisfied.

**Notes for Review (2.3.1 — specificity is the requirement).** Keep §6's paragraph verbatim, with two
edits: replace *"haptic feedback (UIKit feedback generators)"* with **"Core Haptics patterns"**, and
add **"The app is written in SwiftUI; it contains no web view."**

**2.1 / 4.3 "lasting value" defence** (the only remaining review risk): the campaign (24 cases,
5 shifts) + the career ladder + a **precomputed 730-day Daily calendar** so the hub reads complete
with no "coming soon" card; App Store screenshots (6.9" from the 17 Pro Max simulator) show gameplay
— hub, case, evidence board, the call, the debrief stamp, the rank-up; the Notes name Uplink and
Hacknet; priced as a small finished game, not a licence. Ship a TestFlight build before polish is
finished so a verdict arrives while the codebase is small; the 9 archetype×verdict grid gaps are a
queued v1.1 content drop in one file.

---

## 9 · Risks

| # | risk | mitigation |
|---|---|---|
| **X1** | **A new engine branch is added in TypeScript and Swift silently keeps the old behaviour** — the divergence the whole contract exists to prevent. | `OutcomeKey` is a **closed** Swift enum, deliberately against the lenient policy used everywhere else (D10). A new key **fails to decode** at bundle load, before any grading test runs, naming the key. A changed delta on an existing branch fails one of the 96 parameterised rows with the caseId and disposition in the message. There is no path where TS logic changes and Swift stays green. |
| **X2** | **The dead `tp.under-contained` branch (D11).** Only 10 of 11 outcomes are reachable over the shipped corpus, so a Swift transcription bug in the `breachDelta = 10` arm ships undetected and detonates the first time a TP is authored without acceptables. | `grades-synthetic.json` — 3 constructed cases × 4 dispositions = 12 rows reaching all 11 keys and all 12 arms, asserted in the same parameterised suite. Drift-guard check #4 fails if a future key is unreached. **This risk is verified, not hypothetical.** |
| **X3** | Regenerating fixtures **blesses a mistake**: someone breaks the engine, re-runs the export, and the drift guard goes green on wrong values. | Three independent layers: (1) the exporter prints a `diffSummary` naming every changed row, which the PR template requires pasting — a silent regeneration is visible in review; (2) `engine.test.ts` / `cases.test.ts` / `taxonomy.test.ts` assert **properties**, not snapshots (every shift covers three verdicts; `verdictOf(correctDisposition) == truth`; every FP closes and every TP escalates), so a semantic error fails an invariant no snapshot can absorb; (3) exhaustiveness requires every `OutcomeKey` to be reached. |
| **X4** | **The web copy drifts** and the app ships stale or contradictory text — the exact failure the taxonomy playtest already caught once, where the intro taught one definition and the grader used another. | The SHA-pinned source slices (D5): any edit to the taxonomy JSX, `DISPOSITION_META`, `gradeMeta`, the coach steps or the handler bodies **aborts the export** with `stale pin: <file>#<region>`. Plus the 96-pair `outcomeKey ↔ prose` cross-assert (D2). Both run inside `npm test`. |
| **X5** | Float and integer semantics differ across the boundary; `accuracy` is a JS double and a one-ULP flip at the 0.8 clean threshold changes a grade. | **Verified empirically today:** JS emits shortest-round-trip IEEE-754 and Swift's `JSONDecoder` reconstructs the identical bit pattern (`0.8571428571428571 == 6.0/7.0` exactly), so fixtures assert `==`, not a tolerance — drift is what we want to catch. Rates carry their numerator/denominator so a failure localises to the counter. Meters are `Int`, protected by drift-guard check #5. |
| **X6** | **Unicode drift** — the corpus is full of em-dashes, middots, arrows and `⬢ ⬡ ¢ ✓ ✗`; an escape or re-encode corrupts the bundle invisibly. | The canonical serialiser writes raw UTF-8 with no `\u` escaping and no BOM; `contentHash` is a sha256 over those exact bytes and is cross-asserted identical across all 10 files, so a re-encode anywhere breaks the check. `IntegrityTests` additionally pins the character counts of the two known-long fields (559 / 566). |
| **X7** | **The Simulator has NO haptics hardware**, so the lub-dub curves, the stamp and the breach thud are unverifiable before a physical device. A wrong sharpness or a 40 ms-off dub reads as a cheap buzz and undoes the premium feel the whole design is built on. | Every pattern is a pure function in `SentryCore/Feel/` returning value types; `HapticPatternTests` asserts exact event times, intensities and curve control points on macOS in `swift test`. `Haptics/CHPatterns.swift` is a dumb translator with no logic. Everything is gated on `capabilitiesForHardware().supportsHaptics` so the Simulator silently no-ops. A `-hapticTrace` launch argument logs every cue. **The founder device pass is an explicit blocking checklist item before submission** (§7 step 5). |
| **X8** | **Battery / annoyance** from a 150 bpm heartbeat, or audible drift from a Timer-driven scheduler. | One `CHHapticAdvancedPatternPlayer` with `loopEnabled` + `loopEnd` — the OS schedules every beat, so no Timer, no drift, no per-beat main-thread wake-up (D17). All guards live in the pure unit-tested `heartbeatPlan`: HUNT/LOCKDOWN only, investigating only, 400 ms floor, 40 s auto-suspend, `scenePhase` stop, Settings toggle. Silence at CALM/ALERT is the reward. |
| **X9** | **Swift 6 strict concurrency** fights the design — a global content bundle, `@MainActor` UI, and a `CHHapticEngine` calling back on its own queue. | `SentryCore` is 100 % `Sendable` value types with zero global mutable state and imports Foundation only, verified compiling under `.swiftLanguageMode(.v6)` on the probe. `ContentPack.bundled` is a `static let` of a `Sendable` struct (`swift_once`). The app sets `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` + `SWIFT_APPROACHABLE_CONCURRENCY=YES` (both keys verified present in Xcode 26.2's `Swift.xcspec`), so isolation noise disappears; the one off-main hop is `actor SaveStore`. |
| **X10** | **A font fails to register** and iOS silently falls back to system-ui — the app looks generic and nobody notices until a screenshot review (R8). | `FontRegistrationTests` asserts `UIFont(name:size:) != nil` for all six faces in CI, plus a DEBUG launch `fatalError` naming the missing file. Bare `UIAppFonts` filenames per the verified D21. `docs/IOS-BUILD.md` pins the exact GitHub release URLs and a SHA256 per TTF; never Fontsource (woff/woff2 only). `verify.sh` fails on a TTF without its OFL text. |
| **X11** | **Dynamic Type at accessibility sizes destroys** the dense Case and Debrief layouts (11 pt tracked labels, 72 pt rows, a four-tile stat grid). | Root `.dynamicTypeSize(.xSmall ... .accessibility1)` — a sane clamp, not a refusal to scale. Tracked labels bind `relativeTo: .caption2` with `.minimumScaleFactor(0.9)`; long prose is unclamped and scrolls; StatTiles reflow to one column above `.xxLarge`. The screenshot gate captures every screen at three sizes. |
| **X12** | The **`.xcodeproj` is generated and gitignored**, so a build setting changed in the Xcode UI is lost on the next `xcodegen generate`; and an xcodegen bump silently changes the project. | Rule #1 in `docs/IOS-BUILD.md`: all project configuration lives in `ios/project.yml`, including every Info.plist key. `minimumXcodeGenVersion: "2.44.0"` is pinned. CI regenerates from a clean clone and builds. And the parity gate needs neither xcodegen nor the project (D24), so a generation problem can never block the contract. |
| **X13** | **iOS 18.0 excludes iPhone X / 8-class devices.** | Accepted, and cheap to reverse: dropping to 17.0 costs exactly `MeshGradient` (the LOCKDOWN ground) and `onScrollGeometryChange` (the collapsing header), each with a documented one-file replacement. `@Observable`, `.sensoryFeedback` and `.contentTransition(.numericText())` — what the architecture is actually built on — are already 17.0. |
| **X14** | **App Review 2.1 / 4.3 "lasting value"** on a 24-case, ~55-minute game. | The 4.2 risk is gone (genuinely native, no web view), which concentrates the remaining risk here. Countered per §8. TestFlight first so a verdict arrives while the codebase is small. |
| **X15** | **Parallel agents collide** on `package.json`, `project.yml`, `Package.swift` or the generated JSON. | §10's `paths_owned` are disjoint and exhaustive. Every generated artefact lives in `SentryContent/` and `SentryFixtures/`, two SPM targets owned solely by C1 and physically separate from the hand-written engine. `Package.swift` declares all eight targets on day one, and `project.yml` uses whole-tree recursive source paths — so exactly one ticket touches each. `schema.ts` is frozen and published in hour one so C2 codes against a fixed contract before C1's first export exists. |
| **X16** | The **CI macOS image may not carry Xcode 26.2** (unverified). | The `app` job goes `continue-on-error: true` in that case; `contract`, `engine` and `guards` still gate merges. This is the payoff of designing the parity gate to need no Xcode. |
| **X17** | **Schedule slips land on a player-facing screen.** | The cut line is explicit and ordered: (1) the **Daily** — `daily.json` and the Hub's daily row sit behind `features.daily` and the campaign is complete without it; C1's daily sub-scope can be dropped without blocking any other ticket; (2) the **t2 finale variant** of RankUp (the plain rank-up beat still ships); (3) the **read-only debrief** re-open from the Board's done rows (`VIEW_RESULT`). Nothing in the core loop — intro → case → source → call → debrief → summary — is on the cut line. |
| **X18** | **Accepted, unchanged from §7:** R22 (`learn.pointer` stays plain text), R23 (no abandon-recovery of a mid-shift score), R25 (no iPad build in v1). | Accepted deliberately, for the reasons already recorded in `ios-design-spec.md` §7. |

---

## 10 · Work breakdown

**11 tickets. `paths_owned` are disjoint — every path appears in exactly one ticket.**
`package.json` and `scripts/` are both owned by **C1**; the iOS shell scripts therefore live under
`ios/scripts/` (C11), which is a different path.

---

### C1 — Content export: schema, copy lift, SHA pins, daily calendar, 7 fixtures, drift guard
- **paths_owned:** `app/lib/soc/exporter/` · `scripts/` · `package.json` ·
  `ios/SentryCore/Sources/SentryContent/` · `ios/SentryCore/Sources/SentryFixtures/`
- **depends_on:** —
- **size:** L
- **acceptance:**
  1. `npm run soc:export` writes `content.json` (schemaVersion 1, contentHash, dispositions, **26**
     sources, **24** cases incl. the 3 handoff cases, 5 shifts with the blue-only 0/40/80/120/160
     ladder, 4 ranks, 1 kit item, tuning), `copy.json`, `daily.json` (**730** days) and the **7**
     fixture files — all canonical (sorted keys, 2-space, LF, trailing newline, raw UTF-8, no BOM, no
     timestamp, no git SHA) and all carrying the **same** `contentHash`.
  2. `grades.json` has exactly **96** rows. `grades-synthetic.json` has **12** and reaches all **11**
     `OutcomeKey`s including `tp.under-contained` (D11).
  3. `shift-runs.json`'s `demo-complete` entry matches the pinned score of D13 exactly:
     `accuracy 0.8571428571428571`, `blindCalls 1`, `noise 12`, `grade "rough"`, `+300¢`, `+15⬢`,
     inbox `[ev-rough, tip-kit]`.
  4. `daily.test.ts`: over all 730 dates every §4.2 constraint holds (three verdicts present, ≤2 per
     archetype, FP+BTP ≥ TP, never opens on a TP), the same date yields the identical order, no case
     appears on two consecutive days, the fallback ladder is exercised with a starved pool, and the
     generator never throws.
  5. `drift.test.ts` runs inside `npm test` and enforces all 9 checks of §2.5 — including byte
     equality for all 10 files, the pay-figure regex over the exported bundle, every `sourcePins.ts`
     SHA, and `git diff --exit-code` over the four protected web directories (**D1**).
  6. The exporter prints a `diffSummary` naming every changed grade row.
  7. `package.json` gains `soc:export` and `soc:check` and drops the now-dead `@capacitor/*` and
     `@fontsource*` dependencies; `npm run build` still green.
  8. **`app/lib/soc/exporter/schema.ts` is the FIRST file committed and its path is posted within the
     first hour** so C2 codes against a frozen contract (§11).
  9. **Cut line:** `daily.ts` + `daily.json` can be dropped without blocking any other ticket.

### C2 — Swift package skeleton, Codable models, openness policy, decode tests
- **paths_owned:** `ios/SentryCore/Package.swift` · `ios/SentryCore/Sources/SentryCore/Model/` ·
  `ios/SentryCore/Sources/SentryCore/Content/` · `ios/SentryCore/Tests/ContentTests/` · `ios/.gitignore`
- **depends_on:** C1
- **size:** M
- **acceptance:**
  1. `Package.swift` declares **all eight targets** on day one (§3.1) so no later ticket edits it;
     swift-tools 6.2, platforms `.iOS(.v18)` + `.macOS(.v14)`, `.swiftLanguageMode(.v6)` everywhere,
     zero remote dependencies. `swift build --package-path ios/SentryCore -Xswiftc -warnings-as-errors`
     green with **no** UIKit / SwiftUI / CoreHaptics import anywhere.
  2. Every type in the §2.2 schema has a `Sendable`+`Codable`+`Hashable` Swift mirror with
     synthesised `CodingKeys` matching the JSON keys 1:1; every enum's `rawValue` is the TypeScript
     literal verbatim (`escalate-ir-isolate`, `benign-true-positive`, …); `Disposition` is
     `CaseIterable` in exported order; `TraceStatus` is `Comparable` (DV-3).
  3. The **openness policy (D10)** is implemented and tested: closed `SocVerdict` / `Disposition` /
     `ShiftGrade` / `TraceStatus` / `OutcomeKey` / `InvestigationQuality`; lenient
     `SocArchetype` / `ToolSeverity` / `EvidenceWeight`; unknown keys ignored.
     `LenientSchemaTests` decodes a synthetic bundle carrying `archetype "lateral-movement"`,
     `toolSeverity "Informational"`, `weight "circumstantial"` and two unknown keys and asserts it
     loads; a companion asserts an unknown `outcomeKey` **fails** to decode.
  4. `ContentPack.bundled` decodes `content.json` + `copy.json` + `daily.json` and exposes
     `casesByID` (24), `sourcesByID` (26), `shiftsByID` (5); `SocCase.sources` is expanded from
     `sourceIds`. `IntegrityTests` covers every check in §3.6.
  5. `swift test --package-path ios/SentryCore` green.
  6. `ios/.gitignore` excludes `SentrySOC.xcodeproj/`, `SentrySOC/Info.plist`, `.build/`,
     `DerivedData/`, `*.xcuserdatad`.

### C3 — Engine port + golden parity tests
- **paths_owned:** `ios/SentryCore/Sources/SentryCore/Engine/` · `ios/SentryCore/Tests/EngineTests/`
- **depends_on:** C2
- **size:** L
- **acceptance:**
  1. `Trace.status`/`clamp`, `Disposition.verdict`, `gradeCall`, `outcomeKey`, `buildCaseResult`,
     `applyCall`, `assembleShift`, `shiftComplete`, `overallShiftStatus`, `investigationOf` and
     `scoreShift` are ported **literally** from `engine.ts`/`trace.ts` — iteration order and all,
     never "ported to intent". The asymmetric consequence model is intact (miss a TP +30 breach;
     over-contain +12 noise; under-contain +10 breach; FP escalate 12/20; B-TP mislabel 4, T2 14,
     isolate 24) and so is the grade rule (`clean` iff accuracy ≥ 0.8 **and** 0 missed **and** 0
     blind **and** noise status ∉ {HUNT, LOCKDOWN}; `breached` iff breach status is LOCKDOWN **or**
     ≥2 missed).
  2. **`grep -nE '[0-9]' Sources/SentryCore/Engine/*.swift` shows no tuning literal** — every number
     comes from `content.tuning` (**D7**).
  3. `ShiftState.results` is an ordered `[CaseResult]` and the meters are `public internal(set)`,
     mutable only inside `SentryCore`; DV-1/DV-2 are documented in-file.
  4. `GoldenGradeTests` is `@Test(arguments:)` over all **96** rows comparing every `CallGrade` field
     with exact `==`, including `outcome` resolved through `copy.outcomes[outcomeKey]`; failure
     messages name caseId and disposition. `SyntheticGradeTests` covers the **12** synthetic rows and
     all 11 keys.
  5. `GoldenTraceTests` (111 status rows + clamp edges); `GoldenShiftRunTests` asserts `ShiftState`
     after **every step** of all 7 runs before asserting `ShiftScore` field-by-field;
     `GoldenScoringTests` covers the 5 edge shifts; `TuningExpectationTests` pins the 14 numbers.
  6. `swift test --package-path ios/SentryCore` green in under 15 s, with no simulator and no
     `.xcodeproj`.

### C4 — Career + handler port with template interpolation + golden parity tests
- **paths_owned:** `ios/SentryCore/Sources/SentryCore/Career/` · `ios/SentryCore/Tests/CareerTests/`
- **depends_on:** C2
- **size:** M
- **acceptance:**
  1. `rankFor`, `nextRank`, `owns`, `buyKit`, `awardForShift`, `awardRedRun`, `isUnlocked` ported,
     reading `RANKS`, `KIT` and the award constants from the bundle.
  2. **DV-4:** `rankFor` is a literal ascending last-match loop and `nextRank` a literal
     `first(where:)` — ported as written, not as intended — and a test proves both behave identically
     to TypeScript on a deliberately out-of-order ranks array.
  3. `HandlerVoice.inboxFor` reproduces the selection order (event message → rankUp → unlocks →
     redrun tip → kit tip → welcome) and the `.prefix(4)` cap; `Templating` fills named placeholders
     (`{gap}`, `{rank}`, `{cash}`, `{item}`, `{queue}`) and `fatalError`s in DEBUG on an unfilled one.
     Blue-only behaviour: `tip-redrun` suppressed; `ev-unlock-handoff-shift` and the t2 `ev-rankup`
     voiced as Vale per §3.2.
  4. `GoldenCareerTests` replays the 12-award sequence asserting `state`, `rank`, `nextRank` and the
     unlocked-id set after each, plus `awardRedRun` and the three `buyKit` rows.
  5. `GoldenInboxTests` asserts message **ids AND fully rendered bodies** for all 14 scenarios
     including each rank-up, the handoff unlock, the suppressed cross-seat nudge, the kit tip, the
     fresh-career welcome and the 4-message cap.
  6. Runs in parallel with C3 — no shared file.

### C5 — Session reducer, effects, heartbeat plan, haptic pattern DSL
- **paths_owned:** `ios/SentryCore/Sources/SentryCore/Session/` ·
  `ios/SentryCore/Sources/SentryCore/Feel/` · `ios/SentryCore/Tests/SessionTests/`
- **depends_on:** C3, C4
- **size:** M
- **acceptance:**
  1. `reduce(_:_:content:career:) -> (SessionState, [Effect])` implements the **17** actions of §2.1
     + addendum §C (`VIEW_RESULT` with `readOnly` and a `caseId ∈ results` guard, `ACK_FIRSTRUN`, no
     `CONTINUE`). The `MAKE_CALL` re-entrancy guard (`phase == .investigating`, `SocConsole.tsx:234`)
     and the `OPEN_VIEW(.call)` revealed-evidence guard (`SocConsole.tsx:495`) are **reducer**-level,
     not UI-level. `ReducerTests` covers every transition and both guards.
  2. `EffectScheduleTests`: one `MAKE_CALL` emits exactly one `.haptic`; the settle order is
     `settleShift → persistCareer → clearSession`; a repeat daily emits `markDailyDone` and
     suppresses the standing award but not the cash (addendum G7).
  3. `Feel/` is **Foundation-only** (no CoreHaptics import) so it stays in the macOS `swift test`
     build. `SocCue` enumerates the 15 cues of §2.15. `heartbeatPlan` implements nil-at-CALM/ALERT,
     `60000/BPM` at HUNT/LOCKDOWN, the 400 ms floor, the 120 ms dub offset and the 40 s auto-suspend,
     every number from `tuning.heartbeat` and `tuning.bpm`. `HeartbeatTests` covers all four
     statuses, the floor, re-arming and suspension.
  4. `CHPatternSpec` describes the heartbeat (continuous 90 ms lub with the 0 → 1.0 @18 ms → 0 @90 ms
     intensity curve, transient dub at +120 ms), `file`, `breachThud` and `rankup` as pure
     `HapticPattern` values. `HapticPatternTests` asserts exact event times, intensities, sharpnesses
     and curve control points — **the only pre-device verification that exists** (X7).
  5. `swift test --package-path ios/SentryCore` green.

### C6 — XcodeGen project, app shell, persistence, fonts, assets, design tokens, motion gate
- **paths_owned:** `ios/project.yml` · `ios/SentrySOC/Sources/App/` · `ios/SentrySOC/Sources/State/` ·
  `ios/SentrySOC/Sources/Services/` · `ios/SentrySOC/Sources/Design/` · `ios/SentrySOC/Resources/` ·
  `ios/SentrySOC/Tests/`
- **depends_on:** C2
- **size:** L
- **acceptance:**
  1. From a clean checkout with **no Apple account**:
     `xcodegen generate --spec ios/project.yml && xcodebuild build -project ios/SentrySOC.xcodeproj -scheme SentrySOC -destination 'platform=iOS Simulator,id=C2136147-45C8-42DD-8E3A-EDE974B97154'`
     succeeds; the app installs, launches and screenshots with **no white flash**
     (`UILaunchScreen` → `LaunchGround` #010409).
  2. `xcodebuild -showBuildSettings` reports `IPHONEOS_DEPLOYMENT_TARGET = 18.0`,
     `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
     and **`TARGETED_DEVICE_FAMILY = 1`** (not `1,2` — the D20 gotcha is the acceptance test). The
     generated Info.plist carries Dark, `UIRequiresFullScreen`, portrait-only,
     `ITSAppUsesNonExemptEncryption=false` and all six `UIAppFonts` entries as **bare filenames**.
  3. `project.yml` uses whole-tree recursive source paths so no later ticket edits it; Info.plist and
     the `.xcodeproj` are generated and gitignored.
  4. `GameModel` is `@MainActor @Observable`, exposes `content/engine/rules/voice/career/settings/
     session/inbox` with **intent methods only**, and `send(_:)` is the single entry point;
     `EffectRunner` is the only interpreter of `Effect`.
  5. Career and session persist as versioned JSON in Application Support through `actor SaveStore`,
     atomic + `.bak` rotation + file protection; `UserDefaults` holds only the five launch-critical
     flags; hydration is **synchronous in `init()`** before the first frame; a corrupt file is
     renamed, not overwritten. `SaveStoreTests` round-trips every model, proves unknown and missing
     fields survive, and proves a kill-and-relaunch mid-shift restores the exact `ShiftState`.
     `EffectScheduleTests` (app-side) proves the runner performs each effect once.
  6. Six TTFs + both OFL texts committed with SHA256s recorded; `FontRegistrationTests` asserts
     `UIFont(name:size:) != nil` for all six.
  7. `Design/Theme.swift` implements the full §2.16 token table (ground/panel/scrim, the zinc ramp,
     the five semantic accents, the STATUS_COLOR ramp with **cyan CALM**) and `Typography.swift` the
     seven-step scale with an 11 pt tracked floor, both faces through
     `Font.custom(_:size:relativeTo:)`. `Motion.swift` holds every §2.14 duration and curve and the
     single `gated(_:)` Reduce-Motion gate.
  8. Under `#if SENTRY_QA` (Debug only), `-SentryQAScreen <name>` jumps to any named screen, and a
     DEBUG "start Shift 1" entry exists so the loop is playable before C9 lands.

### C7 — Components: chrome, ECG, meters, stamp, hold-to-file ring, rows and cards
- **paths_owned:** `ios/SentrySOC/Sources/Components/`
- **depends_on:** C6
- **size:** L
- **acceptance:**
  1. Seventeen primitives ship, each with a `#Preview` covering its states: `SystemBar`, `ECGCanvas`,
     `Dock`, `SheetChrome`, `MeterView`, `StatTile`, `Chip`, `StampView`, `HoldToFileButton`,
     `SourceRow`, `EvidenceCard`, `QueueRow`, `InboxCard`, `RankBadge`, `CoachBubble`,
     `RichTextView`, `SegmentedTabs`.
  2. `ECGCanvas` is `TimelineView(.animation(minimumInterval: 1/30, paused:))` + `Canvas`, scroll
     period `60/tuning.bpm[status]`, paused when `phase != .investigating` or
     `scenePhase != .active`, degrading under Reduce Motion to a static `Path` glyph + label.
  3. `HoldToFileButton` drives its conic ring from a `TimelineView` clock reading a `Date` delta
     (never `withAnimation` fighting the gesture): 550 ms, ticks at 0/180/360 ms, cancels on early
     release with **zero** state change, ≥64 pt, `.accessibilityAction(named: "File this call")`, and
     a two-tap mode.
  4. `RichTextView` folds `[RichSegment]` into one `AttributedString` with per-run
     `foregroundColor` from `Theme` (D5). `MeterView` and `StatTile` use
     `.contentTransition(.numericText(value:))`.
  5. Every interactive primitive has a custom `ButtonStyle` with a real pressed state and a ≥44 pt hit
     target. Every `Motion` constant collapses under Reduce Motion, verified by a preview at both
     settings.
  6. **No hardcoded hex or font name outside `Design/`** — enforced by `ios/scripts/verify.sh`.
  7. A `-SentryQAScreen kit` harness renders SystemBar in all four statuses, a sheet, the Dock, every
     tone, the meters and the ladder; its screenshot is captured by C11.

### C8 — Play screens: intro, board, case, source, evidence, call, debrief, abandon
- **paths_owned:** `ios/SentrySOC/Sources/Screens/Play/`
- **depends_on:** C5, C7
- **size:** L
- **acceptance:**
  1. The full loop is playable end to end on the simulator: intro → case → pull a source → make the
     call → debrief → next alert → summary hand-off.
  2. **Zero hardcoded player-facing text** — every string comes from `CopyPack`, grep-enforced.
  3. The Case header collapses via `.onScrollGeometryChange`; Coach and Dock are two stacked
     `.safeAreaInset(edge: .bottom)` so they can never overlap the alert header (PLAYTEST P2).
  4. `SourceSheet` grows `[.height(320), .large]` on the pull; findings stagger at 45 ms with
     `findingLand` capped at 3; `evidence.detail` is never truncated.
  5. Upcoming queue rows show `alertTitle` only (no severity chip); `decisive`/`supporting`/
     `neutral`/`noise` render identically during play; the Board's two `fear` strings are visible
     captions **and** VoiceOver hints; done rows dispatch `VIEW_RESULT`.
  6. `CallSheet` rows are built from `copy.dispositionMeta` in exported order; the debrief's ~1.1 s
     entry sequence is skippable by tapping anywhere and fires `breachThud` when
     `breachDelta ≥ 30`; `why` and `learn.concept` are never clamped.
  7. **Every meter value and every grade comes from a `SentryCore` call** — `grep` for arithmetic on
     `breachRisk`/`noise`/`cash`/`standing` under `Screens/` returns nothing (guaranteed by D8, but
     asserted).
  8. A full Shift 1 played on the simulator produces the same `ShiftScore` as `shift-runs.json`.
  9. VoiceOver labels on every source row, meter, disposition row and the stamp. Runs in parallel
     with C9.

### C9 — Meta screens: hub, summary, rank-up, settings, first-run, kit, licences
- **paths_owned:** `ios/SentrySOC/Sources/Screens/Meta/`
- **depends_on:** C5, C7
- **size:** L
- **acceptance:**
  1. Hub renders rank, the standing bar, the Resume card when a snapshot exists, the `InboxCard` from
     `HandlerVoice.inboxFor`, all five queue rows with the blue-only lock states from `isUnlocked`,
     the daily row, the kit entry and the Dock whose label follows the §2.3 rule. Locked rows are
     inert with a **visible** reason (`⬡ LOCKED · opens at ⬢ 120`, no emoji) and fire `denied` once
     per visit.
  2. `ShiftSummaryView` renders **after** the career is persisted (a force-quit here loses nothing):
     the grade headline from `copy.gradeMeta`, four `StatTile`s, the investigation line with its
     blind-call clause, the payout count-up and standing sweep, unlock cards, the tappable board
     glyph strip, and the ladder disclosure carrying the BTL1/NICE framing and the "no pay figures"
     line verbatim.
  3. `RankUpView` is a `.fullScreenCover` with the 900 ms hexagon `Path.trim` draw (instant under
     Reduce Motion), the ladder track from the exported ranks, and a body that is the actual
     `ev-rankup` message from `inboxFor()`; the t2 finale variant adds the recap row and the fuchsia
     badge.
  4. `KitSheet` buys through `CareerRules.buyKit` and no-ops when unaffordable or owned.
  5. `FirstRunView` blocks on first launch with `copy.firstRun`, dispatches `ACK_FIRSTRUN`, and the
     **same** block reappears under Settings → About (grep-enforced). Settings is the only
     `NavigationStack`; the privacy link opens `SFSafariViewController` and is the app's only
     outbound link; Reset career is outside the thumb arc behind a `.confirmationDialog`; Licences
     lists MITRE attribution and both OFL texts.
  6. Under `#if SENTRY_QA` only, five taps on the version line reveal the screen-jump row. Runs in
     parallel with C8.

### C10 — Core Haptics service: engine lifecycle, patterns, looping heartbeat, cue routing
- **paths_owned:** `ios/SentrySOC/Sources/Haptics/`
- **depends_on:** C5, C6
- **size:** M
- **acceptance:**
  1. `HapticsEngine` is `@MainActor` with a lazy `CHHapticEngine`, `playsHapticsOnly = true`,
     `isAutoShutdownEnabled = true`, reset/stopped handlers that restart it, and **every** call gated
     on `capabilitiesForHardware().supportsHaptics` so the Simulator no-ops silently instead of
     crashing.
  2. The heartbeat runs on **one** `CHHapticAdvancedPatternPlayer` with `loopEnabled` and
     `loopEnd = period` — **no `Timer` anywhere** — built from `CHPatternSpec.heartbeat`: a
     continuous 90 ms lub carrying a `CHHapticParameterCurve` (0 → 1.0 by 18 ms → 0 by 90 ms) and a
     transient dub at +120 ms. HUNT = 0.536 s / 0.75 / 0.30; LOCKDOWN = 0.400 s / 1.00 / 0.55. Status
     changes modulate live via `sendParameters`, never by rebuilding.
  3. `file`, `breachThud` and `rankup` are real multi-event patterns matching their §4.4 timings; the
     other 12 cues route to `.sensoryFeedback`. All 15 cues are wired.
  4. Guards honoured: HUNT/LOCKDOWN only, `phase == .investigating` only, 400 ms floor, 40 s suspend
     with re-arm, stop on `scenePhase != .active`, Settings toggle. **Reduce Motion does NOT disable
     haptics** (D18), documented in-file as a deliberate divergence from §2.15.
  5. `Haptics/CHPatterns.swift` contains **no logic** — it is a dumb translator from
     `SentryCore.HapticPattern` to `CHHapticEvent`, so the timing assertions live in
     `swift test` (C5's `HapticPatternTests`).
  6. A `-hapticTrace` launch argument logs every cue with its timestamp. Runs in parallel with C8/C9.

### C11 — Verification gate: Makefile, scripts, CI, guards, screenshots, runbook, store package
- **paths_owned:** `Makefile` · `ios/scripts/` · `.github/workflows/ios.yml` · `docs/IOS-BUILD.md` ·
  `docs/APPSTORE.md` · `docs/screenshots/ios/`
- **depends_on:** C8, C9, C10
- **size:** M
- **acceptance:**
  1. `make` runs the whole gate of §7: `soc:export` → `npm test` (with the drift guard) → `tsc` →
     `next build` → the D1 diff → `swift test` → `xcodegen generate` → `xcodebuild build` + `test` →
     screenshots → the release guard.
  2. `ios/scripts/shots.sh` captures **13** screens × **3** Dynamic Type sizes on the iPhone 17 Pro
     Max, and re-captures hub/case/debrief on an iPhone 16e-class device to catch 375 pt overflow;
     PNGs are committed under `docs/screenshots/ios/` as the founder sign-off artefact.
  3. `ios/scripts/verify.sh` fails on every condition in §7 step 6.
  4. CI has the four jobs of §7 with `actions/checkout` `fetch-depth: 0`; `contract`, `engine` and
     `guards` are **required**; `app` degrades to `continue-on-error` if the runner lacks Xcode 26.2
     (X16).
  5. `docs/IOS-BUILD.md` reproduces from a clean `git clone` + `npm ci` in a temp dir through a green
     simulator build; it pins the toolchain (Xcode 26.2 17C52, Swift 6.2.3, XcodeGen 2.44.1, Node 25,
     tsx 4.23), the six font URLs with SHA256s, the parity contract and its openness policy, what is
     deliberately **not** shared (the session reducer and all presentation), rule #1 (all project
     config lives in `project.yml`; the `.xcodeproj` and Info.plist are generated), the
     kill-and-relaunch check, and the six **Founder steps** of §7 including the blocking device
     haptics pass.
  6. `docs/APPSTORE.md` carries §8 verbatim — metadata, the amended Notes for Review, the age-rating
     answers with the profanity grep result, the privacy-policy blocker, and the screenshot plan.
  7. **Visual defects found in the screenshot gate are filed as a list against the owning ticket, not
     fixed here.**

---

### Parallel stages

| stage | tickets | note |
|---|---|---|
| **0 · handshake** | C1 (first hour) | `schema.ts` is committed and its path posted before anything else. |
| **1** | **C1 · C2** | C2 codes its models against the frozen `schema.ts` while C1 builds the exporter; C2's decode tests go green when C1's first export lands. |
| **2** | **C3 · C4 · C6** | Three agents, no shared file. C6 needs only C2's `Package.swift` + models. |
| **3** | **C5 · C7** | C5 needs C3+C4; C7 needs C6. |
| **4** | **C8 · C9 · C10** | Three agents, no shared file. |
| **5** | **C11** | The gate. |

Critical path: C1 → C2 → C3 → C5 → C8 → C11 (6 stages). Estimated **18–20 agent-days**, ~9–11
calendar days at three parallel agents.

### The minimal simulator-playable set

**C1 · C2 · C3 · C4 · C5 · C6 · C7 · C8.** That is: exported content and fixtures → decoded models →
a parity-proven engine → the reducer → the app shell with tokens and persistence → primitives → the
play loop. Entry is C6's `#if SENTRY_QA` "start Shift 1" jump, so **C9 (the Hub) is not required to
play**. What this set delivers: launch → briefing → case → pull sources → evidence board → call sheet
→ hold to file → debrief → next alert → shift summary hand-off, with real fonts, real tokens, real
motion and a persisted mid-shift snapshot. What it lacks: the Hub, the rank-up beat, Settings, the
first-run gate, Core Haptics (cues fall back to `.sensoryFeedback` only), and the CI gate.

---

## 11 · Parallel-agent protocol

1. **One shared working tree. No worktrees, no branches per agent.** `paths_owned` in §10 are
   disjoint and exhaustive, so edits never collide. If an agent believes it needs a file it does not
   own, it **stops and reports** — it does not edit it and does not negotiate directly with another
   agent.
2. **Never edit the web tree.** `app/lib/soc/{cases,engine,handoff,types}.ts`,
   `app/lib/career/**`, `app/lib/game/**` and `app/components/soc/**` are read-only for every ticket
   including C1 (**D1**). C1 adds `app/lib/soc/exporter/` and nothing else under `app/`.
3. **Run only your own targets.**
   - Package tickets (C2–C5) run `swift test --package-path ios/SentryCore` and may
     `--filter` to their own suite while iterating, but must run the whole suite before finishing.
   - App tickets (C6–C10) run `xcodegen generate --spec ios/project.yml` then
     `xcodebuild build -project ios/SentrySOC.xcodeproj -scheme SentrySOC -destination 'platform=iOS Simulator,id=C2136147-45C8-42DD-8E3A-EDE974B97154'`.
     Only C6 and C11 run `xcodebuild test`.
   - C1 runs `npm test`, `npx tsc --noEmit` and `npm run build`.
   - Nobody runs `make` except C11.
4. **Report foreign failures; do not fix them.** If a test or build failure is in a file the agent
   does not own, re-run once after 60 s; if it still fails, record it in the final report as
   `FOREIGN FAILURE · <ticket that owns the path> · <file:line> · <message>` and continue with your
   own work. Do not "helpfully" patch another ticket's file — that is how a disjoint plan turns into
   a merge conflict.
5. **Regenerating content is C1's job alone.** No other ticket runs `npm run soc:export`. If a
   fixture looks wrong, report it; do not regenerate it, because a regeneration that blesses a bug is
   exactly failure mode X3.
6. **`Package.swift` and `project.yml` are written once, by C2 and C6, and declare everything on day
   one** — including targets and directories that do not exist yet. No later ticket edits either
   file. If a ticket needs a new source directory, it just creates it: both files use whole-tree
   recursive paths.
7. **No agent edits `package.json` except C1.** An agent needing a dependency reports it; C2–C11 need
   none, and `SentryCore` has zero remote dependencies by design.
8. **No git.** Agents do not commit, branch, stage, stash, rebase or push. The lead commits
   checkpoints between stages with the founder's agreement.
9. **Do not touch the protected Cloudflare pipeline:** `next.config.ts`, `open-next.config.ts`,
   `wrangler.jsonc`, `app/api/**`. CI asserts this against the merge base.
10. **Copy voice for anything new and player-facing:** terse, senior analyst, second person, no
    emojis, glyphs only. Reuse existing strings verbatim wherever this spec says "lifted". Never
    state a salary, pay band or hiring claim; never describe a runnable procedure; keep every log
    line fabricated. When in doubt, use the existing string and report the doubt.
11. **Screenshots are evidence, not decoration.** Any ticket that ships a player-facing surface
    captures it on the booted simulator and states in its report what it looked at. The founder's
    aesthetic bar is verified by looking, not by a green build.
12. **Final report format** (every ticket): what shipped · the exact commands run and their result ·
    `FOREIGN FAILURE` lines · anything deliberately left undone with the reason · any proposed change
    to a frozen contract (`schema.ts`, `Package.swift`, `project.yml`) as a *request to the lead*,
    never as an edit.
