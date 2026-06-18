# Link26 → GHOST26

> *An arcade simulator of the modern signals operator. Uplink's heart, reborn for 2026.*

You never leave the chair, but you reach across the whole physical-digital world —
footprint a person, task a sensor, crack a network — to answer one human question,
and get out before anyone realizes you were there.

This started as a browser homage to Introversion's **Uplink** and is being
re-architected into a viable, cybersec-credible game. The full vision, decisions,
and roadmap live in **[docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)**. (Working title;
final name — GHOST26 vs NULLROUTE vs Link26 — is undecided.)

## It's an arcade simulator — not a how-to

| WE DEPICT | WE NEVER DEPICT |
|---|---|
| Real workflow shapes & phase names (recon → access → action) | Working commands, exploits, or payloads |
| What tools/disciplines are *for*, abstractly | Anything that transfers to a real system |
| Risk/reward tradeoffs as game stats | Real targets, data, or credentials |
| The ethics & rules of engagement | Person identification, tracking, or surveillance |

Credibility comes from authentic vocabulary, accurate mental models, and respect
for the craft — never from transferable attack instructions.

## The loop

One target — a person, place, or org — cracked through several recon surfaces,
under a rising **Exposure Board**:

- **Exposure Board** — Uplink's trace tracker, instantiated per detection vector:
  **NETWORK** (tracing the packet back), **RF** (someone in the building noticing),
  **FOOTPRINT** (you tipped them off by looking), **ATTRIBUTION** (they're profiling
  *you*, across sessions). A heartbeat beats at BPM by the worst channel — silence
  at CALM is the reward. The skill is triage, not zeroing one bar.
- **Recon surfaces** — `scan`/`connect` network ops; `osint` (passive vs active,
  the footprint tradeoff) building an **evidence board**; `collect rf` to
  characterize emitters; `acquire` (probabilistic access with harvested creds).
- **Evidence-assembly missions** — `identify`/`characterize` objectives are
  completed by assembling the right cards (a deterministic predicate), never by
  typing free text.
- **Three endings** — **clean** (ghost; streak bonus), **hot** (tripped; full pay,
  attribution ticks up), **burned** (lockdown; you survive, but it costs you).
  The risk-dial (`submit --push`) trades exposure for a payout — the greed beat.
- **Gear** — completing jobs buys gear that flattens an exposure channel: a fear
  gets quieter.

## Commands

```
help · status · inbox · read <id> · accept <id> · missions · submit <id> [--push]
scan <host> [--stealth|--aggr] · probe <host> <port> · fingerprint <host>
osint <subject> [--active] · collect rf <host|emitter> · deploy sensor <host>
acquire <host> [--spray] · evidence
route add/rm/show/clear <proxy> · proxy list/info · connect/disconnect
ls · cat · cp <src> @local · rm · edit <file> key=value · wipe logs
market · buy <id>
```

## Architecture

- **Pure, deterministic engine.** All command logic is a pure reducer
  (`app/lib/game/reducer.ts`); `runCommand` is a thin dispatcher. Non-determinism
  (time/RNG/ids) is injected via `CommandContext`. This is what makes the game
  testable and (later) server-authoritative. Run `npm test`.
- **Seeded world** (`worldgen.ts`) — mulberry32 seed → reproducible hosts, people,
  and RF emitters; same seed → same inbox ("seeded contracts").
- **Exposure engine** (`exposure.ts`) — four channels, dwell clock, decay, outcome.
- **Baked content pack** (`contentPack.ts`) — 30 missions / 30 codex cards / 30
  handler lines, generated once and served offline at **zero per-play LLM cost**.
  Live LLM generation is a paid delighter, gated behind a server key (inert until
  set — see `app/lib/llm/`), so the free tier is genuinely free to run.
- **Recommended hosting:** Cloudflare Workers via OpenNext + Supabase (auth/DB) +
  Claude tiers (Haiku/Sonnet 4.6/Opus 4.8) behind a Worker. iOS later via Capacitor.

## Status

- ✅ Phase 0: pure reducer + determinism harness; ✅ Exposure Board; ✅ seeded
  world + entity graph; ✅ OSINT/RF/access surfaces; ✅ evidence missions; ✅ gear;
  ✅ three endings/streak/RoE; ✅ Gateway UI (board, heartbeat, Mercer, codex);
  ✅ baked content pack.
- ⚠️ **Not yet wired (needs your accounts):** server-authoritative economy (the
  cheat hole — see **[docs/SECURITY.md](docs/SECURITY.md)** and
  `supabase-schema-hardened.sql`), live LLM, Cloudflare deploy, iOS/Capacitor.
  Do not ship a competitive leaderboard until the economy is server-authoritative.

## Develop

```bash
npm install
npm run dev      # http://localhost:3000
npm test         # vitest — engine determinism, purity, behavior parity
npm run build
```

## Credits

Inspired by **Uplink: Hacker Elite** (2001) by Introversion Software.

## License

MIT
