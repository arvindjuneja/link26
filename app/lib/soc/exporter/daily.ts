// The Daily board, PRECOMPUTED at export — 730 days — so no PRNG is ported to Swift (D6).
//
// `fnv1a32` + `xorshift32` + rejection sampling depend on JS `Math.imul` and `>>> 0`
// semantics; porting them bit-for-bit is the single highest-risk thing in the plan and
// buys nothing, because the board is a pure function of the date. Past the horizon the
// app wraps `daysSince(horizonStart) mod days.count` — deterministic and documented.
//
// The algorithm is `docs/ios/DESIGN.md` §4.2, unchanged:
//   1. seed  — fnv1a32(dateISO) → xorshift32. Same date ⇒ same board for everyone.
//   2. pool  — the 21 hand-authored cases (the 3 handoff cases are campaign-only:
//              their framing depends on Shift 4's briefing).
//   3. recency — the previous 3 days' ids are excluded; if that leaves fewer than 8
//              candidates, drop the OLDEST day and retry. Derived from the calendar's
//              own previous days, so the client keeps no ledger (D6).
//   4. draw 5 by deterministic rejection sampling (≤200 attempts) subject to
//              (a) all three verdicts present, (b) ≤2 per archetype,
//              (c) FP + Benign-TP ≥ TP, (d) the board never OPENS on a TP.
//   5. fallback ladder — drop (d), then (c), then (b). (a) is never dropped.
//
// One documented extension to §4.2, needed to make the function TOTAL: if the ladder
// exhausts, the recency window narrows a day at a time — but never below ONE day, so
// "no case appears on two consecutive days" holds unconditionally. If even that
// exhausts, a deterministic constructive board is returned. The function never throws.

import { SOC_CASES } from "@/app/lib/soc/cases";
import type { SocCase } from "@/app/lib/soc/types";
import {
  CONTENT_SCHEMA_VERSION,
  type ExportedDaily,
  type ExportedDailyDay,
  type ExportedDailyTemplate,
} from "@/app/lib/soc/exporter/schema";

export const HORIZON_START = "2026-09-05";
export const HORIZON_DAYS = 730;
export const BOARD_SIZE = 5;
export const RECENCY_DAYS = 3;
export const MIN_CANDIDATES = 8;
export const MAX_ATTEMPTS = 200;

/**
 * The daily shift's ShiftDef, minus the board (S9). R3 carries `requiresRedRun`
 * here too, so `ContentPack.dailyShift(on:)` is a pure field copy rather than a
 * hardcoded `false` sitting beside the copied fields — this build is blue-only on
 * every shift kind (B1), and that fact belongs in the data with the rest of them.
 */
export const DAILY_TEMPLATE: ExportedDailyTemplate = {
  idPrefix: "daily-",
  label: "Daily shift · {date}",
  note: "A fresh board every day — five alerts off the live queue.",
  unlockStanding: 40,
  requiresRedRun: false,
  kind: "daily",
};

// ── PRNG ─────────────────────────────────────────────────────────────────────

