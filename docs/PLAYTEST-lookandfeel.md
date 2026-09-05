# Playtest — look & feel pass (2026-07-11)

Played as a fresh first-time user in a real Chrome window at 1440×900 and 390×844
(mobile). Cleared localStorage/IndexedDB first so onboarding ran from zero. Went
through the red-seat guided tutorial + free play, then both SOC blue-seat cases.
Timings and reactions are a real player's, not the engine's.

Severity: **P0** breaks the first-run experience · **P1** clearly hurts feel ·
**P2** polish · **FLAG** = design decision for you, not auto-fixed.

---

## Red seat (operator cockpit)

### What already feels great — keep it
- **Guided onboarding pacing.** Each step drops its own focused input in the coach
  bubble, so you never hunt for the terminal. Type → Enter → staged result →
  bubble advances. Smooth, never got lost.
- **The proxy payoff lands.** Direct `connect hq-node` spiked NETWORK 0→35% and
  TRACE→34% (CALM→ALERT) in a visible ~1s jump — which sets up Mercer's "wait,
  WAIT" panic beat. Then after building a 1-hop route, the *same* connect barely
  moved NETWORK (~23%). Feeling the difference is the whole lesson, and it works.
- **Staged terminal output** (CONNECT → ROUTE warn → HANDSHAKE → SESSION → TRACE)
  reads like a real session and gives the map animation room to breathe.

### P0 — Post-tutorial LOCKDOWN trap
The tutorial ends with the player **still connected to hq-node** and in HUNT. There
is no `disconnect` step and nothing warns you. I did the natural thing — read the
newly-revealed panels and accepted the next mission from the inbox — and in ~30–60s
of *normal reading* the trace climbed **HUNT → 93% → 100% LOCKDOWN / "IDENTITY
COMPROMISED"**, whole screen pulsing red. A brand-new player gets punished for
exploring the UI they were just handed.
- Made worse by the idle nudge (below), which tells a still-connected player to
  *act*, never to disconnect.
- Code: `GuidedOnboarding.tsx` outro handler resets nothing; `submit` in
  `reducer.ts` never clears `session.connectedHost`; dwell clock adds ~+2.5
  NETWORK/tick (per 3s) while connected (`exposure.ts` `DWELL_NOISE`).
- **Fix shipped:** auto-`disconnect` when the tutorial's "Start playing" is
  pressed, with diegetic outro copy ("I've pulled you off the line").

### P1 — Mercer idle nudge is connection-blind
`deriveSituation` (`HandlerPanel.tsx`) picks `idle_nudge` purely on
`acceptedCount === 0`; it never checks `connected`. So a player parked on a live
session with no mission hears *"Move or fold / clock's running"* — the opposite of
the correct advice (get off the line). 
- **Fix shipped:** new `connected_idle` situation + Mercer lines that tell a
  connected, mission-less player to disconnect and cool the trace.

### P1 — `cp` prints the wrong filename
Tutorial tells you to `cp /secrets.txt @local`; the terminal replies *"Copied
**asset_register.txt** into inventory."* The reducer printed the file's internal
`name` field instead of the path you typed (`reducer.ts` cp case). Small, but it's
the very first "did I do that right?" moment and it reads like a bug.
- **Fix shipped:** echo the source the player typed → *"Copied /secrets.txt …"*.

### P1 — Mobile map header collision (390px)
The map header stacks three absolutely-positioned clusters on one row — "NETWORK
MAP" (left), the centered TRACE bar, and the Proxy/Target legend + Full button
(right). At phone width they physically overlap: "NETWORK MA**TRACE**" and
"**HUNT**Proxy". This is the red-seat mobile collision returning in the header.
- **Fix shipped:** hide the decorative "NETWORK MAP" label and the Proxy/Target
  legend below `sm`; keep the trace read-out and Full toggle.

### P2 — The connection/scan beam could be more cinematic
The user's explicit ask: does the animation get enough space, does it feel
movie-like? The beam is real (cyan dashed line sweeping player→proxy→target with an
arrival ring) but thin (2px, shadowBlur 10) and quick (~600–800ms/phase); on the
big cockpit map it's easy to miss. The idle Full-screen map is also very static.
- **Fix shipped:** thicker/brighter beam, a soft outer glow-pass, a larger fading
  arrival ring, and a brighter leading pulse; slightly longer phase durations so
  the sweep is legible. Tasteful — the 20fps throttle and tab-hidden pause stay.

