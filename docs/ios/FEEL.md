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
