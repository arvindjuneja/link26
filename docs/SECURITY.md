# Security posture & the cheat hole

This game is pitched to a cybersec audience. The anti-cheat boundary is therefore
a launch gate, not a nicety. This doc records the current status and the path to
closing it.

## The cheat hole (OPEN — must close before any public/competitive build)

`supabase-schema.sql` stores the **entire** game state — including `cash` and
`reputation` — as a single jsonb blob in `saves`, under an `update` RLS policy
keyed only on `auth.uid() = user_id`. The client can therefore write any balance
it likes (edit in devtools, save, done). Leaderboards built on this are
meaningless.

## The fix (prepared, needs your infra)

State is **split** (see `supabase-schema-hardened.sql` and design doc §9):

| Class | Where | Who writes |
|---|---|---|
| Cosmetic (scrollback, UI prefs) | `saves` jsonb, IndexedDB | client (offline-capable) |
| Economy (`cash`/`reputation`/`streak`/`gear`/mission completion) | `player_progress` | **Worker only** (service_role) |

`player_progress` has a `select` policy for the owner and **no** write policy for
the anon/authenticated roles — RLS denies by default, so only the Cloudflare
Worker (holding the service_role key) can write it, after validating the action
through the **shared pure reducer** (`app/lib/game/reducer.ts`). The Phase 0
refactor that made the reducer pure and deterministic is what makes this
possible: the same `reduceCommand` runs in the browser (optimistic) and in the
Worker (authoritative).

## To enable (requires your accounts)

1. Provision Supabase; run `supabase-schema.sql` then `supabase-schema-hardened.sql`.
2. Deploy on Cloudflare Workers via OpenNext; set `ANTHROPIC_API_KEY` and the
   Supabase `service_role` key as Worker secrets (never client-exposed).
3. Add a `POST /api/action` Worker route that re-runs `reduceCommand` server-side
   and writes `player_progress`; ship it in **shadow mode** first (log
   client-vs-server divergence in `progress_audit` for ~a week), then enforce.
4. The LLM proxy (`app/api/llm/[usecase]/route.ts`) is already key-gated and
   inert until `ANTHROPIC_API_KEY` is set; add JWT validation + KV token budgets
   before enabling live generation.

Until step 3 enforces, **do not** ship a public leaderboard or competitive mode.
The single-player game is fully playable in the meantime.
