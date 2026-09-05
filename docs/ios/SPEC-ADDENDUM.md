# SENTRY — SOC · Swift spec addendum (binding amendments)

Resolves the critic's 7 blockers + 11 should-fix against `SPEC.md` (the native SwiftUI
spec). Where this file and `SPEC.md` disagree, **this file wins**. Lead decisions, 2026-09-05.

## 0. Document map (resolves B2)
All design documents now live in the repo under `docs/ios/`:
- `docs/ios/SPEC.md` — the native SwiftUI architecture spec (was `ios-swift-spec.md`).
- `docs/ios/SPEC-ADDENDUM.md` — this file.
- `docs/ios/DESIGN.md` — the carried-over product design: §2 Information architecture (state
  machine, layout, every screen's wireframe, motion, haptic cue table, colour/type tokens),
  §3 Shift 4 handoff re-voice + ladder math, §4 content (campaign + daily constraints),
  §6 App Store package, §7 risks — **same section numbers as the spec cites** — plus
  Appendix A (the 17-action machine, `VIEW_RESULT`/`ACK_FIRSTRUN`, daily `dailyDoneOn`
  hook, guardrail regexes, `LADDER_COPY` re-voice) lifted from the earlier addendum §C/§F/§G.
  Its former §1/§5/§8/§9 (Vite/Capacitor build, tickets) are obsolete and omitted.
- `docs/DECISION-soc-taxonomy.md` — the verdict taxonomy decision (already committed).
Wherever `SPEC.md` says "`ios-design-spec.md` §N" read `docs/ios/DESIGN.md` §N; wherever it says
"addendum §C/§F/§G" read `DESIGN.md` Appendix A. These docs are owned by **C11** for edits.

## 1. Blockers

- **B1 · `requiresRedRun` on iOS.** The exporter's blue-only override (`blueOnly.ts`) sets
  `requiresRedRun: false` on EVERY exported shift and re-voices `handoff-shift.note` (currently
  "…run a red-seat mission to open it") to the seat-neutral line from `DESIGN.md` §3.2. Schema keeps
  the field (the web is the other consumer). `ContentTests` asserts
  `content.shifts.allSatisfy { !$0.requiresRedRun }` and
  `CareerRules.isUnlocked(CareerState(standing: 160), shift5) == true`; `daily`-kind shifts too.
- **B3 · Age-rating grep.** `grep -inE '\b(damn|shit|fuck|hostage|weapon)\b|\bkill(s|ed|ing)?\b'`
  over the exported `copy.json` + `content.json` + `ios/SentrySOC/Sources/**/*.swift`, with a
  committed allowlist `ios/scripts/profanity-allow.txt` (one literal line per accepted hit, e.g.
  `don't kill the rule that catches the real thing`). The guard fails only on unlisted hits and
  prints them. Owned by C11.
- **B4 · Pay-figure guard.** Regex is
  `/\$\s?\d|\bsalar(y|ies)\b|\bper year\b|\bpay\b\s*(range|band)|\b(USD|EUR|PLN)\b/i`.
  Applied by the drift guard to the exported bundle (C1) AND by `verify.sh` to
  `ios/SentrySOC/Sources/**/*.swift` (C11).
- **B5 · `tsx` dependency.** C1 adds `"tsx": "4.23.13"` to `devDependencies` (exact) and commits
  the lockfile. C1 acceptance #7's clause about dropping `@capacitor/*`/`@fontsource*` is DELETED
  (already removed in commit 328de55).
- **B6 · Composition without cross-ticket edits.** C6 ships, in `Sources/Services/`:
  ```swift
  // ScreenRegistry.swift (C6)
  @MainActor final class ScreenRegistry { static let shared = ScreenRegistry()
    var play: (any PlayScreenFactory)? ; var meta: (any MetaScreenFactory)? ; var haptics: any HapticsSink = NoopHaptics() }
  protocol PlayScreenFactory { @MainActor func view(for phase: Phase, model: GameModel) -> AnyView
                               @MainActor func sheet(for view: ViewID, model: GameModel) -> AnyView? }
  protocol MetaScreenFactory { /* same shape for hub / complete / milestone / settings / firstRun / kit */ }
  protocol HapticsSink { @MainActor func play(_ cue: SocCue); @MainActor func setHeartbeat(_ plan: HeartbeatPlan?) }
  struct NoopHaptics: HapticsSink { … }
  // Composition.swift (C6)
  enum Composition {}
  protocol ScreenInstaller { static func installPlay(into r: ScreenRegistry)
                             static func installMeta(into r: ScreenRegistry)
                             static func installHaptics(into r: ScreenRegistry) }
  extension ScreenInstaller { static func installPlay(into r: ScreenRegistry) {}   // no-op defaults
                              static func installMeta(into r: ScreenRegistry) {}
                              static func installHaptics(into r: ScreenRegistry) {} }
  extension Composition: ScreenInstaller {}
  ```
  `SentrySOCApp.init` calls `Composition.installPlay(into:)`, `installMeta`, `installHaptics`.
  `PhaseHost` renders a labelled placeholder (`PlaceholderScreen(name:)`) whenever the factory is
  nil. Later tickets **shadow** the defaults from their OWN directories — a concrete-type extension
  wins over the protocol default at the static call site:
  `Screens/Play/PlayComposition.swift`: `extension Composition { static func installPlay(into r: ScreenRegistry) { r.play = PlayScreens() } }` (C8);
  `Screens/Meta/MetaComposition.swift` (C9); `Haptics/HapticsComposition.swift` (C10).
  C6 acceptance adds: "with no other ticket present, the app builds and `PhaseHost` shows
  placeholders for every phase"; C8/C9/C10 acceptance adds "my `*Composition.swift` exists and
  `Composition.installX` resolves to it (verified by a DEBUG log line on install)".
  **`ShiftSummaryView` moves to C8** (`Screens/Play/ShiftSummaryView.swift`) so the minimal set
  C1–C8 ends on a real summary; C9 keeps Hub / RankUp / Settings / FirstRun / Kit / Licences.
- **B7 · Release signing + QA guard.** `project.yml` Release config sets `CODE_SIGNING_ALLOWED: NO`,
  `CODE_SIGNING_REQUIRED: NO` (the founder's archive overrides `DEVELOPMENT_TEAM`/signing on the
  command line or in Xcode — documented in `docs/IOS-BUILD.md`). The release guard builds
  `-configuration Release -destination 'generic/platform=iOS Simulator'` and greps the binary for
  the launch-argument literal **`SentryQAScreen`** (not the compilation condition), with a positive
  control: the Debug binary MUST contain it, else the guard fails as "grep broken".

## 2. Should-fix (all accepted)

- **S1 · Chrome copy.** `ExportedCopy.chrome: Record<string, string>` (~60 keys: "Why",
  "The decisive findings", "Learn it for real", coverage line with `{n}`/`{m}`, blind/thorough
  clauses, "Next alert ▸"/"End shift ▸", "Make the call", "investigate first", empty-board state,
  StatTile labels, "Shift complete · 16:00 handover", "Payout", Hub eyebrows, "Buy · ¢{cost}",
  Settings/About/Abandon/RankUp eyebrows, etc.) authored in `app/lib/soc/exporter/chrome.ts` —
  new iOS copy, NOT SHA-pinned, lifted verbatim from `SocConsole.tsx` where the string exists there.
  Routed through the B3/B4 guards. Grep rule becomes: **no string literal containing a letter in
  `Sources/Screens/**` or `Sources/Components/**` outside `#Preview` blocks and
  `accessibilityIdentifier`/`Image(systemName:)`/`Font.custom` arguments** — `verify.sh` implements it.
- **S2 ·** `handler.templates: Record<string, { sender: "vale" | "mercer"; subject; body; tone }>`.
- **S3 ·** The exporter WRAPS `inboxFor`: `messagesAll = inboxFor(c, ev)`;
  `messagesBlueOnly = inboxFor(c, ev).filter(m => m.id !== "tip-redrun").slice(0, 4)` (cap re-applied
  after the filter). `handler.json` rows carry both; Swift `inboxFor(features: .all)` asserts the
  first, `.iOS` the second. Scenario count corrected to 13 (+1 new: a fresh career at standing 0 with
  a rankUp event) → 14 distinct.
- **S4 ·** `coachSteps[].advance: "on-first-source-pulled" | "button" | "terminal"`; SHA-pinned
  overrides: step-1 "click it" → "tap it", step-2 body "Pull more logs on the left" → "Pull more logs
  from SOURCES; findings land under EVIDENCE" (both added to the D4 override list).
- **S5 ·** `ExportedCopy.severityMeta: Record<string, { label: string; tone: Tone }>` (from
  `SEVERITY_TONE`) and `handlerToneMeta` (from `MSG_TONE`), each with a documented `fallback` tone
  key; `LenientSchemaTests` asserts an unknown severity renders with the fallback tone.
- **S6 ·** `scoring.json` grows to ≥12 rows covering: `keyTotalSum == 0 → investigationRate 1` and
  `investigationOf(total 0) == "thorough"` (via `SyntheticShiftFile` with inline `keySourceIds: []`
  cases); a `results` entry whose `caseId` is not in the map (Swift must SKIP, not crash); the five
  `clean` conjuncts isolated (accuracy exactly 0.8 → clean vs one step below → rough; 1 blind call →
  rough; noise LOCKDOWN → rough; 1 missed → rough with breach 30/ALERT); a meter overflow run (4
  missed → 120 clamped to 100); `applyCall` on an already-present caseId (replace in place, keep
  position); a duplicated id in `queriedSourceIds` (counted twice — documented invariant). Drift-guard
  check #10: every `ShiftGrade` value and every `InvestigationQuality` appears ≥1× across fixtures.
- **S7 ·** C3 #2 becomes: "no occurrence of any of the 29 tuning values as a numeric literal in
  `Engine/*.swift` (allow `0` and `1` only where documented)". C6 #2 pins `-target SentrySOC`.
  C6 #1 "no white flash" becomes: `plutil -p` of the built Info.plist shows
  `UILaunchScreen.UIColorName == "LaunchGround"` and the asset catalog defines `LaunchGround` =
  `#010409`. Drift-guard check #9 (`git diff` of the protected web dirs) MOVES out of vitest into
  `ios/scripts/verify.sh` + the CI `guards` job using `git merge-base origin/main HEAD`.
- **S8 ·** `ExportedTuning` fields are typed `number` (not literals). There are **29** tuning numbers:
  trace 5 · bpm 4 · timeBudgetDefault 1 · grade 8 · shift 2 · career 6 · heartbeat 3.
  `TuningExpectationTests` enumerates exactly those 29.
- **S9 ·** `ExportedDaily.shiftTemplate: { idPrefix: string; label: string; note: string | null }` with
  `{date}` interpolation; `ContentPack.dailyShift(on:)` builds the `ExportedShift` from it.
- **S10 ·** Pins are bidirectional: for each pinned region assert
  `segments.map(s => s.text).join("")` equals the JSX slice with tags stripped, entities decoded
  (`&apos;` `&ldquo;` `&rdquo;` `&amp;`), whitespace normalised. Only tone runs stay hand-authored.
- **S11 ·** Drop `UIStatusBarStyle` (dead under view-controller-based appearance). Assert
  `copy.meters` deep-equals `intro.meters` in the drift guard (or derive one). CI resolves the
  simulator UDID via `xcrun simctl list devices available -j | jq` (name match "iPhone 17 Pro Max",
  else first available iPhone) with the hardcoded UDID as fallback.

## 3. Ticket ownership corrections
- **C6** adds `ios/SentrySOC/Sources/Services/ScreenRegistry.swift`, `…/Services/Composition.swift`,
  `…/Services/PlaceholderScreen.swift` (already inside its owned `Services/` dir).
- **C8** adds `Screens/Play/ShiftSummaryView.swift` and `Screens/Play/PlayComposition.swift`.
- **C9** adds `Screens/Meta/MetaComposition.swift`; loses `ShiftSummaryView`.
- **C10** adds `Haptics/HapticsComposition.swift`.
- **C11** owns `docs/ios/**` for edits (the lead commits the initial versions), plus
  `ios/scripts/profanity-allow.txt`.
- Minimal simulator-playable set: **C1–C8** (entry via C6's `#if SENTRY_QA` "start Shift 1").

## 4. Stage plan for the agents (sequential where a contract must exist first)
Stage 1: **C1** (whole ticket; `schema.ts` first). Stage 2: **C2**. Stage 3: **C3 ‖ C4 ‖ C6**.
Stage 4: **C5 ‖ C7**. Stage 5: **C8 ‖ C9 ‖ C10**. Stage 6: **C11**. Each ticket runs
implement → independent review → fix; the lead commits + pushes a checkpoint after every stage.

## 5. Stage-3 rulings (lead, 2026-09-05 — after C1–C6 reviews)

- **R1 · Blue-only inbox (DV-7).** The exporter keeps WRAPPING the real engine: for the iOS list call
  `inboxFor({ ...c, redRunsDone: Math.max(1, c.redRunsDone) }, ev)` — the engine itself then never
  emits `tip-redrun`, BEFORE its own 4-message cap — and post-process only the two re-voicings
  (`ev-unlock-handoff-shift`, the t2 `ev-rankup`) by swapping in the exported `*-blue-only`
  templates (sender `vale`). `messagesAll` stays the raw `inboxFor(c, ev)`. The exporter asserts, per
  scenario, that `messagesAll` and `messagesBlueOnly` differ ONLY by the absence of `tip-redrun` and
  those two re-voicings (report any other diff). Swift `.iOS` implements the same rule (treat
  `redRunsDone` as ≥ 1 for selection, then re-voice). handler.json + shift-runs.json regenerated;
  `GoldenInboxTests` updated to the new fixture. Addendum S3 is superseded by this ruling.
- **R2 · `Tone` gains `"orange"`** (schema.ts union + exporter); `severityMeta.High.tone = "orange"`.
  Swift `Tone` is lenient so no model change; C7's `Theme` maps `orange` (the HUNT hue).
- **R3 ·** `ExportedDailyTemplate` and `DAILY_TEMPLATE` gain `requiresRedRun: false` so
  `dailyShift(on:)` is a pure field copy.
- **R4 ·** Coach step 2 body (approved): "Findings land here — the evidence, not the tool's 'High'
  guess. Not sure yet? Pull more logs from SOURCES. When you can justify a call, hit Got it."
- **R5 ·** `daily.test.ts` totality test steps by 1 day over 2026–2030 and asserts `n > 1800`.
- **R6 ·** `tuning.handler = { inboxCapacity: 4, redRunNudgeStanding: 90 }` → **31** tuning numbers;
  `Inbox.swift` reads both from the bundle; `TuningExpectationTests` enumerates 31.
- **R7 ·** `SOCEngine.content` stays `internal`; the app threads its own `ContentPack` (GameModel
  already holds it). SPEC §3.3 is correct as written.
- **R8 · Doc corrections for C11:** SPEC §1/§3.2 Engine file list is `TraceOps.swift · Grading.swift ·
  ShiftOps.swift · Scoring.swift` (basename must not collide with `Model/Trace.swift` in one target);
  §3.5 adds DV: `rankFor` traps on an empty ladder and `ContentPack.bundled` traps on decode failure
  (corrupt bundle = programmer error); §6 font roster is the six faces actually shipped (see R11);
  `applyCall` grades twice on purpose (literal parity) — one doc-comment line in `ShiftOps.swift`.
- **R9 · C5 scope extended (C6 is complete, nobody else touches these paths).** C5 additionally owns
  `ios/SentrySOC/Sources/State/` (delete `SessionStubs.swift`; switch `GameModel`/`EffectRunner` to
  `SentryCore` Session/Feel types; `.resume(SessionState)` carries the snapshot THROUGH the reducer —
  no direct `session =` assignment in the model; `buy()` compares `rules.buyKit` before/after and on
  refusal fires `denied` and persists nothing; `.clearSession` uses a monotonic generation token so a
  suspended write can't resurrect a cleared snapshot; delete dead `resetPerformedLog()`; the reducer
  emits `.markDailyDone` and the model stops stamping it itself), `ios/SentrySOC/Sources/App/PhaseHost.swift`
  (read the model's registry, not `ScreenRegistry.shared`), `ios/SentrySOC/Sources/Services/QAJump.swift`
  (derive `first-shift` / first source id from `ContentPack`; DEBUG-assert they resolve),
  `ios/SentrySOC/Sources/Services/Flags.swift` (remove unused `Key.init(_ setting:)` /
  `hasSeenOnboarding` or use them), `ios/SentrySOC/Sources/Services/SafariView.swift` (one comment
  naming C9 as the consumer), and `ios/SentrySOC/Tests/` (delete `SessionStubTripwireTests.swift`; fix
  `EffectScheduleTests.oneSendOnePass` to remove its persistent domain). C5 acceptance adds: "the app
  target builds against `SentryCore` Session/Feel with `SessionStubs.swift` gone, and
  `xcodebuild test -only-testing:SentrySOCTests` is green".
- **R10 · Ratified:** `PlayScreenFactory.view(for:model:) -> AnyView?` and
  `MetaScreenFactory.view(for:model:) -> AnyView?` (nil = "not mine"; PhaseHost falls through play →
  meta → placeholder); `project.yml` Resources `excludes: ["FONTS.md"]`.
- **R11 · Font roster (as shipped):** IBM Plex Mono Light/Regular/Medium/SemiBold + Space Grotesk
  Regular/Medium (SemiBold Grotesk does not exist upstream). C7 binds Plex **Light** to the quiet
  log/meta style and Plex **SemiBold** to the stamp and grade numerals, so no face is dead.
- **R12 · Pay-figure guard in `verify.sh` (C11):** the `\$\s?\d` alternative must not match Swift
  closure arguments (`$0`, `$1`) — run the guard over STRING LITERALS extracted from Swift sources
  (`grep -o '"[^"]*"'`) plus the exported JSON, never over raw Swift.
- **R13 ·** Remove `Tests/CareerTests/.gitkeep` and `Tests/EngineTests/.gitkeep` (F1);
  `Tests/SessionTests/.gitkeep` (C5).
- **F1 · follow-up ticket (runs BEFORE C5/C7):** implements R1–R6, R8's doc comment, R13. Paths:
  `app/lib/soc/exporter/` · `ios/SentryCore/Sources/SentryContent/` · `ios/SentryCore/Sources/SentryFixtures/` ·
  `ios/SentryCore/Sources/SentryCore/Career/Inbox.swift` · `ios/SentryCore/Tests/CareerTests/` ·
  `ios/SentryCore/Tests/EngineTests/TuningExpectationTests.swift` · `ios/SentryCore/Sources/SentryCore/Engine/ShiftOps.swift` (doc comment only).
  Acceptance: `npm run soc:export` idempotent, `npm test`, `swift test` green; drift guard green;
  fixtures show the R1 property; 31 tuning numbers.
- **Simulator driving for screen tickets:** the app is `pl.oumm.sentry.soc` on simulator
  `C2136147-48…` (see SPEC §7). Launch straight to a screen with
  `xcrun simctl launch <UDID> pl.oumm.sentry.soc -SentryQAScreen <name>` (Debug build), then
  `idb screenshot --udid <UDID> <out.png>`; drive with `idb ui tap <x> <y> --udid <UDID>`,
  `idb ui swipe`, `idb ui text`, and read the accessibility tree with `idb ui describe-all --udid <UDID>`.
  Every screen ticket LOOKS at its screenshots (Read the PNG) before reporting.
