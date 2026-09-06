# SENTRY — SOC · Feel pass (F2) — proposal for founder sign-off

**Status:** PROPOSAL, 2026-09-06. Not implemented. Founder feedback that triggered it:
*"wizualnie spoko, brak dynamizmu — wygląda jak wykład o SOC, wszystko naraz, zgaduj co czytać."*

**Diagnosis.** The screens inherited the web SOC's *dashboard* layout: alert, six sources with
their questions, coach and dock all appear at once; a source pull is a 600 ms progress bar; the
meters only move at the verdict; there is no sound. Nothing *arrives*, nothing *happens between
decisions*. The engine (decisions → consequences → debrief) is right; the **direction** is missing.

**Contract.** Everything below is presentation. `SentryCore` grading, content, fixtures and the
TS↔Swift parity contract do not change. New player-facing strings are authored in the exporter
(`chrome.ts`), never as Swift literals. Reduce Motion collapses every sequence to its end state
(sound and haptics stay — D18).

Defaults chosen by the lead (flip any of them): **SFX now** (not v1.1) · **"leads-to" by rule
first**, authored `leadsTo` after a playtest · **no hard timer** — pressure is felt, not scored.

---

## 1. Shift handover — the opening (replaces the static intro card)

| t (ms) | Beat | Sound | Haptic |
|---|---|---|---|
| 0 | Black ground. `SHIFT HANDOVER · 08:00` eyebrow types in (mono, 11 pt), one glyph per 18 ms. | soft room tone fades in (−30 dB) | — |
| 600 | The board slides up: empty rail with 7 slots. | — | — |
| 900 → 900+7×260 | Alerts land one per 260 ms as a **single line each** (`tool severity · alertTitle`); each landing blips the ECG. | `ping` per alert, pitch stepping up slightly | `select` per alert |
| +400 | Vale's ONE line arrives as a message card (typing dots 500 ms → text). Source: `copy.intro` first sentence only; the taxonomy paragraph moves to the coach's first step (see §6). | message `tick` | `commit-soft` |
| +300 | Dock rises: `Clock in ▸`. Meters appear **empty** with their labels only — fear text comes later, when a meter first moves. | — | — |

Tap `Clock in` → cut to black (120 ms) → the first alert arrives (§2). Total ≈ 4.5 s; tap anywhere skips to the end state.

## 2. Alert arrival — every case starts as an event, not a page

| t (ms) | Beat |
|---|---|
| 0 | Previous screen cuts to the ground colour. SystemBar stays. |
| 120 | ECG spikes once (amplitude ×3 for one beat); the **queue pill** increments `1/7 → 2/7`. |
| 260 | **Trigger line only**, in mono, types in over ~700 ms (log voice: `powershell.exe spawned with -EncodedCommand on FIN-WS-04 at 02:14 local — off-hours.`). |
| 1100 | Beat. Then the alert **title** fades in (Grotesk 22 pt) with the `ASSET:` line. |
| 1500 | The severity chip **stamps** in (scale 1.3 → 1, 140 ms) with the detection rule beneath. |
| 1800 | The SOURCES list rises from the bottom, **collapsed** (§3). Dock shows `Make the call` disabled with `investigate first`. |
| 2100 | Coach line (§6) slides in only on shift 1. |

Sound: `arrive` (a short, low pad + click) at 120; `severity` tick at 1500 (pitch by severity: Low soft … Critical sharp). Haptic: `select` at 120, `commit-soft` at 1500. Tap anywhere → end state.

## 3. Sources — collapsed, revealed on touch

- Rows show **name + cost** only (mono, 15 pt). The question is hidden.
- **Tap** = *peek*: the row expands to show the question (Grotesk) and the button `Pull · 10m`. Only one row peeks at a time. Peeking is free.
- **Tap `Pull`** (or long-press the row, 350 ms) = the pull. No confirm dialog.
- Already-pulled rows collapse to a single dim line with a `✓` and the finding count.
- Row order is the authored order; **no reordering**, so the player builds spatial memory.

## 4. The pull — a moment, not a progress bar