### P2 — Free-play layout is scroll-heavy
The terminal (primary surface) is top-right in a 72vh cockpit, but the Mission
Inbox — where a new player must go next — is the 3rd cell of a grid far below four
full-width panels. After the tutorial you're dropped at the top with "No active
mission" and the thing you need is offscreen. Not fixed here (bigger layout
decision); noting for a future pass. A cheap win: surface an "accept a contract ↓"
affordance near the terminal when there's no active mission.

---

## SOC blue seat (SENTRY desk)

This half is the more polished, and pedagogically strong.

### What's great
- Clean, calm home (career ladder, shift queues, Vale's inbox, analyst kit).
- Shift-handover intro states the three verdicts (TP / FP / Benign-TP) and the
  BREACH-RISK / NOISE meters before you touch anything.
- Investigation loop is excellent: each data source is labeled with *the question
  it answers* and a time cost; evidence board builds; the call is gated behind
  "investigate first"; shift-pressure accrues.
- **Debriefs are the standout.** Case 1 (encoded PowerShell → I escalated/isolated)
  returned "GOOD CALL · True Positive" with a clear WHY, the decisive findings, a
  "you pulled 2/3 sources" coverage note, and a real **MITRE ATT&CK T1059.001** +
  LetsDefend reference. Wrong calls still get partial credit and a graceful WHY.

### FLAG — Benign-TP vs False-Positive taxonomy (your call, not auto-fixed)
Case 2 (rkhan: 12× failed logons then success, Monday 09:05). Evidence: all from
the user's **own keyboard**, a helpdesk **"forgot my password after the weekend
reset"** ticket 2 min prior, no remote/VPN/foreign IP. I called **Benign
(authorized)** — because the shift intro defines a Benign-TP as *"the detection was
right, but the activity was authorized,"* which fits exactly. The game scored it
**WRONG, truth = False Positive** ("the rule fired on a real pattern, but there's no
threat").
- Both readings are defensible in the real field, but the game **teaches one
  definition in the intro and then grades by the other** — so a player who
  correctly applies what they were just told gets marked wrong. Recommend either
  (a) re-tag this case as Benign-TP, or (b) tighten the intro so "detection was
  right but authorized" vs "rule misfired on benign noise" are clearly separated.
  Left for your decision.

**RESOLVED 2026-09-05 — option (b).** DEF-A is canonical ("did the attack behaviour
the rule hunts for actually happen?"); rkhan stays FP; intro, buttons, engine strings
and case copy tightened. See docs/DECISION-soc-taxonomy.md.

### P2 — coaching tooltip overlap
The first coaching bubble (step 1/3) overlapped the alert-detail header. Minor;
readable.

**PARTLY FIXED 2026-09-05.** The bubble no longer assumes its own height: it measures
the card and places itself above or below the anchor from that measurement, clamped
into the viewport, and scrolls the anchor into view once per step. Verified headless
(Chrome/CDP, `next dev`) at 1280x900 and 390x844: at all three steps the bubble stays
on screen and never covers its own anchor ring — step 3/3 clears the disposition
buttons by 8px at both widths. The residual step-1 overlap is with a *non-anchor*
panel and is unchanged.

---

## Fix summary (this pass)
| # | Sev | Area | File(s) |
|---|-----|------|---------|
| 1 | P0 | Auto-disconnect after tutorial | `GuidedOnboarding.tsx` |
| 2 | P1 | Connection-aware Mercer nudge | `HandlerPanel.tsx`, `contentPack.ts` |
| 3 | P1 | `cp` filename echo | `reducer.ts` |
| 4 | P1 | Mobile map-header collision | `MapCanvas.tsx` |
| 5 | P2 | Cinematic connect beam | `MapCanvas.tsx` |

FLAGged (no code change): SOC FP/Benign taxonomy (resolved 2026-09-05); free-play scroll depth; SOC
coaching overlap.
