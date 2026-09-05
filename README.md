# Link26 → GHOST26 / SENTRY

> *An arcade **cybersecurity career-path** sim. Uplink's heart, reborn for 2026 — now with the other chair.*

**Two seats, one world.** In the **red seat** you're a signals operator: footprint a
person, task a sensor, crack a network, and get out before anyone realizes you were
there. In the **blue seat** you're a Tier-1 SOC analyst working a queue of alerts: pull
the right logs, read what actually happened, and make the call. The twist that binds
them: **your own red-team run, seen from the blue chair, is a case you have to adjudicate.**

This started as a browser homage to Introversion's **Uplink** and is being
re-architected into a viable, cybersec-credible **career sim** spanning **Blue (SOC
analyst) · Red (authorized offense) · Blackhat (off-book)** — three chairs sharing one
engine. Full vision, decisions, and roadmap live in
**[docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)**. (Working title; final name — GHOST26 vs
NULLROUTE vs Link26 — undecided.)

## It's an arcade simulator — not a how-to

| WE DEPICT | WE NEVER DEPICT |
|---|---|
| Real workflow shapes & phase names (recon → access → action) | Working commands, exploits, or payloads |
| What tools/disciplines are *for*, abstractly | Anything that transfers to a real system |
| Risk/reward tradeoffs as game stats | Real targets, data, or credentials |
| The ethics & rules of engagement | Person identification, tracking, or surveillance |

Credibility comes from authentic vocabulary, accurate mental models, and respect for
the craft — never from transferable attack instructions. The **blue-seat** content is
held to a higher accuracy bar (it's grounded in adversarially-verified research against
Microsoft / CISA / MITRE primaries) because the career framing ties to real learning;
no pay/salary figures are ever presented as fact.

## The blue seat — Tier-1 SOC analyst (`/soc`)

