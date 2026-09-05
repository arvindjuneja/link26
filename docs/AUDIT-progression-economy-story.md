# Audit — progression, economy, story (2026-07-12)

Triggered by three player critiques + "finish the whole game once." I completed a
full 15/15 clean campaign playthrough in a real browser (all three acts, the
"Nobody" finale) and cross-checked against the code. Verdicts below combine the
firsthand run with a source audit.

## The playthrough happened
Fresh save → all 15 chapters, every one a clean exit (streak ×15). Ended with
**CASH 78,020c, REP 452**. The campaign spine is Act I "The Scared Freelancer"
(First Light → Paper Trail → Dead Air → The Key → Ghost) → Act II "The Operator"
(Known Quantity → Crossed Wires → The Tell → Burn Notice → Operator) → Act III
"The Hunt" (Tripwire → Listening Post → Cold Storage → Scrub → **Nobody**). The full
copy-pasteable command playbook is in the session workflow output.

---

## (a) "Missions should be earned / gated" — PARTIALLY VALID
Two mission systems, opposite behavior:
- **Campaign spine IS gated**, but only *sequentially* — finishing chapter N flips
  N+1 from locked→available (`reducer.ts:365-373`; `accept` refuses locked at
  `:276-279`). There is **no rep/cash/skill gate anywhere** — starting rep 36 is
  never checked. Ordering, but no *earning*.
- **The contract board is NOT gated at all.** `generateMissions` stamps all ~13
  board contracts `available` at world-gen (`missions.ts:100-113`) — a fresh player
  sees high-value targets (`iris`, `solstice`) open immediately. This is the "flood
  of missions I never earned" you reacted to.
- **Reputation gates nothing** — it's a score with no consumer.

**Fix:** gate the board behind reputation tiers (rep already tracked + rewarded,
currently inert). Low-rep jobs at start; marquee targets locked until you've built a
name. One filter turns rep into real progression *and* gives it a sink.

## (b) "Cash with nowhere to spend it" — VALID
- Only **two** cash sinks exist: gear purchase and `churn` (`reducer.ts:1137`,
  `:1100`). The `MarketPanel` "Browse (coming soon)" is a stub (`MarketPanel.tsx:10-12`).
- Gear catalog = **4 items, ~46,800c one-time ceiling** (`gear.ts`). It does matter
  (up to ~48% NETWORK noise cut) but it's a one-time buy.
- I finished with **78k cash** having bought nothing and never needing to — income
  (~83k–110k/run) dwarfs the ~47k ceiling by ~2:1. `churn` only fires if ATTRIBUTION
  is dirty (mine stayed 0). Cash maxes out and stops mattering.

**Fix:** convert the one-time gear sink into **recurring per-run operating costs**
(consumable one-shots, burner-proxy upkeep, churn as routine) so cash is a resource
you manage each mission instead of a number that caps.

## (c) "Where is the game story?" — PARTIALLY VALID
The claim "there's no story" is *wrong*; the experience "I never met a story" is
*right*.
- A real 3-act, 15-chapter arc exists (`campaign.ts`) with recurring characters
  (handler Mercer; hunter Iris; Polaris the incriminating job) and a script-flip:
  fear-of-trace → you're-known → you-are-the-target. Each chapter has intro + outro.
- A written ending exists and it's **good** (the "Nobody" outro — *"you came in a
  scared freelancer; you leave a ghost story… Mercer out — for real, this time."*).
- **But it's invisible.** The whole narrative is `MERCER:` lines in terminal
  scrollback + a 4-line campaign panel. Confirmed firsthand: finishing the game
  produced **no ending screen, no credits, no summary** — the climax scrolled past
  and dumped me on the open board. Two story-less systems (30 pack contracts, the
  separate SOC career ladder) drown out the one arc that has a story.

**Fix (highest-leverage, lowest-ambiguity):** don't write a story — *surface* it.
Promote the "Nobody" finale to a real ending beat (dedicated screen/modal: the outro
text, run stats, clean-streak, "you're a ghost story now", a way back to the board /
to the SOC desk). Optionally gate the campaign as *the* spine so the arc announces
itself.

---

## Priority
1. **Ending beat** — pure win, content already written, directly answers (c).
2. **Rep-gated board** — fixes (a) and gives rep a purpose; moderate work.
3. **Recurring economy** — fixes (b); needs balance tuning.