| t (ms) | Beat | Sound | Haptic |
|---|---|---|---|
| 0 | Sheet opens at `.height(320)`: `QUERYING · <source>` eyebrow; a **log pane** in mono. | `query-start` (filtered noise burst, 200 ms) | `select` |
| 0 → 1500–2400 | 4–6 fake log lines stream in, one per 280–420 ms (jittered, seeded by case id so it's deterministic): templates from `chrome.query.lines` with `{asset} {source} {n} {window}` placeholders — e.g. `connecting edr://FIN-WS-04 …`, `process tree · 3 h window`, `matching lineage for pid 4412`, `{n} events`. The shift clock in the SystemBar **counts up** the cost (e.g. `0m → 10m`) in sync. | soft `tick` per line | — |
| end | `RESULTS · {n} findings` header; the sheet grows to `.large`. | `resolve` chord (short) | `commit-soft` |
| +0 / +260 / +520 … | Findings land **one at a time** (max 3 before the rest appear together): card slides up 12 pt + fades, weight badge NOT shown (all cards look equal during play). | `land` per card | `finding-land` per card (≤3) |
| after last | If a decisive finding landed: the ECG does one extra beat and the SystemBar band word pulses once. | — | — |

Duration scales with cost: `cost ≤ 8m → 1.5 s`, `10m → 2.0 s`, `≥ 12m → 2.4 s`. Second and later pulls in the same case are 25 % faster. Tap the log pane → skip to results.

## 5. Pressure you can feel — without changing the score

- **Time pulse.** During `investigating`, the ECG/heartbeat status shown is
  `max(engineStatus, timeStatus)` where `timeStatus` maps shift time used vs the 90-minute budget:
  `< 50 % → CALM`, `50–75 % → ALERT`, `75–100 % → HUNT`, `> 100 % → LOCKDOWN`. **Presentation only** —
  `scoreShift` is unchanged; the heartbeat haptic follows the same rule (so the desk starts to
  *thump* when you are burning the shift). Board sheet shows `TIME 62 / 90m`.
- **Live board.** Every ~25–40 s of real time while investigating (seeded, capped at the remaining
  queue), one *upcoming* alert on the board gets its severity revealed with a `ping` + ECG blip and the
  queue pill flashes. Nothing changes in the queue order or content — the desk simply feels live.
- **Fear text arrives with the first delta.** Meter captions (`a real threat you closed is dwelling
  undetected`) appear the first time that meter moves, as a typed line, then stay.

## 6. Vale — a voice in your ear, not a panel

- Coach steps become **one sentence each**, delivered as a message card that slides in from the
  left rail with typing dots (500 ms) → text. Three steps stay; the taxonomy paragraph (the DEF-A
  definition with colour runs) becomes the *first* card of shift 1, shown **before** the first
  alert arrives, and is reachable later from Settings → "Read the rules again".
- Interjections (rule-based, no new content): on the first pull of a shift-1 case: `Good — now
  read what it says, not what the tool guessed.`; when the player opens the call sheet with only a
  noise-weight finding on the board: `You're calling on one card. Your call — but I'd pull one more.`
  Both strings live in `chrome.ts`. Each fires at most once per shift.

## 7. Leads-to — the board points at the next question (cheap rule first)

After each pull, if a **decisive** or **supporting** finding landed, the not-yet-pulled sources that
are in the case's `keySourceIds` get a **soft pulse** (one 600 ms glow on their row's left rule) and a
mono caption `worth a look` — once, not persistent. It nudges without answering (the rule fires on any
key source, including the ones that would refute the player's hunch). If the founder later wants
authored precision, `evidence[].leadsTo: sourceId[]` in the exporter replaces the rule with zero UI
change.

## 8. The call — a cut, not a transition

| t (ms) | Beat | Sound | Haptic |
|---|---|---|---|
| 0 | Hold-to-file completes. Ring fills. | rising `hold` tone under the ring | `hold-tick` ×3 |
| 0 | **Cut to black.** SystemBar hides. | silence (room tone ducks) | `file` (heavy) |
| 450 | The **stamp slams**: rotated −3°, scale 1.4 → 1 over 180 ms, with the disposition text. | `stamp` (paper + thud) | — |
| 900 | Ground returns to the panel colour; `GOOD CALL` / `RIGHT VERDICT` / `WRONG CALL` eyebrow fades in. | `verdict-good` / `-off` / `-wrong` chord | `verdict-*` |
| 1200 | `TRUTH:` chip reveals (flip 200 ms). | — | — |
| 1500 | Meters sweep to their new values with count-up; **breach thud** if `breachDelta ≥ 30` (screen edge flashes rose once). | `breach-thud` | `breach-thud` |
| 2100 | `WHY` and the decisive findings fade in, staggered 80 ms. Dock rises last. | — | — |

Tap anywhere from 450 ms onward → end state. Reduce Motion: stamp appears instantly at 0, everything else at 0; sound and haptics unchanged.

## 9. Sound design (SFX now; no music)

Category `AVAudioSession.Category.ambient` (respects the ringer switch and mixes with the player's own music — this is a reading game; **the haptics carry the tension when muted**). All assets short (≤ 600 ms), mono, 44.1 kHz, authored to a common −16 LUFS peak; a single `SoundBank` enum maps `SocCue` → file, so cues and sounds stay one vocabulary:

| Cue | Sound character |
|---|---|
| `arrive` (new) | low pad + click, 400 ms |
| `select` | dry click, 30 ms |
| `query-start` (new) | filtered noise burst, 200 ms |
| `tick` (log line, new) | tiny click, 20 ms |
| `finding-land` | soft mallet hit, 120 ms; three pitches cycling |
| `commit-soft` | short double click |
| `file` | paper slide + thud, 350 ms |
| `stamp` (new) | ink stamp on paper, 300 ms |
| `verdict-good` / `verdict-off` / `verdict-wrong` | 2-note chord: major / suspended / minor 2nd, 500 ms |
| `breach-thud` | sub thud, 400 ms |
| `beat-lub` / `beat-dub` | **haptic only** by default; optional low thump under −24 dB behind a Settings toggle ("Heartbeat sound") |
| `rankup` | rising 3-note figure, 700 ms |
| `denied` | dull knock, 120 ms |
| `ping` (board, new) | sonar ping, pitch up per alert, 300 ms |
| Room tone | −30 dB filtered noise loop while a shift is open; ducks −12 dB for 600 ms on `file`. |

Settings gains two toggles: **Sound** (default on) and **Heartbeat sound** (default off). Source
files: generated procedurally (a small Swift/`AVAudioEngine` synth script committed under
`ios/scripts/render-sfx.swift`) so there is no licensing surface — no downloaded samples.

## 10. What gets removed / shortened

- The three-paragraph coach body → one sentence per step (§6).
- Source questions from the default list state (peek reveals them, §3).
- Detection rule + severity chip shown at t=0 → they arrive in sequence (§2).
- Static fear captions → arrive with the first delta (§5).
- Nothing is removed from the debrief; its *order* is now paced (§8).

## 11. Verification (motion can't be judged from a still)

- `ios/scripts/record.sh`: `xcrun simctl io <udid> recordVideo --codec h264 out.mp4` around each
  sequence, then frames extracted every 100 ms (via `ffmpeg` if installed, else `simctl` burst
  screenshots at 10 Hz) into `docs/screenshots/ios/feel/<sequence>/f-000.png …`. The reviewer reads
  the frame strips and checks the timelines above (±60 ms).
- A `SequenceTests` target unit-tests the pure timeline generators (every sequence is a pure
  function `[Beat]` with times, so the numbers above are asserted, not eyeballed).
- Full Shift 1 replay: score identical to `shift-runs.json` demo-complete (nothing in the engine
  moved).

## 12. Open questions for the founder

1. SFX now (default) or v1.1?
2. Leads-to by rule (default) or authored `leadsTo` straight away?
3. Any hard timer? (default: none — the time pulse is felt, not scored)
4. Room tone on by default, or off (SFX only)? (default: on, −30 dB)

---

## 13. F2a implementation notes (2026-09-06)

**What F2a was:** the *spine* of the feel pass — the pure timelines, the cue vocabulary,
the sound bank, the settings and the verification tooling. The screens that play the
sequences (§1/§2/§4/§8's pixels, §3's collapsed source rows, §6's message cards, §7's
pulse) are a separate ticket; everything below is in the tree and green today.

### Landed

| Deliverable | Where |
|---|---|
| §1/§2/§4/§8 as pure `[Beat]` generators, §5's `timeStatus` / `feltStatus` / live-board schedule | `ios/SentryCore/Sources/SentryCore/Feel/Sequences.swift` |
| Six new cues — `arrive` `queryStart` `tick` `stamp` `ping` `landCard` | `Feel/SocCue.swift` (the original 16 untouched) |
| Chrome key roster for the new copy (so no screen writes `"queryLine\(i)"`) | `Feel/FeelCopyKeys.swift` |
| Every FEEL.md number asserted, 24 tests | `Tests/SessionTests/SequenceTests.swift` |
| `chrome.queryHeader` · `queryLine1…6` · `queryWindow` · `queryResults` (plural) · `valeFirstPull` · `valeThinCall` · `sourceWorthALook` · `settingsSound` · `settingsHeartbeatSound`; coach bodies cut to one sentence each | `app/lib/soc/exporter/chrome.ts`, `copy.ts` |
| 27 procedurally-synthesised assets, deterministic, RMS −16 dBFS with a −1 dBFS ceiling | `ios/scripts/render-sfx.swift` → `ios/SentrySOC/Resources/Sounds/*.wav` |
| `SocCue` → file, incl. pitch variants and the documented reuse | `ios/SentrySOC/Sources/Sound/SoundBank.swift` |
| `AVAudioEngine` service: `.ambient`, 6-voice pool, room-tone loop at −30 dB with a −12 dB / 600 ms duck on `file` | `Sources/Sound/SoundService.swift` |
| Sound + Heartbeat-sound switches, `replayMuted` | `Sources/State/Feel.swift`, `Screens/Meta/SettingsView.swift` |
| The **audible heartbeat** — the loop as a schedule of thumps, bounded by the same 40 s wall | `SentryCore/Feel/Heartbeat.swift` (`heartbeatSoundSchedule`), `Sound/SoundService.swift`, fanned out by `Haptics/HapticsEngine.setHeartbeat(_:)` |
| One call site → haptic **and** sound | `Sources/State/EffectRunner.swift` (`.haptic` arm), `GameModel.feel(_:variant:)` |
| Recorder: 100 ms frames at 1x + a `strip.png` contact sheet + a manifest, ffmpeg optional | `ios/scripts/record.sh` → `docs/screenshots/ios/feel/<sequence>/` |

`project.yml` needed **no edit**: `SentrySOC/Resources` is a whole-tree resource path and
the copy phase flattens, so `Resources/Sounds/select.wav` reaches the bundle as
`select.wav` — verified in the build log and by `SoundService` decoding all 27 at launch.

### Decisions and deviations (each one a place the document and the tree differ)

1. **The two switches are not `SettingKey`s.** §4.3 pins `UserDefaults` at *exactly
   five* launch-critical flags and `Flags.set(rawKey:)` trips an assertion on a sixth.
   Sound lives in its own observable, `State/Feel.swift`, with its own keys
   (`sentry.sound`, `sentry.heartbeatSound`). The reducer decides what the game does;
   whether the desk makes a noise is not that.
2. **Sound is fired *before* the haptics gate, not behind it.** `hapticsEnabled()` is the
   *Haptics* switch, and a player who turned haptics off did not ask for silence. The two
   channels therefore have two gates — verified on the simulator: with Sound off the
   trace reads `sound select muted (replay=false sound=false)` while `cue select via
   sensoryFeedback` still fires.
3. **Three cues are sound-only** (`SocCue.soundOnly` = `tick`, `stamp`, `landCard`).
   §9 gives them an audio row and a `—` in the haptic column. `HapticsEngine` traces them
   as `route: soundOnly` rather than asserting on a missing route.
4. **§4's `resolve` chord is `commitSoft`.** §4's sound column names a `resolve`; §9's
   asset table — the authoritative list — has no such row. The results header therefore
   takes `commit-soft`. If a distinct chord is wanted, it is one `Asset` in the synth.
5. **§4's jitter is scaled onto the cost window.** "One per 280–420 ms" and "duration
   scales with cost" cannot both be literally true of the same pane, so the *shape* of
   the stream is the jitter (n+1 seeded gaps, ratios preserved) and its *length* is the
   cost. A 1125 ms repeat pull still streams 4–6 lines.
6. **§1 chains its `+400` / `+300` from the previous row's end**, and the message row's
   end is its 500 ms of typing dots. Seven alerts ⇒ dock at 3920 ms, end state at
   4180 ms — the "≈ 4.5 s" of §1, and the only number in the document written with a `≈`.
7. **`rankup` is 700 ms**, past §9's own "≤ 600 ms" headline — because §9's own table
   gives that row 700 ms. The cap is enforced per asset and this is the one exception
   besides the room tone, which is a loop and not a cue (4.0 s, equal-power wrap so the
   seam is inaudible).
8. **−16 LUFS-ish is RMS, not BS.1770.** Each asset is normalised to −16 dBFS RMS then
   ceilinged at −1 dBFS. Short clicks (`tick`, `select`) land nearer −22 dBFS RMS because
   the ceiling wins — correct, and what stops a 20 ms transient clipping.
9. **Coach step 2 keeps R4's exact phrase.** The one-sentence rewrite still contains
   "Pull more logs from SOURCES" and still offers rather than orders, because the drift
   guard asserts both — a shortening is not a licence to replace a ruling.
10. **The taxonomy paragraph was not deleted.** It is `copy.intro.taxonomy`, with its
    colour runs, and `ShiftIntroView` already prints it before the first alert — so
    cutting coach step 3 to one sentence loses no teaching. §6's "reachable later from
    Settings" row is F2b's.
11. **`arrivalSequence(withCoach:)`, `pullSequence(…findingCount:hasDecisive:)` and
    `callSequence(breachDelta:verdict:)`** carry defaulted extra parameters, so the
    signatures the ticket names remain legal calls while the sequences can still emit
    the beats §2/§4/§8 describe.
12. **`record.sh` falls back to a burst when the capture is static.** `simctl
    recordVideo` is variable-frame-rate: a screen that never changes writes ONE frame
    with a 0.07 s duration, and `fps=10` over 0.07 s is one frame however long the wall
    clock ran. A real sequence produces frames and keeps the accurate video path.
13. **Frames are written at 1x (440 px), not at the @3x capture**, and the artefact a
    reviewer opens is `strip.png` — every frame six to a row, left to right at 100 ms a
    step. A strip answers "which beat landed on which frame", and that question does not
    need 500 KB a frame. The QA relaunch also happens *inside* the recording, so frame 1
    is the launch rather than its aftermath.
14. **The audible heartbeat is a schedule, not a loop, and it is armed by
    `HapticsEngine.setHeartbeat(_:)`.** The hand hands one pattern to a
    `CHHapticAdvancedPatternPlayer` with `loopEnabled` and the OS beats it forever;
    an `AVAudioPlayerNode` schedules *buffers*, so the ear has to be told when each
    thump is. `heartbeatSoundSchedule(plan)` in `SentryCore` writes the whole armed
    run out as a value — 150 hits for HUNT's 536 ms period inside the 40 s wall — and
    `SoundService` walks it with **one** task, sleeping to an absolute instant on the
    continuous clock rather than a relative gap. Both channels are armed from the one
    call that knows which band is beating, so the thump and the buzz can never be on
    different bands, and the wall suspends them together.
15. **The Heartbeat-sound switch therefore rides on the Haptics switch.** §9 makes
    the thump an option *under* a beat ("haptic only by default; optional low thump"),
    and the plan the ear follows is `HeartbeatDirector`'s — which is `nil` when
    `cuesAreLive` is false. With Haptics off there is no heartbeat to make audible.
    Haptics defaults on, and this is the one place where the two-gates rule of #2
    does not apply, because the heartbeat is a *state* and not a cue. What is
    **not** gated on the actuator: the Simulator and every device without a Taptic
    Engine still play the thump, which is how the run below was verified.

### Two bugs the runtime passes caught

`SoundService.play(named:)` looked the buffer up **before** taking a voice — and taking a
voice is what starts the engine, which is what decodes the buffers. The first sound of
every launch was therefore dropped. Found with `-hapticTrace` on
`-SentryQAScreen debrief`, where the verdict chord is the first sound the process ever
asks for (`sound verdict-good dropped (engine unavailable or not decoded)`). The guard
order is now load-bearing and says so.

**The Settings switch was a promise nothing kept** (F2a review, major). `playHeartbeat()`
was reachable only from `play(_ cue:)`'s `if case .heartbeat` arm, and nothing in the app
fires a one-shot `SocCue.heartbeat` — the heartbeat is a *loop*, owned by
`HeartbeatDriver` / `HeartbeatPlayer`. `beat-lub.wav` and `beat-dub.wav` shipped, decoded
at every launch, and were never scheduled: the row drew, the switch moved, and the desk
stayed silent. Fixed by deviation #14. Verified on the Simulator at HUNT with
`-hapticTrace`: `heartbeat sound start HUNT period=536ms 150 beats over 40000ms`, 75
lub/dub pairs at a measured 536.3 ms period, `heartbeat sound suspend` 39.8 s later, and
`heartbeat sound rearm …` on the next pull — while the hand's own line in the same trace
reads `heartbeat start skipped — no haptics engine`. With the switch off: `heartbeat
sound start muted (replay=false sound=true heartbeatSound=false)` and zero beats. The
first cut of the walk slept *relative* gaps and drifted to a 565 ms period — 5 % slow,
two seconds of lag across a run — which is why it sleeps to a deadline.

### What F2b inherits

The generators, the cues, the sounds and the copy are all in place and unit-tested; what
is missing is the *drawing*. `Sequences.handoverSequence(alertCount:)` has no view yet, so
`ShiftIntroView` still renders the static briefing; `arrivalSequence` has no view, so
`CaseView` still shows everything at once; `pullSequence` has no view, so `SourceSheet`
still runs its 600 ms progress bar; `callSequence` has no view, so `DebriefView` still
mounts whole. §3 (collapsed source rows), §5's live board and fear text, §6's message
cards and §7's pulse are likewise unbuilt. Every one of them now has its numbers, its
cues, its sounds and its strings waiting.

---

## 14. F2b implementation notes (2026-09-06)

**What F2b was:** the *drawing*. F2a landed the spine — the pure timelines, the cue
vocabulary, the sound bank, the settings and the recorder — and left every screen
rendering the pre-feel-pass page. F2b plays them: §1 and §2 are sequences now, §3's
sources are collapsed, §4 is a query rather than a progress bar, §5's pressure is
felt, §6 is a voice, §7 points, §8 is a cut, and §10's removals are done.

**Contract, unchanged and re-verified.** `SentryCore` grading, content, fixtures and
the TS↔Swift parity contract did not move: `swift test --package-path ios/SentryCore`
is green on the same 215 tests and the same goldens, `content.json`'s
`cases`/`shifts`/`tuning` are byte-identical to `HEAD` (checked field by field, not
just by eye), and a full Shift 1 played through the UI produces the
`shift-runs.json` / `shift1-demo-complete` scoreline exactly.

### 14.1 Landed

| Deliverable | Where |
|---|---|
| The sequence runner: one running sequence, absolute deadlines, end-state memory, skip, Reduce-Motion collapse, two channels per beat | `Sources/State/Director.swift` |
| §5's live board, §6's interjections, §7's nudge, §5's fear-caption ledger, §4's clock count-up | the same file, driven from `GameModel.directorFollow(...)` |
| §5's felt band — `max(engine, time)` on the ECG, the band word **and** the heartbeat | `GameModel.feltStatus`, `PlayBar`, `Haptics/HeartbeatPlayer.swift` (one line, see 14.2 #9) |
| §1 the handover: typed eyebrow, a rail of seven slots, alerts landing one per 260 ms, Vale's line, the dock last | `Screens/Play/ShiftIntroView.swift` |
| §2 the arrival: cut, spike, trigger typed, title + asset, severity stamped, sources risen, coach last | `Screens/Play/CaseView.swift` (+ `CaseHeader`) |
| §3 collapsed sources, peek-on-tap (one at a time), `Pull · 10m`, 350 ms long-press, a spent row as a `✓` line | `Components/SourceRow.swift`, `CaseView.sources(_:proxy:)` |
| §4 the pull as a query: seeded log pane, the SystemBar clock counting the cost, `RESULTS`, cards one at a time | `Screens/Play/SourceSheet.swift` |
| §6 Vale as one-line message cards with 500 ms of typing dots; the taxonomy as shift 1's first card | `Components/MessageCard.swift`, `ShiftIntroView`, `CaseView.voice` |
| §6 Settings → *Read the rules again* | `Screens/Meta/SettingsView.swift` (`MetaRoute.rules`, `RulesScreen`) |
| §7 leads-to by rule | `Director.leadsTo(_:justPulled:queried:)` + `SourceRow.nudge` |
| §8 the call as a cut: black, stamp, ground, truth flip, meters, breach flash, why, dock | `Screens/Play/DebriefView.swift` |
| §5's `TIME n / 90`, the live-board severity reveals, the deferred fear captions | `Screens/Play/BoardSheet.swift`, `Components/MeterView.swift` |
| A line that types itself, frame-stable and Reduce-Motion-correct | `Components/TypedText.swift` |
| New durations only — no new timings | `Design/Motion.swift` |
| 25 tests for the parts a strip cannot prove | `Tests/DirectorTests.swift` |
| The QA stopwatch a frame strip is read against | `App/RootView.swift` (`#if SENTRY_QA`) |
| One new chrome key, `settingsRules` | `app/lib/soc/exporter/chrome.ts` |

### 14.2 Decisions and deviations — each one a place the document and the tree differ

1. **`intro.severity` is no longer printed on the handover.** It was the second of the
   two paragraphs that made §1 read as a lecture, and §6 already moves its neighbour —
   the taxonomy — into a card. Both now live in the shift-1 card and in Settings →
   *Read the rules again*. Nothing was deleted: the copy is exported, drawn and
   reachable, and later boards get Vale's one line alone.
2. **The rail carries no title.** §1's `intro.title` — *"7 alerts on the board."* — is
   the ONE line Vale says at the bottom of the sequence, and printing it over the rail
   as well made the screen say the same sentence twice, 1.4 s apart.
3. **The handover's dock is `intro.cta` ("Start the shift ▸"), not §1's "Clock in ▸".**
   §1's label is descriptive; `intro.cta` is the *authored* string for that button, and
   "Clock in" is already the hub's dock (`dockClockIn`). Changing the exported CTA to
   match a prose row would have been a copy edit the document did not ask for.
4. **One new chrome key.** §6's Settings row needed a word, so `settingsRules: "Read
   the rules again"` was authored in `chrome.ts` and the bundle re-exported. The
   exporter's own report is the evidence: `copy.json: changed (23070 → 23115 bytes)` ·
   `contentHash restamped only (no content change)` for the other nine. `content.json`,
   `handler.json`, `shift-runs.json` and `grades.json` were then compared to `HEAD`
   with their `contentHash` removed: identical.
5. **§2's header reads evidence → title → guess.** The shipped header led with the
   severity chip, which is the deck teaching the exact habit it exists to break — the
   tool's severity is a *guess* (`intro.severity`), and printing it first frames the
   read. §2's own timeline puts the trigger at 260 ms and the chip at 1500, so the
   layout was inverted to match the order the player receives it in.
6. **Reduce Motion deduplicates the cues it collapses.** D18 says the sound and the
   haptics stay, and they do — but seven `ping`s inside one millisecond is a blurt
   rather than §1's rising line, and a six-voice pool would drop most of them anyway.
   Each distinct cue fires once, in order.
7. **A skip drops the cues it passed.** Reduce Motion is "do not perform this at me";
   a tap is "stop performing this at me", and finishing the performance into the
   player's ear on the way out is not what they asked for.
8. **`Director.play(…, silencing:)` exists for exactly one cue.** §8's `.cut` beat
   carries `file`, and the reducer already emitted `Effect.haptic(.file)` on
   `MAKE_CALL` — the thud belongs to the *action*. Without the silencer the call
   slammed twice, half a frame apart.
9. **One line outside the owned paths.** `HeartbeatDriver.Signal.status` now reads
   `GameModel.feltStatus` instead of `session.status`
   (`Sources/Haptics/HeartbeatPlayer.swift`, two call sites, one expression). §5 asks
   for the heartbeat to follow `max(engine, time)` and the driver is the only thing
   that decides which band beats. It is presentation exactly like the ECG the same
   value drives; `scoreShift` never sees it.
10. **The scrim dims the read, not the strip.** It used to cover the whole screen,
    SystemBar included, at 85 % — and §4 asks the player to watch the shift clock
    count the cost out under an open sheet. It now covers the content area only.
11. **§7's nudge is delivered when the findings land, and the caption outlives the
    glow.** `PULL_SOURCE` is dispatched before the first log line, so a nudge applied
    there glowed and faded while the player was still watching a query pane two
    seconds from its results. It is now *decided* at the pull and *delivered* at the
    sequence's `.end`. The pulse is §7's 600 ms; the caption stays 4.2 s or until the
    player touches any row, because two words that vanish before the sheet is
    dismissed are a nudge nobody receives.
12. **The board's TIME row reads `20 / 90 shift-min`, not §5's `62 / 90m`.** That is
    the authored `boardTimeValue`, and re-voicing it would have been a copy edit for a
    shorthand in a prose row.
13. **The QA stopwatch.** §11 asks a reviewer to check the beats to ±60 ms off a
    100 ms frame grid, which a grid alone cannot settle. Under `SENTRY_QA` — Debug
    only, and check 3 of the release guard proves its absence from Release — the
    running sequence prints its own elapsed milliseconds in the corner. Every timing
    claim in 14.4 is read off those numerals.
14. **`docs/screenshots/ios/feel/debrief/` was removed**, superseded by `call/`: the
    same QA screen, recorded against the screen §8 describes. `smoke/` stays — it is
    the recorder's fallback-path evidence, not a screen's. All frames are re-encoded
    to an 8-bit palette (35 KB a frame rather than 380 KB) and stay fully legible.
15. **§6's thin-call rule is exactly one finding, of noise weight.** §6's line is
    *"You're calling on one card"*, so the condition is `revealed.count == 1 &&
    revealed.allSatisfy { $0.weight == .noise }`. Three noise findings would make the
    sentence false.
16. **The dots are the typing.** §1 row 4 and §6 say "typing dots 500 ms → text";
    running a typewriter on the line *as well* pushed the sentence 400 ms past the
    dock that is supposed to rise after it. The card fades its line in.
17. **The full Shift-1 replay has one forced deviation.** `shift1-demo-complete`'s
    sixth step files a call with **nothing** pulled, and the shipped app disables the
    Dock until a finding is on the board (C8: *"You can't make the call blind"*). The
    replay pulls `change-tickets` — a **non-key** source — instead: `keySourcesPulled`
    stays 0, the call is still blind by the grader's definition, and every scored
    number is unchanged. This is a pre-existing property of the UI, not an F2b change.

### 14.3 Eight bugs the runtime passes caught

1. **The case screen went blank the moment a pull started.** Only one sequence runs at
   a time, so `runID` moved to `pull:…` and `shows(.sources, of: "arrival:…")` — which
   draws the SOURCES list — went false under the open sheet. Found by the Shift-1
   replay, which could not find its second source to pull. Fixed with an end-state
   memory.
2. **…and remembering only the *id* was worse.** `shows(_:of:)` then answered `true`
   for every kind, including beats a sequence never had, so the debrief of a **good**
   call drew §8's rose breach edge. Visible in the first `call/` recording, frames
   37–40. The memory is now the *set* of beats a run contained.
3. **The breach edge never went out.** A beat that has landed stays landed, so an edge
   drawn from `shows(.breach)` stayed lit for the whole debrief — frame 65 of
   `breach/`, four and a half seconds after the cut, still had a rose border. It is a
   one-shot the screen owns now, and Reduce Motion draws no flash at all.
4. **A relative `Task.sleep` is 140 ms late on a 500 ms wait.** The default tolerance
   lets the runtime coalesce a wake-up: §1's line landed at 3760 ms against a
   specified 3620. Every sleep in the feel pass now passes `tolerance: .zero`, and the
   beat walks sleep to absolute deadlines besides.
5. **A pulled source row read as nothing at all.** `.accessibilityElement(children:
   .ignore)` on the row's outer `Group` threw away the labels its branches carry;
   the replay's accessibility dump showed two `case.source` elements with an empty
   label. Each branch owns its own element now, and a spent row announces what it
   surfaced.
6. **The peek button could open underneath the coach card.** The coach and the Dock
   are two stacked bottom insets; the fourth source's `Pull · 6m` chip landed at
   y 702 under a card occupying 689–830, and the tap went to the card. Peeking now
   scrolls the row to centre.
7. **The shift clock jumped instead of counting.** `Director.clockHeld` was subtracted
   inside the source sheet but not in the case screen's own read-out, so the strip
   above the sheet went `0m → 10m` in one frame. One `clockReading(_:)` on the
   Director, read by both.
8. **A beat's two channels were collapsed into one cue.** `Beat` names the haptic and
   the sound separately and they are frequently different — §1's alert is a `select`
   under a `ping`, §4's log line is a `tick` nobody feels — and firing
   `beat.sound ?? beat.cue` on both channels replaced the tap with a second ping and
   lost every `—` row of §9's table. `GameModel.feel(haptic:sound:variant:)` is the
   two-channel call site.

### 14.4 Verification — what was measured, and where the evidence is

Frames are cut at 10 Hz; the fuchsia numerals in each frame are the running
sequence's own elapsed milliseconds (14.2 #13), so a beat and its clock are read off
the same pixel row. Strips and frames are under `docs/screenshots/ios/feel/<name>/`
with a `manifest.txt` beside each.

| § | Beat | FEEL.md | Measured | Evidence |
|---|---|---|---|---|
| §1 | eyebrow complete (22 glyphs × 18 ms) | 396 | 445 | `handover/` |
| §1 | board rises | 600 | (595, 662] | `handover/` |
| §1 | alerts 1–7 | 900 … 2460, step 260 | every one inside its 100 ms frame | `handover/` |
| §1 | Vale's card | 3120 | (3119, 3219] | `handover/` |
| §1 | its line, after 500 ms of dots | 3620 | (3723, 3811] mid-fade ⇒ ~3630 | `handover/` |
| §1 | dock + meters | 3920 | (3886, 4019] | `handover/` |
| §2 | trigger types in | 260, over ~700 | (212, 312], complete 996 | `arrival/` |
| §2 | title + `ASSET:` | 1100 | (1112, 1212] | `arrival/` |
| §2 | severity chip stamps | 1500 | (1496, 1596] | `arrival/` |
| §2 | sources rise | 1800 | (1796, 1896] | `arrival/` |
| §4 | log lines (seeded 310 · 602 · 989 · 1300 · 1705) | that list | each inside a frame of it | `pull/` |
| §4 | the clock counts the cost | 0m → 10m over 2000 | 1m at 271, 5m at 1071, 9m at 1871 | `pull/` |
| §4 | `RESULTS · 1 finding`, sheet grows | 2000 | (2014, 2147] | `pull/` |
| §8 | stamp slams | 450 | (442, 534] | `call/`, `breach/` |
| §8 | ground + `WRONG CALL` | 900 | (934, 1034] | `breach/` |
| §8 | `TRUTH:` flips | 1200 | (1234, 1334] | `breach/` |
| §8 | meters + breach flash | 1500 | (1409, 1511] | `breach/` |
| §8 | `WHY` + findings, dock last | 2100 | (2132, 2233] | `call/` |

Everything else, checked on the glass and kept as an end state under
`docs/screenshots/ios/feel/states/`:

- `03-arrival-end` — §2's end state and §3's collapsed rows: name and cost, no questions.
- `04-source-peek` — §3's peek, one row open, `Pull the log 10m`, and §6's coach as a card.
- `06-pull-querying` / `07-pull-results` — §4 mid-stream (clock at 6m, `USED 6 / 90`) and at rest.
- `08-leads-to-and-vale` — §7's `worth a look` on two unpulled key sources, §6's first-pull line, §3's spent row as `✓ … 1 finding`.
- `10-board-sheet` — §5's `TIME 20 / 90 shift-min`, no fear captions yet.
- `12-live-board` — §5's live board: alert 6 revealed `MEDIUM` after ~60 s of investigating.
- `13-breach-edge` / `14-fear-caption` — §5's caption arriving with the first delta, on the meter that moved and not on the one that did not.
- `shift1-summary` — the full replay's scoreline.

**Reduce Motion** (`ReduceMotionEnabled` on the simulator): §1's whole 4.2 s sequence
is at its end state 1.2 s after launch — eyebrow complete, seven slots filled, the
taxonomy card with no dots, meters and dock present — and the trace still reads
`sound ping-1` · `cue ping via feedbackGenerator` · `sound tick` · `cue tick via
soundOnly`. Motion collapsed; both other channels unchanged (D18).

**Full Shift 1, fresh install, driven with idb.** Seven alerts, fifteen pulls, seven
holds-to-file. The 16:00 summary: `ROUGH SHIFT` · Accuracy **86 %** · Calls **7/7** ·
Missed threats **0** · False escalations **1** · Investigation **88 %** · **1 call
made blind** · **+300 ¢** · **+15 ⬢** · standing `0 → 15`. Every one of those is
`shift1-demo-complete`, to the number.

**Check set:** `xcodegen generate` · `xcodebuild build` · `xcodebuild test
-only-testing:SentrySOCTests` (109 tests, 9 suites) · `swift test --package-path
ios/SentryCore` (215 tests, 18 suites) · `bash ios/scripts/verify.sh` (9 checks, 0
failures, no new allowlist entries).