A **shift** is a queue of alerts. Every alert resolves to exactly ONE call — the real
Tier-1 decision (and, verified, Microsoft's own alert taxonomy). One question decides it:
**did the attack behaviour the rule hunts for actually happen?**

- **False Positive** — the behaviour the rule hunts for never happened; ordinary
  activity only looked like it → close (fix the rule).
- **Benign True Positive** — it happened, and a sanction (a pentest, a change
  ticket, a known tool) covers it → close benign.
- **True Positive** — it happened and nothing sanctioned it → escalate (Tier 2,
  or IR + isolate).

Per alert you **pull the right data sources** — each carries the *question it answers*
("which log answers which question": auth → 4624/4625/4672, C2 → DNS, lineage → EDR
process tree, identity → Entra sign-in risk, email → SPF/DKIM/DMARC) — assemble the
**evidence**, then make the call. Grading is a deterministic predicate (the same crisp,
un-gameable shape as the red seat's `evaluateMission`).

- **Two pressure meters** reuse the red seat's engine: **BREACH RISK** (the trace
  heartbeat *inverted* — a real threat you close and miss is now *dwelling*, so the dread
  is the adversary's clock) and **NOISE** (crying wolf — escalating noise or
  isolating authorized work buries Tier-2).
- **Investigation matters.** Pulling the logs that actually answer the case is the skill
  — a right verdict reached *blind* (no key logs pulled) is luck, not a read, and can't
  grade a shift **clean**.
- **Content** — 5 shifts, **21 hand-authored + 3 generated cases across 10 archetypes**
  (encoded PowerShell, auth brute-force, DNS C2, phishing, impossible-travel, MFA-fatigue,
  EDR malware, data exfil, account lockout, insider threat), each shipping a malicious *and* an
  authorized (Benign-TP) or false-positive variant ("same detection, opposite verdict"). The insider desk adds
  the twist that the *same* action is malicious or benign by **intent/authorization/role**, and
  its true positive **escalates — hands up to insider-risk/HR/legal — rather than isolating**.
  Grounded in adversarially-verified research: [r1](docs/research/soc-tier1-research.md) ·
  [r2](docs/research/soc-tier1-cases-round2.md) · [r3](docs/research/soc-tier1-cases-round3.md) ·
  [r4](docs/research/soc-tier1-cases-round4.md).
- **The Red↔Blue handoff** — a run you pulled off in the red seat is turned into a blue
  case: your tradecraft becomes the analyst's evidence, and whether an engagement
  **authorized** it decides Benign-TP vs True-Positive. *Authorization, not authorship.*
  (Shift 3.)
- **The ladder** — the shift debrief frames the T1 → T2 → T3 path and the real-world
  entry credential (BTL1 → NICE "Cyber Defense Analyst").

## The red seat — the operator

One target — a person, place, or org — cracked through several recon surfaces, under a
rising **Exposure Board**:

- **Exposure Board** — Uplink's trace tracker, instantiated per detection vector:
  **NETWORK** (tracing the packet back), **RF** (someone in the building noticing),
  **FOOTPRINT** (you tipped them off by looking), **ATTRIBUTION** (they're profiling
  *you*, across sessions). A heartbeat beats at BPM by the worst channel — silence at
  CALM is the reward. The skill is triage, not zeroing one bar.
- **Recon surfaces** — `scan`/`connect` network ops; `osint` (passive vs active, the
  footprint tradeoff) building an **evidence board**; `collect rf` to characterize
  emitters; `acquire` (probabilistic access with harvested creds).
- **Evidence-assembly missions** — `identify`/`characterize` objectives are completed by
  assembling the right cards (a deterministic predicate), never by typing free text.
- **Three endings** — **clean** (ghost; streak bonus), **hot** (tripped; full pay,
  attribution ticks up), **burned** (lockdown; you survive, but it costs you). The
  risk-dial (`submit --push`) trades exposure for a payout — the greed beat.
- **Gear** — completing jobs buys gear that flattens an exposure channel: a fear gets quieter.

### Commands (red seat)

```
help · status · inbox · read <id> · accept <id> · missions · submit <id> [--push]
scan <host> [--stealth|--aggr] · probe <host> <port> · fingerprint <host>
osint <subject> [--active] · collect rf <host|emitter> · deploy sensor <host>
acquire <host> [--spray] · evidence
route add/rm/show/clear <proxy> · proxy list/info · connect/disconnect
ls · cat · cp <src> @local · rm · edit <file> key=value · wipe logs
market · buy <id>
```

The blue seat is point-and-click (pull a source, make the call), not command-driven.

## Architecture

- **Pure, deterministic engine.** All red-seat command logic is a pure reducer
  (`app/lib/game/reducer.ts`); `runCommand` is a thin dispatcher. Non-determinism
  (time/RNG/ids) is injected via `CommandContext`. This is what makes the game testable
  and (later) server-authoritative. Run `npm test`.
- **Blue seat (SOC), self-contained** (`app/lib/soc/`) — a pure engine (`engine.ts`:
  deterministic grading, breach/noise meters, investigation scoring), static content
  (`cases.ts` + research-grounded archetypes), and the **Red↔Blue handoff**
  (`handoff.ts`: generates blue cases from red runs). Console UI at `/soc`
  (`app/components/soc/`). It **reuses** the red engine's `trace.ts` thresholds and the
  evidence-assembly + deterministic-grading pattern, and **doesn't touch** the red game's
  state.
- **Seeded world** (`worldgen.ts`) — mulberry32 seed → reproducible hosts, people, and RF
  emitters; same seed → same inbox ("seeded contracts").
- **Exposure engine** (`exposure.ts`) — four channels, dwell clock, decay, outcome.
- **Baked content pack** (`contentPack.ts`) — 30 missions / 30 codex cards / 30 handler
  lines, generated once and served offline at **zero per-play LLM cost**. Live LLM
  generation is a paid delighter, gated behind a server key (inert until set — see
  `app/lib/llm/`), so the free tier is genuinely free to run.
- **Recommended hosting:** Cloudflare Workers via OpenNext + Supabase (auth/DB) + Claude
  tiers (Haiku/Sonnet 4.6/Opus 4.8) behind a Worker. iOS later via Capacitor.

## Status

- ✅ **Red seat:** Phase 0 pure reducer + determinism harness; Exposure Board; seeded
  world + entity graph; OSINT/RF/access surfaces; evidence missions; gear; three
  endings/streak/RoE; Gateway UI (board, heartbeat, Mercer, codex); baked content pack.
- ✅ **Blue seat (SOC) prototype** (`/soc`): TP/FP/Benign-TP triage; 8 archetypes across
  3 shifts (15 hand-authored + 3 generated); breach/noise meters + heartbeat;
  investigation-quality scoring; first-shift coach; **Red↔Blue handoff**. Deterministic,
  research-grounded, and unit-tested.
- ⚠️ **Not yet wired (needs your accounts):** server-authoritative economy (the cheat
  hole — see **[docs/SECURITY.md](docs/SECURITY.md)** and `supabase-schema-hardened.sql`),
  live LLM, Cloudflare deploy, iOS/Capacitor. Do not ship a competitive leaderboard until
  the economy is server-authoritative.

## Develop

```bash
npm install
npm run dev      # red seat: http://localhost:3000 · blue seat: http://localhost:3000/soc
npm test         # vitest — engine determinism, purity, SOC grading + case integrity
npm run build
```

## Credits

Inspired by **Uplink: Hacker Elite** (2001) by Introversion Software.

## License

MIT