export function fnv1a32(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

export function xorshift32(seed: number): () => number {
  let x = seed >>> 0;
  if (x === 0) x = 0x9e3779b9;
  return () => {
    x ^= x << 13;
    x >>>= 0;
    x ^= x >>> 17;
    x ^= x << 5;
    x >>>= 0;
    return x >>> 0;
  };
}

// ── dates ────────────────────────────────────────────────────────────────────

const DAY_MS = 86_400_000;

/** UTC-only date arithmetic — no local timezone, so the export is machine-independent. */
export function addDays(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  const t = Date.UTC(y, m - 1, d) + n * DAY_MS;
  const dt = new Date(t);
  const yy = dt.getUTCFullYear().toString().padStart(4, "0");
  const mm = (dt.getUTCMonth() + 1).toString().padStart(2, "0");
  const dd = dt.getUTCDate().toString().padStart(2, "0");
  return `${yy}-${mm}-${dd}`;
}

// ── the pool and its constraints ─────────────────────────────────────────────

/** §4.2 step 2 — the 21 hand-authored cases, in a stable id order. */
export function dailyPool(): SocCase[] {
  return SOC_CASES.filter((c) => !c.handoff).slice().sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

interface Rules {
  archetypeCap: boolean; // (b)
  notTpHeavy: boolean; // (c)
  calmOpener: boolean; // (d)
}

const RULE_LADDER: Rules[] = [
  { archetypeCap: true, notTpHeavy: true, calmOpener: true },
  { archetypeCap: true, notTpHeavy: true, calmOpener: false },
  { archetypeCap: true, notTpHeavy: false, calmOpener: false },
  { archetypeCap: false, notTpHeavy: false, calmOpener: false },
];

export function satisfies(board: SocCase[], rules: Rules): boolean {
  // (a) all three verdicts present — NEVER dropped.
  const verdicts = new Set(board.map((c) => c.truth));
  if (verdicts.size < 3) return false;

  if (rules.archetypeCap) {
    const counts = new Map<string, number>();
    for (const c of board) counts.set(c.archetype, (counts.get(c.archetype) ?? 0) + 1);
    for (const n of counts.values()) if (n > 2) return false;
  }

  if (rules.notTpHeavy) {
    const tp = board.filter((c) => c.truth === "true-positive").length;
    if (board.length - tp < tp) return false;
  }

  if (rules.calmOpener && board[0].truth === "true-positive") return false;

  return true;
}

function drawFive(next: () => number, candidates: SocCase[]): SocCase[] {
  const pool = candidates.slice();
  const out: SocCase[] = [];
  for (let k = 0; k < BOARD_SIZE && pool.length > 0; k++) {
    out.push(pool.splice(next() % pool.length, 1)[0]);
  }
  return out;
}

function candidatesFor(pool: SocCase[], history: string[][], window: number): SocCase[] {
  const excluded = new Set<string>();
  for (let i = 0; i < window && i < history.length; i++) for (const id of history[i]) excluded.add(id);
  return pool.filter((c) => !excluded.has(c.id));
}

/** The total fallback: a deterministic board that still satisfies rule (a) when it can. */
function constructiveBoard(candidates: SocCase[]): SocCase[] {
  const pick = (t: SocCase["truth"]) => candidates.find((c) => c.truth === t);
  const seed = [pick("false-positive"), pick("benign-true-positive"), pick("true-positive")].filter(
    (c): c is SocCase => c !== undefined
  );
  const out = [...seed];
  for (const c of candidates) {
    if (out.length >= BOARD_SIZE) break;
    if (!out.includes(c)) out.push(c);
  }
  // (d) — open on something that is not a TP, if one is in hand.
  const calm = out.findIndex((c) => c.truth !== "true-positive");
  if (calm > 0) [out[0], out[calm]] = [out[calm], out[0]];
  return out.slice(0, BOARD_SIZE);
}

/**
 * One day's board. `history[0]` is yesterday, `history[1]` the day before, etc.
 * Pure and total — it never throws for any date.
 */
export function boardFor(dateISO: string, pool: SocCase[], history: string[][]): SocCase[] {
  const next = xorshift32(fnv1a32(dateISO));

  // §4.2 step 3 — the recency ladder, on candidate COUNT.
  let window = Math.min(RECENCY_DAYS, history.length);
  let candidates = candidatesFor(pool, history, window);
  while (window > 1 && candidates.length < MIN_CANDIDATES) {
    window -= 1;
    candidates = candidatesFor(pool, history, window);
  }

  for (;;) {
    if (candidates.length >= BOARD_SIZE) {
      // §4.2 steps 4-5 — rejection sampling, then the fallback ladder.
      for (const rules of RULE_LADDER) {
        for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
          const draw = drawFive(next, candidates);
          if (draw.length === BOARD_SIZE && satisfies(draw, rules)) return draw;
        }
      }
    }
    // Extension: narrow the recency window, but NEVER below one day.
    if (window <= 1) break;
    window -= 1;
    candidates = candidatesFor(pool, history, window);
  }

  return constructiveBoard(candidates);
}

/** The whole precomputed calendar. */
export function dailyCalendar(horizonStart = HORIZON_START, days = HORIZON_DAYS): ExportedDaily {
  const pool = dailyPool();
  const history: string[][] = []; // most recent first
  const out: ExportedDailyDay[] = [];

  for (let i = 0; i < days; i++) {
    const date = addDays(horizonStart, i);
    const board = boardFor(date, pool, history);
    const caseIds = board.map((c) => c.id);
    out.push({ date, caseIds });
    history.unshift(caseIds);
    if (history.length > RECENCY_DAYS) history.pop();
  }

  return {
    schemaVersion: CONTENT_SCHEMA_VERSION,
    contentHash: "",
    horizonStart,
    shiftTemplate: DAILY_TEMPLATE,
    days: out,
  };
}
