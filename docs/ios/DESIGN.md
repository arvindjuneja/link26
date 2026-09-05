# SENTRY — SOC · Product design (carried over)

> Extracted 2026-09-05 from the earlier (Capacitor-era) design spec. Sections keep their
> original numbers because `docs/ios/SPEC.md` cites them (§2.x, §3, §4, §6, §7). The
> build architecture is NOT this document — see `SPEC.md` (native SwiftUI) and
> `SPEC-ADDENDUM.md`. Where they conflict, SPEC-ADDENDUM > SPEC > this file.

## 2 · Information architecture

### 2.1 The Deck's phase state machine

Two orthogonal pieces of state, both inside the pure reducer `app/lib/soc/session.ts`:

```ts
type Phase = "hub" | "briefing" | "investigating" | "debrief" | "complete" | "milestone";
type View  = "none" | "board" | "source" | "call" | "kit" | "settings" | "abandon" | "firstRun";
```

`Phase` is where you are in the shift; `View` is what is on top of it. Actions:
`HYDRATE · START_SHIFT · BEGIN · RESUME · OPEN_VIEW · CLOSE_VIEW · PULL_SOURCE · PICK_DISPOSITION · MAKE_CALL · NEXT_CASE · ACK_MILESTONE · TO_HUB · ABANDON · BUY · SET_SETTING`.

**Transitions**

