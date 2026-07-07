# SOC blue seat — playtest (validate the bet)

> **The one question this playtest resolves:** *Is the core loop — pull the right logs →
> read the evidence → make the call — **fun as deduction**?* (Everything else — more
> archetypes, the career shell, shipping — waits on a "yes".) You are the only person who
> can answer it; this guide just removes the friction and points your attention.

## Start in 60 seconds
```bash
npm run dev          # then open:
#   http://localhost:3000/soc     ← the blue seat (SOC analyst)
#   http://localhost:3000/        ← the red seat (the operator), for contrast
```
- First run shows a one-time **"shift lead" coach** on the opening case — follow it; it teaches the loop, then retires.
- **"New shift"** (end-of-shift button) rotates through the 5 shifts. `↩ red seat` jumps to the operator game.
- Pre-flighted 2026-07-04: a full Shift 1 plays clean end-to-end (7/7, 0 errors). The small **"N" bottom-left is the Next.js dev badge** — ignore it.

## What to play (~20–30 min, or 10 min for the short path)
Rotate through the shifts on "New shift":
1. **Shift 1 · fundamentals** — encoded PowerShell, auth, DNS C2. Learn the loop + the 3-way call.
2. **Shift 2 · phishing / identity / EDR / exfil** — the breadth.
3. **Shift 3 · the lockout queue** — where *most* alerts are benign (the FP-heavy reality).
4. **Shift 4 · the other chair** — the **Red↔Blue handoff**: cases generated from *your own red run*.
5. **Shift 5 · the insider desk** — context (not the action) decides; *escalate, don't isolate*.

**Short on time?** Play **Shift 1** (the loop) + **Shift 4** (the handoff wow) — those two carry the thesis.

## What to notice (the 9 prompts)
As you play, watch for these — they're what the bet turns on:
1. **The call.** Does choosing **True Positive / False Positive / Benign True Positive** feel like a real *judgment* — or a coin-flip? Is there an **"aha"** when the evidence resolves it?
2. **Investigation.** Does pulling the *right* log (vs a wrong one) feel meaningful? Does **"which log answers which question"** land?
3. **Same detection, opposite verdict.** The malicious-vs-benign pairs (encoded-PS *cradle* vs *patch-agent*; impossible-travel *compromise* vs *corporate-VPN*). Does the discriminator click?
4. **Tension.** Do **BREACH RISK / NOISE** + "a blind call can't grade clean" create stakes — or is it flat? (Try *guessing blind* on one case to feel the penalty.)
5. **The debrief.** Does the *why* + *learn-for-real* (MITRE, the real concept) feel **rewarding / like you learned something**?
6. **The handoff (Shift 4).** Does *"your own red run, seen from the blue chair"* land as a **wow**?
7. **The insider twist (Shift 5).** Does *"escalate to HR/legal, don't isolate"* feel like a genuine, satisfying inversion?
8. **Pace & friction.** Is a shift the right length? Too many clicks? Any boring beats? Anything confusing?
9. **The retention question.** After a shift or two — **would you play shift #7?**

## Things I'd specifically watch (honest friction candidates)
- **No audio.** The red seat has an *audible* heartbeat that carries its dread; the SOC breach/noise heartbeat is **visual only**. Does the tension land without sound — or does the blue seat need its own audio pulse?
- **Where the tension lives.** Stakes currently come from the *call* (breach/noise) more than the *investigation* (time isn't scored). Does the investigation phase itself feel tense enough, or is it "read then decide"?
- **Deduction vs recognition.** After a few cases, are you *deducing* (weighing evidence) or *pattern-matching* the archetype? (Some recognition is fine; too much = shallow.)
- **No progress/persistence** (each session starts at Shift 1) — fine for a playtest; note if it bugs you.

## Scorecard (fill in)
Rate 1–5 (1 = flat, 5 = genuinely fun):

| Dimension | 1–5 | Note |
|---|---|---|
| The call feels like real judgment (aha moments) | | |
| Investigation / "which log answers the question" | | |
| Same-detection-opposite-verdict clicks | | |
| Tension (breach/noise, blind-call penalty) | | |
| Debrief teaches / rewards | | |
| Handoff (Shift 4) — the wow | | |
| Insider twist (Shift 5) | | |
| Pace / friction (5 = smooth) | | |
| Retention — would you play shift #7? | | |

**The verdict (the whole point):**
- Is the blue-seat deduction **fun enough to keep building the career sim around it**?
  → **YES** / **NO** / **YES, but it needs: ________**

## What a "yes / no / yes-but" unlocks next
- **YES** → build the **career shell** (landing + 3 seats + ladder + progression) and re-center `GAME_DESIGN.md` on the 3-seat sim; then the shippability gate (server-authoritative economy / the cheat hole) before any public build.
- **YES, but ___** → fix the named thing first (likely candidates from above: audio, investigation tension, pace) — cheap and targeted.
- **NO** → stop and diagnose *why* the deduction falls flat before building more — the content depth won't save a loop that isn't fun.
