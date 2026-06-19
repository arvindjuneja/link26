-- GHOST26 — HARDENED schema (closes the cheat hole).
--
-- Problem with supabase-schema.sql: the `saves` table stores the entire game
-- state (incl. cash/reputation) as a client-writable jsonb blob under an
-- `update` policy. A devtools edit of cash therefore persists. For a game
-- pitched to the cybersec community, that is existential — it gets popped on
-- stream in 90 seconds. (See docs/GAME_DESIGN.md §9 + docs/SECURITY.md.)
--
-- Fix: SPLIT state.
--   * Cosmetic, client-authoritative (terminal scrollback, UI prefs): stays in
--     `saves`, client-writable, offline-capable. Never trusted for economy.
--   * Economy, server-authoritative (cash/reputation/streak/gear/mission state):
--     lives in `player_progress`, which clients can READ but NOT write. Only the
--     Cloudflare Worker (service_role key) writes it, after validating the
--     action delta through the SHARED PURE REDUCER (the Phase 0 engine).
--
-- Run in the Supabase SQL editor. Requires the existing `saves` table.

create extension if not exists "uuid-ossp";

-- ----------------------------------------------------------------------------
-- Server-authoritative economy. Clients: SELECT only. Writer: service_role.
-- ----------------------------------------------------------------------------
create table if not exists player_progress (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  cash        integer not null default 4200  check (cash >= 0 and cash <= 100000000),
  reputation  integer not null default 36     check (reputation >= 0),
  streak      integer not null default 0      check (streak >= 0),
  gear        jsonb   not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

alter table player_progress enable row level security;

-- Clients may read their own balance...
create policy "read own progress"
  on player_progress for select
  using (auth.uid() = user_id);

-- ...but there are deliberately NO insert/update/delete policies for the
-- anon/authenticated roles. RLS denies by default, so only the service_role
-- key (held by the Worker, never shipped to the client) can write. This is the
-- gate: the client physically cannot mutate its own balance.

-- ----------------------------------------------------------------------------
-- Grandfather migration with a sanity-clamp so tampered legacy blobs can't seed
-- inflated balances. Run once after creating player_progress.
-- ----------------------------------------------------------------------------
insert into player_progress (user_id, cash, reputation, streak, gear)
select
  s.user_id,
  least(greatest(coalesce((s.state->>'cash')::int, 4200), 0), 250000) as cash,
  least(greatest(coalesce((s.state->>'reputation')::int, 36), 0), 5000) as reputation,
  least(greatest(coalesce((s.state->>'streak')::int, 0), 0), 999) as streak,
  coalesce(s.state->'gear', '{}'::jsonb) as gear
from saves s
on conflict (user_id) do nothing;

-- ----------------------------------------------------------------------------
-- Shadow-mode rollout (de-risks the prediction/reconciliation bug class):
-- before enforcing, log the Worker's authoritative result alongside the
-- client's optimistic one and watch divergence for a week, THEN flip enforcement.
-- ----------------------------------------------------------------------------
create table if not exists progress_audit (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  action      text not null,
  client_cash integer,
  server_cash integer,
  diverged    boolean not null default false,
  created_at  timestamptz not null default now()
);
alter table progress_audit enable row level security;
-- service_role only (no client policies).