| From | Action | To | Guard / effect |
|---|---|---|---|
| *(boot)* | `HYDRATE` | `hub` (+ `view:"firstRun"` if `sentry_soc_firstrun_v1` unset) | If a `sentry_soc_session_v1` snapshot exists, the hub shows a Resume card; the snapshot is **not** auto-entered. |
| `hub` | `START_SHIFT(defId)` | `briefing` | `isUnlocked(career, def)` must hold. |
| `hub` | `RESUME` | snapshot's phase (`investigating` \| `debrief`) | Restores `shift`, `queried`, `last`. |
| `hub` | `BUY(item)` | `hub` | `buyKit` no-ops if unaffordable/owned. |
| `hub` | `OPEN_VIEW("kit"\|"settings")` | `hub` + view | |
| `briefing` | `BEGIN` | `investigating` (+ `view:"board"` once) | Applies the intel-feed pre-pull (`initialQueried`). The Board sheet auto-opens on the first case of a shift, then never again unless asked. |
| `briefing` | `TO_HUB` | `hub` | Nothing committed yet, so a back control is allowed here (the web never had one). |
| `investigating` | `OPEN_VIEW("source", id)` | `investigating` + `view:"source"` | |
| `view:"source"` | `PULL_SOURCE(id)` | `investigating`, view stays `"source"` | Idempotent. Adds to `queried`; findings render inside the same sheet. |
| `investigating` | `OPEN_VIEW("call")` | `view:"call"` | **Guard:** `revealedEvidence.length > 0` (today's `revealed.length > 0` rule, SocConsole.tsx:495). |
| `view:"call"` | `PICK_DISPOSITION(d)` | same | Sets `pendingDisposition`; reveals hold-to-file. |
| `view:"call"` | `MAKE_CALL(d)` | `debrief`, `view:"none"` | **Guard:** `phase === "investigating"` (the re-entrancy guard at SocConsole.tsx:234). Runs `applyCall`; writes the onboarding key on the first real call of shift index 0. |
| `debrief` | `NEXT_CASE` | `investigating` \| `complete` | `complete` runs the settlement: `scoreShift → awardForShift → unlocked diff → HandlerEvent → saveCareer`, and clears the session snapshot. |
| `complete` | `NEXT_CASE`/`CONTINUE` | `milestone` \| `hub` | `milestone` iff `reward.rankUp` or `unlocked.length > 0`. |
| `milestone` | `ACK_MILESTONE` | `hub` | |
| `investigating` | `OPEN_VIEW("abandon")` → `ABANDON` | `hub` | Clears the snapshot. Progress on that queue is lost; career is not touched. |
| *any* | `SET_SETTING` | same | |

**Render map (phase, view) → component**

| phase | view `"none"` | overlay |
|---|---|---|
| `hub` | `screens/Hub` | `KitSheet` · `Settings` · `FirstRun` |
| `briefing` | `screens/ShiftIntro` | — |
| `investigating` | `screens/Case` | `Board` · `SourceSheet` · `CallSheet` · `AbandonSheet` · `Coach` (shift index 0 only, not a view — anchored) |
| `debrief` | `screens/Debrief` | `Settings` |
| `complete` | `screens/ShiftSummary` | — |
| `milestone` | `screens/RankUp` | — |

`SystemBar` renders above everything except `RankUp` (full-bleed) and `FirstRun`.

### 2.2 Layout system (390 × 844) and thumb zones

The Deck is `position: fixed; inset: 0;` with `padding-top: env(safe-area-inset-top)` and `padding-bottom: env(safe-area-inset-bottom)`, one scroll region per screen, `overscroll-behavior: none`.

```
y=0    ┌─────────────────────────────────┐
       │ status bar / Dynamic Island     │  59 pt  safe-area-top — never draw here
y=59   ├─────────────────────────────────┤
       │ SYSTEM BAR (44 pt)              │  wordmark · ECG · queue pill · ⚙
y=103  ├─────────────────────────────────┤
       │                                 │
       │   READ ZONE                     │  scrolls. No primary action lives here.
       │   (content)                     │  Secondary taps (source rows, cards) are fine.
       │                                 │
y=560  ├─────────────────────────────────┤
       │   THUMB ARC                     │  every primary action: Dock CTA (56 pt),
       │                                 │  hold-to-file (64 pt), disposition rows (68 pt)
y=780  ├─────────────────────────────────┤
       │ home indicator                  │  34 pt safe-area-bottom — nothing tappable
y=844  └─────────────────────────────────┘
```

Rules: minimum hit target **44 pt**; list rows 56–72 pt; primary CTA 56 pt; hold-to-file 64 pt; ≥8 pt between adjacent targets; destructive actions (Abandon, Reset career) are text buttons **outside** the thumb arc and always behind a confirm sheet. Back controls sit top-left at 44 pt (stretch reach, low frequency).

### 2.3 Hub — "The Desk"

```
┌──────────────────────────────────────────────────┐ y=0
│ 9:41                                  ●●●● ▮▮▮▮  │ safe-area-top 59pt
├──────────────────────────────────────────────────┤
│ SENTRY · SOC              ⬢ 80   ¢ 650      ⚙   │ SystemBar, hub mode: no ECG
├──────────────────────────────────────────────────┤
│  THE DESK · YOUR CAREER                          │ 11pt mono tracked .18em emerald
│  Tier-1 Analyst                                  │ 24pt Grotesk semibold zinc-100
│  ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░  70 to Senior    │ 4pt bar · 13pt mono zinc-500
│                                                  │
│  ┌ RESUME ─────────────────────────────────────┐ │ only when a snapshot exists
│  │ Shift 2 · alert 3 of 8 · 22m                │ │
│  │ BREACH 30 · NOISE 0            Resume  ▸    │ │
│  └─────────────────────────────────────────────┘ │
│                                                  │
│  ┌ ● VALE · YOUR SHIFT LEAD ───────────── 1/3 ›┐ │ InboxCard · tone colour on the dot
│  │ Clean shift — nice work                     │ │ 17pt Grotesk semibold
│  │ Sharp reads all the way through. +40        │ │ 15pt Grotesk zinc-400, 2-line clamp,
│  │ standing. Keep them clean and you're 70…    │ │ tap = expand in place
│  └─────────────────────────────────────────────┘ │
│                                                  │
│  QUEUES — EARN ⬢ TO OPEN HARDER WORK             │
│  ┌─────────────────────────────────────────────┐ │
│  │ Shift 1 · fundamentals            7 alerts  │ │ 64pt rows, whole row tappable
│  │ cleared · replay                    Start ▸ │ │ cleared: zinc-400
│  ├─────────────────────────────────────────────┤ │
│  ┃ Shift 2 · phishing · identity     8 alerts  │ │ open: 3px emerald left rule
│  ┃ open                                Start ▸ │ │
│  ├─────────────────────────────────────────────┤ │
│  │ Shift 3 · the lockout queue       3 alerts  │ │ locked: zinc-600, dashed border
│  │ ⬡ LOCKED · opens at ⬢ 80                    │ │ NO emoji (🔒 is gone)
│  ├─────────────────────────────────────────────┤ │
│  │ Shift 4 · the other chair         3 alerts  │ │ blue-only label ends
│  │ ⬡ LOCKED · opens at ⬢ 120                   │ │ "(a red team's runs)"
│  ├─────────────────────────────────────────────┤ │
│  │ Shift 5 · the insider desk        3 alerts  │ │
│  │ ⬡ LOCKED · opens at ⬢ 160                   │ │
│  ├─────────────────────────────────────────────┤ │
│  ┃ DAILY SHIFT · FRI 05 SEP          5 alerts  │ │ cyan rule; "done today ✓" after play
│  ┃ a fresh board every day             Start ▸ │ │
│  └─────────────────────────────────────────────┘ │
│                                                  │
│  ANALYST KIT — SPEND ¢                     1 ▸   │ opens KitSheet
│  About · fiction simulator · privacy             │ opens Settings
├──────────────────────────────────────────────────┤
│ ┃██   Clock in · Shift 2  ▸                 ██┃  │ Dock 56pt emerald, thumb arc
│                    ▬▬▬▬▬▬▬▬                      │ safe-area-bottom 34pt
└──────────────────────────────────────────────────┘
```
Dock label: `Resume Shift 2 · alert 3/8` when a snapshot exists, else `Clock in · <next open shift>`, else (all cleared) `Daily shift · Fri 05 Sep`. Locked rows are inert; the reason line is text, never a tooltip. Web only: an `exitLink` slot ("↩ red seat") renders under the About line.

### 2.4 Shift intro — handover 08:00

```
┌──────────────────────────────────────────────────┐
│ ‹ Desk                       Shift 1 · 7 alerts  │ 44pt header; back = TO_HUB
├──────────────────────────────────────────────────┤
│  ● SHIFT HANDOVER · 08:00                        │ 11pt tracked emerald (fuchsia on Shift 4)
│                                                  │
│  Welcome to the desk.                            │ 24pt Grotesk semibold
│  7 alerts on the board.                          │
│                                                  │
│  You're the Tier-1 analyst. Every alert          │ 15pt Grotesk zinc-400
│  resolves to exactly one call:                   │
│  ┌───── TAXONOMY SLOT — SOC_INTRO_COPY.verdicts ┐│
│  │ ▍ True Positive                              ││ 3px rose rule · 17pt
│  │   a real threat                              ││ 15pt zinc-400
│  │ ▍ False Positive                             ││ cyan rule
│  │   the detection misfired                     ││
│  │ ▍ Benign True Positive                       ││ emerald rule
│  │   the detection was right — the activity     ││ ← the parallel taxonomy workflow
│  │   was authorized                             ││   rewrites exactly this object
│  └──────────────────────────────────────────────┘│
│                                                  │
│  The tool's severity label is a guess. Pull      │ 15pt zinc-400
│  the right logs, read what actually happened,    │
│  and make the call. Escalate a real threat;      │
│  don't bury Tier-2 in false alarms; never        │
│  isolate a sanctioned operation.                 │
│                                                  │
│  BREACH RISK   miss a real one and it dwells     │ 13pt mono · rose label
│  NOISE         cry wolf and Tier-2 stops         │ amber label
│                trusting your tickets             │
│                                                  │
│  ┌ SHIFT 4 ONLY · fuchsia ─────────────────────┐ │ features.redSeat ? .handoff.redSeat
│  │ Tonight every alert is a red-team           │ │                  : .handoff.blueOnly
│  │ engagement's run, seen from your chair.     │ │
│  │ Authorization, not authorship, decides      │ │
│  │ the verdict.                                │ │
│  └─────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────┤
│ ┃██   Start the shift  ▸                    ██┃  │ 56pt emerald
│  Fiction simulator — every log line is           │ 11pt zinc-500, 3 lines
│  fabricated; it teaches the analyst's read,      │
│  never a working technique.                      │
│                    ▬▬▬▬▬▬▬▬                      │
└──────────────────────────────────────────────────┘
```
Every string here comes from `copy.ts`. Scrolls; the Dock is fixed.

### 2.5 Board sheet — the queue + pressure

```
┌──────────────────────────────────────────────────┐
│ SENTRY · SOC   ~~/\~~~~/\~~~   QUEUE 3/7    ⚙   │ ECG live; the pill opens this sheet
├──────────────────────────────────────────────────┤
│░░░░░░░░ case dimmed to 40% · scrim #020408/85 ░░░│ tap to dismiss
│┌──────────────────── ▬▬▬▬ ──────────────────────┐│ sheet, 92% height, 320ms spring
││ ALERT QUEUE · SHIFT 1                 22m      ││ 11pt tracked · shift clock
││ ┌────────────────────────────────────────────┐ ││
││ │ ✓ 1  Encoded PowerShell on a finance wo…   │ ││ done · verdict right (emerald ✓)
││ │ ✗ 2  Failed-logon burst then success — r…  │ ││ done · verdict wrong (rose ✗)
││ ┃ ▶ 3  Encoded PowerShell on a patch server  │ ││ current · cyan rule + glow
││ │      EDR · powershell.exe -EncodedCommand  │ ││ 13pt mono zinc-500 detectionRule
││ │ · 4  Periodic DNS to high-entropy domains  │ ││ ahead: title only, truncated —
││ │ · 5  Failed-logon burst then success — m…  │ ││ NO severity shown (it would prime
││ │ · 6  DGA heuristic fired on marketing lap… │ ││ the read before the alert opens)
││ │ · 7  Credential spray across many accounts │ ││
││ └────────────────────────────────────────────┘ ││
││ SHIFT PRESSURE                                 ││
││ BREACH RISK                              30    ││ amber at ALERT band
││ ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░     ││
││ a real threat you closed is dwelling           ││ 11pt zinc-600 — the fear text that
││ undetected                                     ││ is a title= tooltip today (L108)
││ NOISE / FATIGUE                           0    ││
││ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░     ││
││ crying wolf — Tier-2 stops trusting your       ││
││ tickets                                        ││
││ TIME                        22 / 90 shift-min  ││ soft budget, surfaced not scored
││ ▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░     ││
││                                                ││
││                              Abandon shift ·   ││ 13pt zinc-600 → AbandonSheet
│├────────────────────────────────────────────────┤│
││ ┃    Open alert 3  ▸                        ┃  ││ 52pt cyan · "Back to the alert"
│└──────────────────── ▬▬▬▬▬▬▬▬ ──────────────────┘│   once you have been on the case
└──────────────────────────────────────────────────┘
```
Done rows re-open their debrief read-only (`gradeCall` re-run from `shift.results`). At ≥1024px this same component renders inline as a 260 px left rail — **one of the only two `lg:` rules in the Deck.**

### 2.6 Case — the read

```
┌──────────────────────────────────────────────────┐
│ ‹ 1/7          ~~~~~~~~~~~~   QUIET       0m  ⚙ │ ECG flat at CALM · long-press = numbers
├──────────────────────────────────────────────────┤
│  ┌ HIGH · AS FLAGGED ┐                           │ severity chip, 11pt mono, orange outline
│  EDR · powershell.exe launched with              │ 13pt mono zinc-500 (detectionRule)
│  -EncodedCommand                                 │
│                                                  │
│  Encoded PowerShell on a                         │ 22pt Grotesk semibold zinc-100
│  finance workstation                             │ never truncated
│                                                  │
│  powershell.exe spawned with -EncodedCommand     │ 15pt Grotesk zinc-300 (trigger)
│  on FIN-WS-04 at 02:14 local — off-hours.        │
│                                                  │
│  ASSET  FIN-WS-04 · user jdoe (Finance)          │ 13pt mono · overflow-wrap:anywhere
│  ──────────────────────────────────────────────  │ hairline zinc-800/60
│  ┌──────────────────────┬──────────────────────┐ │ segmented control, 44pt, live badges
│  │ ● SOURCES     0/6    │   EVIDENCE      0    │ │ data-soc="sources" / "evidence"
│  └──────────────────────┴──────────────────────┘ │
│  WHICH LOG ANSWERS THE QUESTION?                 │
│  ┌─────────────────────────────────────────────┐ │
│  │ EDR — process tree & lineage          10m   │ │ 72pt rows: label 15pt mono zinc-100,
│  │ what spawned this, and what did it do after?│ │ cost 13pt tabular right,
│  ├─────────────────────────────────────────────┤ │ question 13pt Grotesk italic zinc-500
│  │ Decode the command                    10m   │ │
│  │ what does the encoded blob actually say?    │ │
│  ├─────────────────────────────────────────────┤ │
│  │ Firewall / proxy logs                  8m   │ │
│  │ did it call out, and to what?               │ │
│  ├─────────────────────────────────────────────┤ │
│  │ Change tickets / CAB                   6m   │ │
│  │ was this scheduled or authorized?           │ │
│  └─────────────────────────────────────────────┘ │
│  ┌ ● SHIFT LEAD · IN YOUR EAR             1/3 ─┐ │ Coach docks ABOVE the Dock — never
│  │ Pull the log that answers the question      │ │ over the alert header (fixes the
│  │ Each source shows the question it answers   │ │ P2 overlap from PLAYTEST-lookandfeel)
│  │ — start with the process tree.              │ │
│  │                            skip coaching    │ │
│  └─────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────┤
│ ┃   Make the call  ▸        investigate first ┃  │ 56pt, 40% opacity until a finding
│                    ▬▬▬▬▬▬▬▬                      │ exists (the existing rule)
└──────────────────────────────────────────────────┘
```
The header collapses to one sticky line (`HIGH · Encoded PowerShell on a finance workstation ▾`) after 80 px of scroll.

### 2.7 Source sheet — the commit

```
│░░░░░░░░░░░ case dimmed · scrim ░░░░░░░░░░░░░░░░░░│
│┌──────────────────── ▬▬▬▬ ──────────────────────┐│
││ PULL A DATA SOURCE                             ││ 11pt tracked cyan
││                                                ││
││ EDR — process tree & lineage                   ││ 18pt Grotesk
││ what spawned this, and what did it do after?   ││ 15pt Grotesk italic zinc-400
││                                                ││
││ COST  10 shift-min             USED  0 / 90    ││ tabular
││ ▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░     ││ ▒ = the +10 preview segment (cyan)
││                                                ││
││ ┃          Pull the log  ▸                  ┃  ││ 52pt cyan
││ ───────────── after the pull ─────────────────  ││ same sheet, CTA morphs
││ ▒▒▒▒▒▒▒▒▒░░░  querying EDR — process tree …    ││ QueryProgress, 600ms
││ ● 1 FINDING SURFACED                           ││
││ ┌────────────────────────────────────────────┐ ││ card lands: translateY 12→0, 220ms
││ │ Parent is WINWORD.EXE                      │ ││ 15pt medium zinc-200
││ │ Lineage: WINWORD.EXE → cmd.exe →           │ ││ 15pt Grotesk zinc-400 — FULL text,
││ │ powershell.exe. A document spawned a       │ ││ never clamped (it is the puzzle)
││ │ shell — not how IT runs scripts.           │ ││
││ └────────────────────────────────────────────┘ ││
││ ┃          To the board  ▸                  ┃  ││ closes, selects EVIDENCE tab
││ Pull another                                   ││ text button → back to SOURCES
│└──────────────────── ▬▬▬▬▬▬▬▬ ──────────────────┘│
```
Pulled sources stay listed and inert. Sources render in the case's authored order; `label` (≤38 ch) and `question` (≤75 ch) are never truncated.

### 2.8 Evidence board

```
┌──────────────────────────────────────────────────┐
│ ‹ 1/7          ~~/\~~~~/\~~~   ALERT     26m  ⚙ │
├──────────────────────────────────────────────────┤
│  HIGH · Encoded PowerShell on a finance work… ▾  │ collapsed sticky header
│  ┌──────────────────────┬──────────────────────┐ │
│  │   SOURCES     3/6    │ ● EVIDENCE      3    │ │
│  └──────────────────────┴──────────────────────┘ │
│  EVIDENCE BOARD                       3 findings │
│  FROM  EDR — process tree & lineage              │ 11pt tracked zinc-600, pull order
│  ┌─────────────────────────────────────────────┐ │
│  │ Parent is WINWORD.EXE                       │ │
│  │ Lineage: WINWORD.EXE → cmd.exe →            │ │
│  │ powershell.exe. A document spawned a shell  │ │
│  │ — not how IT runs scripts.                  │ │
│  └─────────────────────────────────────────────┘ │
│  FROM  Decode the command                        │
│  ┌─────────────────────────────────────────────┐ │
│  │ Decodes to a download-cradle                │ │
│  │ Decoded blob is an in-memory downloader:    │ │
│  │ pull a follow-on script from a remote host  │ │
│  │ and run it without writing to disk.         │ │
│  └─────────────────────────────────────────────┘ │
│  FROM  Change tickets / CAB                      │
│  ┌─────────────────────────────────────────────┐ │
│  │ No change ticket                            │ │
│  │ No maintenance window, no change record for │ │
│  │ FIN-WS-04. jdoe is Finance, not IT.         │ │
│  └─────────────────────────────────────────────┘ │
│  ┌ ─ EMPTY STATE (0 pulls) ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐   │
│    Pull a source to surface findings.            │
│    You can't make the call blind.                │
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘   │
├──────────────────────────────────────────────────┤
│ ┃██  Make the call  ▸      3 findings · 26m ██┃  │ armed: emerald fill
│                    ▬▬▬▬▬▬▬▬                      │
└──────────────────────────────────────────────────┘
```
`neutral` and `noise` findings render **identically** to `decisive` ones — weights are only revealed in the debrief. Tapping a `FROM` header jumps back to that row in SOURCES.

### 2.9 Call sheet — hold to file

```
┌──────────────────────────────────────────────────┐
│ ✕                                  MAKE THE CALL │ full-height sheet, 320ms
├──────────────────────────────────────────────────┤
│  Encoded PowerShell on a finance workstation     │ 15pt Grotesk zinc-400
│  3 sources pulled · 26m                          │ 11pt mono zinc-600 — no thin/thorough
│                                                  │ hint (that is the debrief's job)
│  ┌─────────────────────────────────────────────┐ │
│  │ ▍ Close · False Positive                    │ │ 68pt · cyan rule · 17pt Grotesk
│  │   a false alarm — no real threat            │ │ 13pt zinc-500 — DISPOSITION_META.sub
│  ├─────────────────────────────────────────────┤ │ (copy.ts: the taxonomy slot again)
│  │ ▍ Close · Benign (authorized)               │ │ emerald rule
│  │   correct detection, sanctioned activity    │ │
│  ├─────────────────────────────────────────────┤ │
│  │ ▍ Escalate → Tier 2                         │ │ amber rule
│  │   suspicious / confirmed — hand up          │ │
│  ├─────────────────────────────────────────────┤ │
│  ┃ ▍ Escalate → IR + isolate host        ◉     │ │ SELECTED: 8% rose fill, 1px rose ring;
│  ┃   active threat — contain now               │ │ the others dim to 55%
│  └─────────────────────────────────────────────┘ │
│                                                  │
│  Keep investigating                              │ 13pt zinc-400 → close, selection kept
├──────────────────────────────────────────────────┤
│ ┃ ◔   Hold to file · Escalate → IR          ██┃  │ 64pt, appears only after a pick.
│                    ▬▬▬▬▬▬▬▬                      │ 550ms hold, conic ring fills clockwise;
└──────────────────────────────────────────────────┘ release early = cancel, no penalty
```
Hold-to-file is the Papers-Please stamp: `pointerdown` starts the 550 ms timer and the ring; `pointerup`/`pointercancel`/`pointerleave` before completion cancels with no state change. **Settings → "Hold to file" off** switches to a two-tap `File ▸` → `Confirm` (accessibility + preference). One `MAKE_CALL` per case is guaranteed by the reducer's re-entrancy guard, not by the UI.

### 2.10 Debrief — the hero screen

```
┌──────────────────────────────────────────────────┐
│ SENTRY · SOC   ~~/\~~~~/\~~~   ALERT     1/7  ⚙ │ no back control — a debrief is completed
├──────────────────────────────────────────────────┤
│▒▒▒▒▒ full-bleed 6% tint in the verdict tone ▒▒▒▒▒│ emerald / amber / rose
│  ● GOOD CALL                                     │ 11pt tracked — DEBRIEF_HEADLINES
│  ┌─────────────────────────────────────────────┐ │
│  │     ╔═══════════════════════════╗           │ │ THE STAMP: 13pt mono, rotate(-3deg),
│  │     ║ ESCALATED · IR + ISOLATE  ║           │ │ scale 1.4→1 over 180ms
│  │     ╚═══════════════════════════╝           │ │
│  │ Encoded PowerShell on a finance workstation │ │ 15pt zinc-400
│  │ TRUTH   True Positive                       │ │ VERDICT_LABEL chip · rose
│  └─────────────────────────────────────────────┘ │
│  Right call — an active threat, contained and    │ 17pt Grotesk zinc-100 (grade.outcome)
│  handed to IR.                                   │
│                                                  │
│  BREACH RISK  ░░░░░░░░░░░░░░░░░░░░  0   ±0       │ MeterDelta: sweeps 600ms + count-up
│  NOISE        ░░░░░░░░░░░░░░░░░░░░  0   ±0       │ a +30 breach jump = thud + rose flash
│                                                  │
│  WHY                                             │ 11pt tracked
│  Encoding was never the threat — the LINEAGE     │ 15pt/1.6 Grotesk zinc-300, FULL text
│  and BEHAVIOUR are. A Word document spawned      │ (291–566 chars; it scrolls, it is
│  PowerShell, the decoded payload is an in-       │  never clamped)
│  memory download-cradle, there's a live          │
│  outbound to a 3-day-old domain, and no change   │
│  ticket on a finance host off-hours…             │
│                                                  │
│  THE DECISIVE FINDINGS                           │
│  ✓ Parent is WINWORD.EXE                         │ ✓ emerald = you pulled it
│  ✓ Decodes to a download-cradle                  │ ○ zinc = you missed it
│  ○ Immediate outbound to a fresh domain          │
│  you pulled 2/3 of the sources that answer this  │ 13pt zinc-500
│  case                                            │
│                                                  │
│  ┌ ▸ LEARN IT FOR REAL      T1059.001 · PowerS…┐ │ collapsed expander: concept +
│  └─────────────────────────────────────────────┘ │ MITRE chip + pointer, TEXT ONLY
│  your call: Escalate → IR + isolate host         │ 13pt zinc-500
├──────────────────────────────────────────────────┤
│ ┃██   Next alert  ▸                         ██┃  │ "End shift ▸" on the last case
│                    ▬▬▬▬▬▬▬▬                      │
└──────────────────────────────────────────────────┘
```
Entry sequence (~1.1 s, tap anywhere to skip): stamp lands → outcome fades in → meters sweep. Re-openable read-only from the Board's done rows. The Escape shortcut survives on web (harmless in the app).

### 2.11 Shift summary — 16:00 handover

```
┌──────────────────────────────────────────────────┐
│ SENTRY · SOC   ───────────────   QUIET   7/7  ⚙ │ ECG flattens and fades
├──────────────────────────────────────────────────┤
│         SHIFT COMPLETE · 16:00 HANDOVER          │ 11pt tracked zinc-500
│                                                  │
│                 CLEAN SHIFT                      │ 28pt Grotesk bold emerald
│                                                  │ (ROUGH SHIFT amber /
│   Sharp reads all night. Nothing dwelt, and      │  BREACH ON YOUR WATCH rose)
│   you didn't bury Tier-2 in noise. This is       │ 15pt zinc-400 — GRADE_META
│   what a good T1 looks like.                     │
│  ┌──────────────────────┬──────────────────────┐ │
│  │  100%                │  7/7                 │ │ StatTile · 28pt mono tabular
│  │  ACCURACY            │  CALLS               │ │ 11pt tracked zinc-600
│  ├──────────────────────┼──────────────────────┤ │
│  │  0                   │  0                   │ │ emerald at 0, rose above
│  │  MISSED THREATS      │  FALSE ESCALATIONS   │ │
│  └──────────────────────┴──────────────────────┘ │
│  Investigation — pulled 86% of the logs that     │ 13pt zinc-500; blind-call line in rose
│  answer these cases · 0 blind calls              │
│                                                  │
│  PAYOUT                                          │ 11pt tracked emerald
│  +500 ¢                +40 ⬢ standing            │ 22pt mono, 800ms count-up
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░  0 → 40             │ standing bar sweeps to the new value
│  ┌─────────────────────────────────────────────┐ │
│  │ UNLOCKED   Shift 2 · phishing · identity …  │ │ fuchsia card, text chip (no 🔓)
│  └─────────────────────────────────────────────┘ │
│  THE BOARD    ✓ ✓ ✓ ✓ ✓ ✗ ✓                      │ tap a glyph → that debrief, read-only
│                                                  │
│  ┌ ▸ THE LADDER · Tier-1 → Tier-2 → Tier-3 ────┐ │ collapsed. Inside, verbatim:
│  └─────────────────────────────────────────────┘ │ BTL1 / NICE framing + "in-game
├──────────────────────────────────────────────────┤ framing only — not a certification;
│ ┃██   Back to the desk  ▸                   ██┃  │ no pay figures are presented as fact"
│                    ▬▬▬▬▬▬▬▬                      │
└──────────────────────────────────────────────────┘
```
The career is saved **before** this screen renders, so a force-quit here loses nothing. CTA routes to Rank-up when there is a milestone, else to the Hub.

### 2.12 Rank-up / campaign finale

```
┌──────────────────────────────────────────────────┐
│                                                  │ no SystemBar — a cinematic beat
│                   ╱‾‾‾‾‾‾‾╲                      │ RankBadge: 140pt hexagon (the ⬢ glyph),
│                 ╱           ╲                    │ emerald stroke draws itself over 900ms
│                │   TIER-1    │                   │ (stroke-dashoffset), then fills to 10%
│                │   ANALYST   │                   │ 13pt mono tracked inside
│                 ╲           ╱                    │
│                   ╲_______╱                      │
│                                                  │
│                  PROMOTED                        │ 11pt tracked emerald
│           Trainee  →  Tier-1 Analyst             │ 22pt Grotesk zinc-100
│                                                  │
│  ┌ ● VALE · YOUR SHIFT LEAD ───────────────────┐ │ the ev-rankup body from inboxFor()
│  │ That's Tier-1 Analyst. I flagged you to the │ │ 15pt Grotesk zinc-300
│  │ lead. This is the ladder, and you're        │ │ (at t2 with redSeat=false this is
│  │ climbing it the right way — by being right. │ │  Vale's line, not Mercer's)
│  └─────────────────────────────────────────────┘ │
│  THE LADDER                                      │
│  ●────────●────────○────────○                    │ RANKS from career/state.ts:41-46
│  Trainee  Tier-1   Senior   Tier-2               │
│    0        40       150      210                │ 11pt mono
│  Real-world entry credential for this chair:     │ 13pt zinc-500
│  BTL1 (Blue Team Level 1) · NICE "Cyber Defense  │
│  Analyst". In-game framing — not a certification,│
│  and no pay figures.                             │
├──────────────────────────────────────────────────┤
│ ┃██   Continue  ▸                           ██┃  │
│                    ▬▬▬▬▬▬▬▬                      │
└──────────────────────────────────────────────────┘
```
Finale variant at rank `t2`: eyebrow **THE DESK IS YOURS**, a recap row (`N shifts · M clean · K cases read`), fuchsia badge, and the Daily row is promoted to the top of the Hub afterwards. This is the climax the red-side audit found missing.

### 2.13 Settings / About, and the first-run disclaimer

```
┌──────────────────────────────────────────────────┐   ┌──── FIRST RUN (blocking) ────┐
│ ‹ Desk                              SETTINGS     │   │                              │
├──────────────────────────────────────────────────┤   │  SENTRY — SOC                │
│  FEEL                                            │   │                              │
│  ┌─────────────────────────────────────────────┐ │   │  FICTION SIMULATOR           │
│  │ Haptics · heartbeat + feedback      [●   ]  │ │   │  Every organisation, host,   │
│  │ Hold to file · off = tap twice      [●   ]  │ │   │  user and log line in this   │
│  │ Coaching on the first alert         [●   ]  │ │   │  game is fabricated. Cases   │
│  │ Motion                  follows system      │ │   │  show how a Tier-1 analyst   │
│  └─────────────────────────────────────────────┘ │   │  reads evidence — concepts   │
│  DESK                                            │   │  and workflow, never a       │
│  ┌─────────────────────────────────────────────┐ │   │  working technique. Not a    │
│  │ Tier-1 Analyst · ⬢ 40 · ¢ 350 · 1 clean     │ │   │  training platform, not a    │
│  │ Reset career…                               │ │   │  certification. MITRE        │
│  └─────────────────────────────────────────────┘ │   │  ATT&CK® ids are lookup      │
│  ABOUT · SENTRY — SOC 1.0 (12)                   │   │  labels only. No pay or      │
│  ┌─────────────────────────────────────────────┐ │   │  salary figures are          │
│  │ FICTION SIMULATOR                           │ │   │  presented as fact.          │
│  │ …the same block as the first-run gate…      │ │   │                              │
│  ├─────────────────────────────────────────────┤ │   │ ┃██  I understand      ██┃  │
│  │ PRIVACY                                     │ │   └──────────────────────────────┘
│  │ No account. No network. No analytics. Your  │ │   written to sentry_soc_firstrun_v1
│  │ career is stored only on this device.       │ │
│  │ Privacy policy                          ↗   │ │ Browser.open → SFSafariViewController
│  ├─────────────────────────────────────────────┤ │ (the ONLY outbound link in the app)
│  │ Our promise: no ads, no pay-to-win, no      │ │
│  │ timers, no loot boxes, no data selling.     │ │
│  │ Credits · MITRE ATT&CK® · font licenses     │ │
│  └─────────────────────────────────────────────┘ │
│  [web only]  ↩ red seat                          │ exitLink slot
└──────────────────────────────────────────────────┘
```
Dev builds only (`platform.isDev`): five taps on the version line reveal a QA-jumps row that dispatches the `demo.ts` fixtures — this replaces the `?demo=` URL deep-links, which do not exist at `capacitor://localhost`.

### 2.14 Motion

| Element | Motion |
|---|---|
| Screen push | 260 ms `cubic-bezier(.2,.8,.2,1)`, `translateX 24px → 0` + fade |
| Sheet | 320 ms up, scrim fade 200 ms, swipe-down to dismiss |
| Source query | 600 ms `QueryProgress` bar, then findings land `translateY 12px → 0` + fade 220 ms, 45 ms stagger |
| Stamp | 180 ms `scale 1.4 → 1` + `rotate(-3deg)` |
| Meter delta | 600 ms sweep with numeric count-up |
| Payout | 800 ms count-up; standing bar sweeps old → new |
| Rank badge | 900 ms `stroke-dashoffset` draw, then 10 % fill |
| ECG | rAF canvas, scroll period `60000 / BPM[status]`; CALM = near-flat at 50 % opacity with one faint blip |
| Edge glow | the existing inset `box-shadow` table; pulses at beat cadence **only** at HUNT/LOCKDOWN; at LOCKDOWN non-focal panels dim to 40 % ("tunnel vision") |
| `prefers-reduced-motion` | Everything above becomes instantaneous; the ECG freezes to a static glyph + label; no stamp, no badge draw, no glow pulse |

**Budget rule (design doc §10):** no idle decorative motion, no glitch, no scanlines, no CRT, no emoji. Colour and motion are spent as tension rises; CALM is deliberately quiet.

### 2.15 Haptic mapping (D6)

`app/lib/soc/haptics.ts` defines the **cue** vocabulary; `mobile/src/platform/haptics.ts` maps cues to plugin calls. The web platform's haptics object is all no-ops.

| Game event | Cue | `@capacitor/haptics` call |
|---|---|---|
| Source row tap / disposition pick / settings toggle / queue row tap | `select` | `Haptics.selectionChanged()` |
| Hold-to-file progress at 0 / 180 / 360 ms | `hold-tick` | `Haptics.selectionChanged()` |
| A finding lands on the board (max 3 per pull) | `finding-land` | `Haptics.impact({ style: ImpactStyle.Light })` |
| "Start the shift" · Buy kit · Unlock card appears · payout count-up ends | `commit-soft` | `Haptics.impact({ style: ImpactStyle.Medium })` |
| Hold-to-file completes (the stamp) | `file` | `Haptics.impact({ style: ImpactStyle.Heavy })` |
| Debrief mount — right call | `verdict-good` | `Haptics.notification({ type: NotificationType.Success })` |
| Debrief mount — right verdict, off response | `verdict-off` | `Haptics.notification({ type: NotificationType.Warning })` |
| Debrief mount — wrong call | `verdict-wrong` | `Haptics.notification({ type: NotificationType.Error })` |
| `grade.breachDelta ≥ 30` as the meter sweeps | `breach-thud` | `impact(Heavy)` then `impact(Medium)` at **+90 ms** |
| Shift summary — clean / rough / breached | `shift-*` | `notification(Success / Warning / Error)` |
| Rank-up beat | `rankup` | `impact(Medium)` @0 · `impact(Medium)` @180 · `impact(Heavy)` @420 · `notification(Success)` @700 |
| Heartbeat **lub** (HUNT/LOCKDOWN only) | `beat-lub` | `Haptics.impact({ style: ImpactStyle.Heavy })` |
| Heartbeat **dub** (+120 ms) | `beat-dub` | `Haptics.impact({ style: ImpactStyle.Medium })` |
| Locked queue row tap (once per hub visit) | `denied` | `notification(Warning)` |
| Abandon confirmed · Reset career confirmed | `destructive` | `notification(Error)` |

**The heartbeat scheduler** (`app/lib/soc/heartbeat.ts`, pure, unit-tested):

```ts
heartbeatPlan(status: TraceStatus):
  CALM | ALERT → null                                    // silence is the reward
  HUNT      → { periodMs: 60000/112 ≈ 536, beats:[{at:0,"heavy"},{at:120,"medium"}] }
  LOCKDOWN  → { periodMs: 60000/150 = 400, beats:[{at:0,"heavy"},{at:120,"medium"}] }
```
Caps and guards, all in the pure scheduler so they are testable:
1. **Floor 400 ms** between lub-dub pairs (`MIN_PERIOD_MS`), so no status can ever buzz faster than 2.5 Hz.
2. **Auto-suspend after 40 s** of continuous beating; re-arms on the next status change or the next `PULL_SOURCE` — a player reading a long `why` is never buzzed for minutes.
3. Runs **only** while `phase === "investigating"` (never on hub, debrief, summary, or in a sheet).
4. Stops on `document.visibilitychange` **and** on `@capacitor/app`'s `appStateChange` → `isActive: false` (D6: never fires backgrounded).
5. Off when `settings.haptics === false` or `prefers-reduced-motion: reduce`.

No custom Swift plugin (the plugin has no pattern API; a lub-dub composed from two impacts is the v1 answer) and **no audio** — v1.1 at the earliest.

### 2.16 Colour and type tokens

All values already exist in the repo (`app/globals.css:5-11`, `SocConsole.tsx:43-80`). `app/styles/soc-theme.css`:

```css
@theme inline {
  --font-mono: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
  --font-sans: "Space Grotesk Variable", "Space Grotesk", system-ui, sans-serif;

  --color-ground: #010409;   /* globals --background */
  --color-panel:  #05080c;   /* SocConsole debrief card */
  --color-scrim:  #020408;   /* SocConsole overlay, used at 85% */
}
```

| Role | Token / class | Note |
|---|---|---|
| Ground | `#010409` | `--background` |
| Panel | `#05080c` / `bg-black/50` | hairlines `zinc-800/60`, radius 10 (cards) / 16 (sheets) |
| Text | `zinc-100` · `zinc-300` · `zinc-400` · `zinc-500` | nothing meaningful below `zinc-600` |
| **True Positive / breach / isolate** | `rose-300/400/500` | |
| **False Positive / neutral action / system chrome** | `cyan-300/400/500` | |
| **Benign-TP / good / progress / primary CTA** | `emerald-300/400/500` | |
| **Pressure / Tier-2 hand-up** | `amber-300/500` | |
| **Crossover (Shift 4) / milestone / unlock** | `fuchsia-400/500` | |
| Status ramp | `STATUS_COLOR`: CALM cyan · ALERT amber · HUNT orange · LOCKDOWN rose | Deliberate divergence from `--trace-calm: #10b981` (emerald), which is the **red seat's** token; the design doc §10 says CALM must be low-saturation cyan, "explicitly not bright green". |
| Edge glow | the existing inset `box-shadow` table | ALERT `.08` amber · HUNT `.14` orange · LOCKDOWN `.22` rose |

**Type — two voices.** IBM Plex Mono = the machine (labels, numbers, detection rules, asset strings, chips, ECG readouts, log-like evidence details, the stamp). Space Grotesk Variable = the human (alert titles, trigger prose, `why`, `learn`, Vale's messages, headlines).

| Role | Size | Face |
|---|---|---|
| Tracked uppercase label (`.18em`) | **11 pt — the hard floor** | mono |
| Meta / log / cost / chip | 13 pt | mono |
| Body | 15 pt / 1.55 | Grotesk (prose) or mono (log) |
| List-row title | 17 pt | Grotesk |
| Screen title | 22 pt | Grotesk |
| Hero / rank | 28 pt | Grotesk |
| Grade headline | 34 pt | Grotesk |

Numbers always `tabular-nums`. The ~42 nodes at 8.8–9.9 px in `SocConsole.tsx` (`text-[0.55rem]`…`text-[0.62rem]`) are **not** ported — they were the desktop grid's compromise. `overflow-wrap: anywhere` on `asset` and any sender string (`soc-phish-harvest`'s `it-support@m1crosoft-helpdesk.co` is a 33-char unbreakable token). Every `hover:` is paired with an `active:` (Tailwind v4 wraps `hover:` in `@media (hover:hover)`, so phones never see it). Glyphs, not emoji: `⬢ ⬡ ¢ ✓ ✗ ▸ ‹ ◉ ◔ ↗`.

### 2.17 The ≥1024 px rules

Exactly **two** `lg:` prefixes are permitted anywhere under `app/components/soc/deck/**`:

1. **`Sheet.tsx`** — below 1024 px a bottom sheet with a grabber; at `lg:` a centered dialog (`lg:max-w-[560px] lg:rounded-xl lg:top-1/2 lg:-translate-y-1/2`).
2. **`Board.tsx`** — below 1024 px it is a sheet; at `lg:` it renders inline as a fixed 260 px left rail beside the case (`lg:static lg:w-[260px] lg:translate-y-0`).

Everything else is width-agnostic: the deck column is `mx-auto max-w-[430px]` (hub `max-w-[560px]`) on the full-viewport cold-glass ground with the edge glow — cinematic on a desktop monitor, not a stretched phone. **Enforced in CI:**

```bash
grep -rn "lg:" app/components/soc/deck | grep -v -e "/Sheet.tsx" -e "/Board.tsx"   # must be empty
```

This replaces the nine responsive tokens in `SocConsole.tsx` (L367, L369, L431, L489, L635, L709, L828, L830, and the `md:` at L431).

---

## 3 · Shift 4 handoff (D4)

### 3.1 What changes

The three handoff cases are **kept**. They are pure functions of the `RED_RUNS` fixture (`HANDOFF_CASES = RED_RUNS.map(r => caseFromRedRun(r, S))`, `cases.ts:1564`) and need zero red-seat code at runtime; they are also the corpus's best identical-tradecraft Benign-TP/TP pair (`the-key` + `burn-notice` authorized vs `unsanctioned` not).

**The flag.** `SocFeatures.redSeat` — `true` on web, `false` on iOS.

**`app/lib/soc/shifts.ts`:**
```ts
shiftsFor({ redSeat: true })  === SHIFTS            // identity; web is byte-unchanged
shiftsFor({ redSeat: false }) === [                 // a remapped COPY; SHIFTS is never mutated
  { …first-shift,   unlockStanding:   0 },
  { …second-shift,  unlockStanding:  40 },
  { …lockout-shift, unlockStanding:  80 },          // was 90
  { …handoff-shift, unlockStanding: 120,            // was 90 + requiresRedRun
                    requiresRedRun: false,
                    label: "Shift 4 · the other chair (a red team's runs)",
                    note:  "Adjudicate a contracted red team's tradecraft from the blue side." },
  { …insider-shift, unlockStanding: 160 },          // was 210
]
```
`career.redRunsDone` stays in the schema at 0 — no synthesized red run, no faked career fields. `isUnlocked()` (`state.ts:118-122`) is untouched, so `state.test.ts`'s two red-run assertions (`SHIFTS[3].requiresRedRun === true` and the gate behaviour at standing 999) stay valid **because they read `SHIFTS`, not `shiftsFor()`**.

### 3.2 Re-voiced copy (seat-neutral, both surfaces)

Five strings, none asserted by a test:

| Location | Now | Becomes |
|---|---|---|
| `handoff.ts:202` (`why` opener) | "This alert IS a run you performed in the red seat…" | "This alert IS a red-team engagement's run, seen from your chair — the same board, the other seat." |
| `handoff.ts:211` (`trigger`) | ``${run.operator}'s session…`` | unchanged — `ghost_0x2A` reads correctly as the contractor's handle |
| `cases.ts:828` (`soc-edr-test` aside) | "(Your own red-seat run, seen from the blue chair.)" | "(A red-team engagement's run, seen from the blue chair.)" |
| `cases.ts:636` (`soc-auth-pentest` aside) | "(It's also the bridge between the two seats…)" | "(It's also the bridge to the red team's world: same tradecraft, opposite verdict.)" |
| Briefing handoff panel | "…YOU pulled off in the red seat" | `SOC_INTRO_COPY.handoff.blueOnly` / `.redSeat` — flag-selected |

The fuchsia case chip reads **"↔ red-team run"** in both modes (true in both). `caseFromRedRun(run, sources, opts?: { voice: "own-run" | "red-team" })` defaults to `"own-run"`, so `handoff.test.ts` keeps passing unchanged; `shiftsFor({redSeat:false})` requests `"red-team"`. `cases.ts` also gains `export const SOURCES = S` so `shifts.ts` can call the generator.

**Handler (`handler.ts`):** `inboxFor(c, ev, features = { redSeat: true, daily: true })`. With `redSeat: false`:
- `tip-redrun` ("Come sit in the other chair", L98-108) is **not emitted**;
- `ev-unlock-handoff-shift` (L85-96) becomes Vale: *"A contracted red team ran three engagements against us this month. One of them was never sanctioned. Shift 4 is their board, from your chair — go find it."*;
- the `t2` `ev-rankup` (L72-83) becomes Vale: *"That's Tier-2 · candidate. The desk is yours to run now — and Tier-2 is earned, not given. You earned it."*

Default behaviour is unchanged, so the web keeps Mercer and the cross-seat pull.

### 3.3 The ladder math (why the gates move)

Awards (`awardForShift`, `state.ts:88-102`, unchanged): **clean +40 ⬢**, rough +15, breached +5. Ranks (unchanged): Trainee 0 · Tier-1 40 · Tier-1 Senior 150 · Tier-2 candidate 210.

**If we only dropped the red-run gate and left standing thresholds at 0/40/90/90/210:**

| step | standing after | S3/S4 open at 90? | S5 open at 210? |
|---|---|---|---|
| clean S1 | 40 | no | no |
| clean S2 | 80 | **no — 10 short** | no |
| forced replay of S1 or S2 | 120 | yes | no |
| clean S3 | 160 | — | no |
| clean S4 | 200 | — | **no — 10 short** |
| second forced replay | 240 | — | yes |

That is **two mandatory replays of already-solved boards** (the player knows every verdict) inside a 24-case game — precisely the "cash/standing with nowhere to go" failure the progression audit flagged on the red side, and precisely what makes a reviewer read this as a demo. So the math *does* require lowering the gates (D4's condition is met).

**Blue-only gates 0 / 40 / 80 / 120 / 160:**

| step | standing after | unlocks | rank |
|---|---|---|---|
| start | 0 | Shift 1 | Trainee |
| clean Shift 1 | 40 | Shift 2 | **Tier-1 Analyst** (rank-up beat #1) |
| clean Shift 2 | 80 | Shift 3 | |
| clean Shift 3 | 120 | Shift 4 | |
| clean Shift 4 | 160 | Shift 5 | **Tier-1 · Senior** at 150 (rank-up beat #2, same session) |
| clean Shift 5 | 200 | — | |
| one clean Daily | 240 | — | **Tier-2 · candidate** at 210 → **campaign finale** |

**Exactly one clean shift per unlock, zero replays, and the finale lands on the Daily** — which is why the Daily exists and why it stays in v1. Rough shifts (+15) still bite hard: an all-rough player needs 3 boards for Shift 2, 6 for Shift 3, 8 for Shift 4, 11 for Shift 5. Quality still opens doors; incompetence still grinds. Ranks are deliberately **not** lowered — they are the long tail and the finale trigger.

**Web is unchanged:** 0 / 40 / 90 / 90 + red run / 210, Mercer's nudges intact, `SHIFTS` untouched, `state.test.ts` green. (Aside for the founder, out of scope here: the web has the same 80 < 90 stall, because red runs pay cash, not standing. `cases.ts:1630` → `80` is a one-number fix whenever you want it.)

---

## 4 · Content

### 4.1 Campaign

Unchanged: 24 cases (21 hand-authored + 3 generated), 5 shifts of 7 / 8 / 3 / 3 / 3, ~50–65 min for a first clean run-through. Authored order is preserved on a first play — it is pedagogy (TP → look-alike FP → subtle Benign-TP). Replays are allowed and pay out again.

What the UI does to slow recognition, given only 24 cases:
- upcoming queue rows show the **title only** — no severity chip (the tool's severity is a guess, and showing it primes the read);
- `neutral` and `noise` findings are visually indistinguishable from `decisive` ones during play;
- the Call sheet gives no thin/thorough hint before you commit;
- the debrief grades *investigation*, not just the verdict — "you pulled 2/3 of the sources that answer this case", and a blind call can never grade clean. A remembered verdict still has to be **proved**.

**Content roadmap (not in v1, one file, `cases.ts`):** the archetype × verdict grid is 10 × 3 with 24 cells filled unevenly. The 9 empty cells — encoded-powershell FP, dns-c2 Benign-TP, phishing FP, impossible-travel TP + Benign-TP, mfa-fatigue FP + Benign-TP, edr-malware FP, data-exfil FP — reuse existing sources, reinforce the "same detection, different verdict" thesis, and take the pool to 30, which is the point at which a Daily runs a week without a repeat and an endless mode becomes defensible.

### 4.2 Daily shift algorithm (`app/lib/soc/daily.ts`, pure, tested)

```ts
export function dailyShift(dateISO: string, recentIds: string[]): ShiftDef
```

1. **Seed.** `seed = fnv1a32(dateISO)` → `xorshift32` PRNG. Same date ⇒ same board for every player, no clock skew, no storage read inside the function.
2. **Pool.** `SOC_CASES.filter(c => !c.handoff)` — the 21 hand-authored cases. The 3 handoff cases are campaign-only (their framing depends on Shift 4's briefing).
3. **Recency.** `recentIds` = the case ids from the last **3** days' boards (≤15 ids), read from `sentry_soc_daily_v1`. Candidates exclude them. If fewer than 8 candidates remain, drop the oldest day from the exclusion set and retry — the function is **total** and never throws.
4. **Draw 5** by deterministic rejection sampling (≤200 attempts), subject to:
   - all three verdicts present (mirrors the invariant `cases.test.ts:103-106` enforces on authored shifts);
   - **≤ 2 per archetype**;
   - `FP + BenignTP ≥ TP` — real triage is mostly not-a-threat;
   - the board never **opens** with a TP (the first card is FP or Benign-TP — a daily starts calm).
5. **Fallback ladder** if sampling exhausts: drop rule (4d), then (4c), then (4b). (4a) is never dropped.
6. **Emit** `{ id: "daily-2026-09-05", label: "Daily shift · Fri 05 Sep", caseIds, unlockStanding: 40, kind: "daily" }`. It runs through `assembleShift(id, caseIds)` untouched.

**Economy.** Cash pays out every time; **standing is awarded once per calendar day** (`career.dailyDoneOn?: string`, merged safely by `loadCareer`'s spread over `INITIAL_CAREER`, so old saves load fine). Unlocked at ⬢ 40 so the fundamentals are learned in authored order first.

**Tests** (`daily.test.ts`): 366 consecutive dates satisfy every constraint; the same date twice yields identical `caseIds` in identical order; no case appears on two consecutive days; the fallback ladder is exercised with a starved pool; the function never throws for any date in 2026–2030.

**No endless mode in v1** (D5). 21 cases at ~2 min each is ~42 minutes before the first full repeat; shipping an endless mode over that pool would prove a reviewer's "demo" instinct right.

---


## 6 · App Store package

| Field | Value |
|---|---|
| App Store name | **SENTRY — SOC** |
| Subtitle | Tier-1 SOC analyst shifts |
| Home-screen name | SENTRY SOC |
| Bundle id | `pl.oumm.sentry.soc` (register on day 1 — the ASC record and internal TestFlight group can exist before the first archive) |
| Category | **Games › Puzzle**, secondary **Education** |
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait, iOS 16.0+ |
| Version / build | 1.0 / CI run number |
| Price | **Paid up-front** (Tier 5, $4.99) — zero StoreKit code, zero restore flow, and it keeps "Data Not Collected" trivially true. The design doc's $14.99 license belongs with a 60+ case corpus. No ads, no timers, no consumables, no loot — stated in-app under "Our promise". |

**Age rating (new 4+/9+/13+/16+/18+ questionnaire).** Text-only fictional security alerts trigger no Violence / Mature / Medical / Gambling / Unrestricted-Web-Access descriptor → computes **4+**. Run `grep -inE "damn|shit|fuck|kill|hostage|weapon" app/lib/soc/cases.ts` before answering (expect zero hits). Optionally raise voluntarily to 13+ for positioning (Apple allows raising, never lowering). **Do not add an embedded browser** — that alone forces 16+; the privacy link opens SFSafariViewController, which does not.

**Privacy.** Label: **Data Not Collected** — true only because v1 ships no analytics, crash SDK, account, or network call (Apple's own opt-in crash reports are fine). Guideline 5.1.1(i) still requires a privacy-policy link **in App Store Connect metadata AND inside the app** even at zero collection → Settings › Privacy policy → `https://<worker>/privacy`, backed by the new static `app/privacy/page.tsx` on the existing Cloudflare deploy (no new infra).

**Info.plist.** `ITSAppUsesNonExemptEncryption = NO` (skips the export questionnaire on every upload), `UIStatusBarStyle = UIStatusBarStyleLightContent`, `UIViewControllerBasedStatusBarAppearance = YES`, portrait-only orientations, `UIRequiresFullScreen = YES`. Built with Xcode 26.2 / iOS 26 SDK (mandatory for uploads since 2026-04-28 — satisfied).

**Notes for Review (2.3.1 — specificity is the requirement).**
> SENTRY — SOC is a fictional, offline single-player deduction game about a Tier-1 security-operations analyst. The player reads fabricated alerts, chooses which fabricated log excerpts to consult, and classifies each alert as a true positive, a false positive, or authorized (benign) activity; a debrief then explains the reasoning. The content is defensive and educational: it teaches how an analyst reads evidence, and never depicts a working attack or evasion technique. No real organisations, systems, credentials, or data appear — every host, user, domain and log line is invented. Public MITRE ATT&CK® technique identifiers are cited as glossary references only. All content is bundled: there is no account, no login, no network request, no advertising, no user-generated content, no third-party AI, and no in-app purchase. Native features: haptic feedback (UIKit feedback generators) for the alert heartbeat and for filing a call, a native splash screen, and full offline play with local save. Precedent: Uplink and Hacknet. To reach every screen quickly: Desk → Clock in → tap any data source → Make the call → Next alert; the shift summary appears after 7 alerts (~12 minutes). Haptics can be turned off in Settings, which also contains the fiction disclaimer and the privacy policy link.

**4.2 "repackaged website" defence.** Native splash with no white flash → canvas ECG System Bar → haptic hold-to-file and stamp → full offline → safe-area-correct portrait chrome → no browser chrome and no outbound link inside the game loop → sheets and gestures, not pages. App Store screenshots (6.9" from the 17 Pro Max simulator) show gameplay: hub, case, evidence board, the call, the debrief stamp, the rank-up. Submit a TestFlight build first (the design doc's "submit early" rule) and budget 2–4 weeks of review iteration.

---

## 7 · Risks — every risk raised by any proposal, resolved or explicitly accepted

| # | Risk (source) | Resolution |
|---|---|---|
| R1 | **Two Tailwind versions in the tree** — `@tailwindcss/postcss@4.1.18` (Next) vs a nested `@tailwindcss/vite@4.3.3` (Vite). Same class could compile differently on web vs iOS. **This is real right now, not hypothetical.** | T7 pins all three to 4.3.3 exactly; `npm ls tailwindcss` must print one deduped version — an acceptance criterion. `@source "../../app/components/soc"` in `mobile/src/styles.css` covers the whole component tree. |
| R2 | Shared components silently regain a Next-only or red-seat dependency and the iOS build breaks weeks later | `no-restricted-imports` ESLint override on `app/components/soc/**`, `app/lib/soc/**`, `app/lib/career/**` (§1.6) **plus** `npm run mobile:build` in `npm run check` and in CI — it needs no Xcode, so every PR proves the contract. |
| R3 | App Review **4.2 / 4.3** rejects a WKWebView game as a repackaged website | Native splash, haptics on every meaningful action, safe-area chrome, offline-only, no outbound links in the loop, gameplay screenshots, specific Notes for Review naming Uplink/Hacknet (§6). TestFlight first so Apple's verdict arrives while the codebase is small. |
| R4 | 24 cases / ~50–65 min reads as a demo (**2.1 / 2.2 "lasting value"**) | Campaign + career ladder + Daily shift; the hub reads complete (no "coming soon" cards); priced as a small finished game, not a $14.99 license; the 9 grid-gap cases are the queued v1.1 content drop. |
| R5 | The **taxonomy** FP-vs-Benign-TP decision lands mid-build and collides with the copy move | Every taxonomy string moves **verbatim** into `app/lib/soc/copy.ts` in T1, which lands on day 1. The parallel workflow then edits one file and both surfaces change. If their PR merges first, T1 rebases and re-moves the new wording — either order works, the slot exists in both. |
| R6 | **Career loss:** WKWebView evicts `localStorage` under disk pressure; or Preferences hydration races React and overwrites a good save with `INITIAL_CAREER` | Preferences (UserDefaults) is the durable store, `localStorage` the synchronous cache; `hydrateStorage()` is **awaited before `createRoot().render()`** with the splash still up; `saveCareer` never writes `INITIAL_CAREER` except on an explicit double-confirmed reset. The session snapshot means even a mid-shift kill loses nothing. Verified by kill-and-relaunch on the simulator. |
| R7 | `@capacitor/haptics` has **no pattern API**; a composed lub-dub at 150 bpm feels like a buzz, annoys, or drains battery | Heartbeat only at HUNT/LOCKDOWN, only while `phase === "investigating"`, 400 ms floor, 40 s auto-suspend, paused on background/visibility change, Settings toggle, reduced-motion respected (§2.15). Silence at CALM/ALERT is the reward. A ~40-line Core Haptics Swift plugin is the documented v1.1 upgrade path. |
| R8 | Fontsource's variable family is **`Space Grotesk Variable`**, not `Space Grotesk` → silent fallback to `system-ui` | `--font-sans` lists both names; `SplashScreen.hide()` waits on `document.fonts.ready`; the screenshot gate checks the Grotesk `g` and the Plex Mono `0`; the same CSS renders in Chrome first, so a fallback is visible before the simulator. |
| R9 | Swapping the web to Plex Mono changes the look the founder has been approving (today's SOC is SF Mono via `ui-monospace`) | Called out explicitly (§1.9). It is the design doc §10 intent, it is in the ≥1024 px screenshot gate, and it is reversible with one line in `soc-theme.css` if the founder prefers system mono. |
| R10 | Safe areas break: `env()` reads 0, the Dock hides under the home indicator, or hiding the status bar zeroes the top inset on iOS 26 | `viewport-fit=cover` in `mobile/index.html`; `ios.contentInset: "never"`; the status bar **stays visible** with light glyphs via `SystemBars.setStyle({style:"DARK"})`; `Screen` and `Dock` primitives own the insets so no screen re-implements them; `100dvh` not `100vh`; verified on the Dynamic Island simulator in T8. |
| R11 | Tailwind v4 gates `hover:` behind `@media (hover:hover)` → taps look dead; and `title=` tooltips carry meaning nobody on iOS can see | Every control ships an `active:` variant (`TONE` in `theme.ts` is extended with them); `-webkit-tap-highlight-color: transparent`; fear/standing/cash explainers become visible text on the Board sheet and Hub. |
| R12 | The phone UI reads as a "shrunk desktop" and fails the founder's aesthetic bar | The Deck is written against these wireframes at the 11 pt floor / 44 pt targets from the first commit, never derived from the grid. T11 is a dedicated screenshot gate (every screen at 390×844 and 440×956, plus 375×667 for the SE class) with founder sign-off on hub / case / debrief **before** the archive; defects route back to the owning ticket. |
| R13 | Apple account / signing / ASC friction eats the last day (bundle id unregistered, agreements, processing, compliance key) | T7 registers `pl.oumm.sentry.soc`, creates the ASC record and the internal TestFlight group **in parallel with the code**; `ITSAppUsesNonExemptEncryption=NO` is in the plist from the start; the first archive uploads as soon as T8 passes even if polish continues, so processing and rejections surface early. |
| R14 | A live-reload `server.url` or the dev QA-jumps menu ships to reviewers | `server` is only present when `CAP_DEV_URL` is set at sync time and is never a committed value; `scripts/check-release-guard.sh` fails if `ios/App/App/capacitor.config.json` contains `"url"` or if the release bundle contains `applyDemo`/`QA jumps`; the dev menu compiles only under `import.meta.env.DEV`. |
| R15 | **SPM / signing reproducibility** across machines | `ios/` is committed including `CapApp-SPM/Package.swift` and `Package.resolved`; every Capacitor package is pinned exact; `docs/IOS-BUILD.md` records Xcode 26.2 (17C52), Node ≥22 and the exact command sequence; `cap sync` is idempotent. |
| R16 | Retuning the standing ladder breaks web expectations or `state.test.ts` | The blue-only ladder lives in `shiftsFor({redSeat:false})` and returns a **copy**; `SHIFTS`, `RANKS` and `isUnlocked` are untouched, so `state.test.ts:71-92` stays green. `shifts.test.ts` covers both modes. |
| R17 | Parallel agents collide on `package.json`, `cases.ts`, or the composition root | §8's files-owned lists are disjoint and exhaustive; **only T7** touches `package.json`/`tsconfig`/`eslint`/`.gitignore`; **only T5** touches `cases.ts`/`handoff.ts`/`handler.ts`; **only T6** owns `SocApp.tsx`; **only T10** touches `app/soc/page.tsx` and deletes the old components. `deck/types.ts` (T2) is frozen on day 1 and published in the PR description within the first hour so dependents code against a fixed contract. |
| R18 | The founder's working tree is dirty (`GuidedOnboarding.tsx`, `HandlerPanel.tsx`, `MapCanvas.tsx`, `contentPack.ts`, `reducer.ts`) | No ticket touches any red-seat file. The font swap preserves the literal family name `"IBM Plex Mono"`, so `MapCanvas.tsx:403`'s `ctx.font` needs no edit — the dirty files never enter a diff. |
| R19 | Vite and Next disagree on TS/ESLint (`import.meta.env`, JSX runtime, alias) and `next build` starts type-checking `mobile/` | Root tsconfig excludes `mobile`/`ios`; `mobile/tsconfig.json` re-includes with `types:["vite/client"]` and `plugins:[]`; the alias is an explicit `resolve.alias`, not a plugin; `npm run check` runs lint + vitest + `next build` + `vite build`. |
| R20 | Hold-to-file is friction, or inaccessible | 550 ms with a visible ring and haptic ticks, cancels on release, 64 pt target, and a **Settings toggle** to two-tap filing. Reduced-motion keeps the ring static. |
| R21 | Heartbeat/ECG canvas cost on battery, or effort creep on the polish items | ECG is a single rAF canvas that pauses when not `investigating`, when hidden, and under reduced motion (it degrades to the existing dot + label, which is the documented fallback if the canvas slips). The MVP line inside the tickets ships without evidence mark-as-key, edge-swipe-back, and the finale recap. |
| R22 | **Accepted:** the debrief's `learn.pointer` (LetsDefend etc.) stays plain text in v1 | Accepted deliberately. External commerce/affiliate links inside the game loop are an App Store risk and a design-doc violation ("never a mid-mission interrupt"); the sole outbound link is the privacy policy. Tappable pointers via SFSafariViewController are a v1.1 item. |
| R23 | **Accepted:** no abandon-recovery of a mid-shift *score* — abandoning loses the queue's progress | Accepted. The session snapshot covers crashes and app kills; a deliberate abandon is a deliberate loss, confirmed behind a sheet. Anything finer needs a `CareerState` schema change. |
| R24 | **Accepted:** the `?demo=` fixtures do not exist on iOS release builds | Accepted. They are a web/dev affordance; the dev-only QA-jumps row covers the screenshot workflow, and shipping them would be a 4.2 liability ("feels like a prototype"). |
| R25 | **Accepted:** iPad users get the iPhone app scaled, or nothing | Accepted for v1 (`TARGETED_DEVICE_FAMILY = 1`). It avoids the iPadOS 26 window-control overlap, a second screenshot set, and a landscape layout — all v1.1. |

---


---

## Appendix A — amendments carried from the earlier addendum (§C, §F, §G)

## C. State machine additions (T1)
- **G5** New action `VIEW_RESULT(caseId)`: from `investigating` (via the Board's done rows) or
  `complete` (glyph recap) → `debrief` with `readOnly: true`; `NEXT_CASE` from a read-only
  debrief returns to the originating phase. Guard: `caseId ∈ shift.results`. Reducer test.
- **G6** `CONTINUE` is removed; `complete → NEXT_CASE → milestone | hub`.
- **G19** New action `ACK_FIRSTRUN`: `FirstRun` dispatches it; `useSocSession` persists
  `sentry_soc_firstrun_v1`. Components never write storage directly.
- **G7** `completeShift()` writes `career.dailyDoneOn = todayISO` when the finished shift is the
  daily one and suppresses the standing award if `dailyDoneOn === todayISO` already (cash still
  pays — grind-friendly). `STORAGE_KEYS.daily = "sentry_soc_daily_v1"` holds the recency ledger
  `{ dates: [{ date, caseIds }] }` (last 7 days). `shiftBoard(features, todayISO, recentIds)`.
- Action count is therefore **17**: the 15 of §2.1 minus `CONTINUE` plus `VIEW_RESULT`,
  `ACK_FIRSTRUN`. T1 acceptance #1 reads "the 17 actions".

## F. Acceptance-criteria rewrites (G16, G17)
- T3 #1 / T4 #1 "matches wireframes" → replaced by the enumerable sub-bullets already present +
  "screenshots committed under the owned `docs/screenshots/deck/*` path; visual defects are
  filed as a list in the ticket's final report for T11".
- T2 #1 → "`deck/types.ts` is the FIRST file written and contains an interface for each of the
  nine screens plus `ScreenName`; T3/T4 must import from it and add no props of their own without
  extending it there (T2 owns the file; T3/T4 propose additions in their report)".
  Practical rule for the parallel run: **T2 publishes `types.ts` before T3/T4 start** — the
  workflow stages guarantee this by ordering.
- **G17** T1 acceptance: "`haptics.ts` exports the `SocCue` union of the 15 cues in §2.15,
  `noopHaptics: SocHaptics`, and `cueTiming` (the multi-impact patterns with offsets)".

## G. Guardrails (G20, G21) — T5
- `app/lib/soc/guardrails.test.ts` (T5 files-owned): (i) no `/\$\s?\d|salary|salaries|per year|\bpay\b\s*(range|band|of)\s*\d|USD|EUR|PLN/i`
  match in `cases.ts`, `copy.ts`, `handler.ts`; (ii) `DISCLAIMER_SHORT`/`DISCLAIMER_LONG`
  non-empty and imported by both `FirstRun.tsx` and `Settings.tsx` (grep-based test);
  (iii) every FP case's `why` contains none of `/\bsanctioned\b|\bauthori[sz]ed\b|benign true positive/i`
  used as the verdict justification, and every B-TP case's `why` contains none of
  `/detection (misfired|was wrong)|false alarm/i` — the corpus-vs-definition invariant (**G15**).
- **G21** `LADDER_COPY` re-voiced: "Credentials people in this chair often cite: BTL1, NICE
  'Cyber Defense Analyst'. This is fiction — not a certification, not a training platform, and it
  makes no claims about hiring or pay."

