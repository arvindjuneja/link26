// The career layer — one identity across the seats. This is where "you built
// yourself up" lives: you EARN two things, with deliberately different roles.
//
//   Cash (¢)      — POWER. Earned by COMPLETING work (grind-friendly: do easy jobs
//                   for money). Spent on gear/compute (blue: analyst kit; red:
//                   proxies/rig later). Fungible.
//   Standing (⬢)  — ACCESS / RANK. Earned by doing WELL (a clean shift), never spent.
//                   It gates harder work and moves you up the ladder — the handler
//                   "vouches" for you as it climbs. Quality, not quantity.
//
// Pure + deterministic (no I/O here except the tiny persist helpers). The red seat
// will later award into the SAME state (cash from contracts, `redRunsDone` from runs)
// — this module is written to be shared, and to migrate cleanly to server-authoritative
// Supabase writes for beta (the values a cheat would forge — cash/standing/gear — live
// in one place).

import type { ShiftScore } from "@/app/lib/soc/engine";

export interface CareerState {
  cash: number; // ¢ — power currency
  standing: number; // ⬢ — access/rank currency (earned by quality; never spent)
  shiftsCleaned: number; // count of clean shifts (for flavour/history)
  redRunsDone: number; // red-seat runs completed (the handoff's intended gate; wired later)
  gear: string[]; // owned analyst-kit upgrade ids
}

export const INITIAL_CAREER: CareerState = {
  cash: 0,
  standing: 0,
  shiftsCleaned: 0,
  redRunsDone: 0,
  gear: [],
};

// ── Rank (derived from standing) ─────────────────────────────────────────────
export interface Rank {
  id: string;
  label: string;
  min: number; // standing at/above this = this rank
}
export const RANKS: Rank[] = [
  { id: "trainee", label: "Trainee", min: 0 },
  { id: "t1", label: "Tier-1 Analyst", min: 40 },
  { id: "t1-senior", label: "Tier-1 · Senior", min: 150 },
  { id: "t2", label: "Tier-2 · candidate", min: 210 },
];
export function rankFor(standing: number): Rank {
  let r = RANKS[0];
  for (const rank of RANKS) if (standing >= rank.min) r = rank;
  return r;
}
/** Standing needed for the next rank, or null if maxed. */
export function nextRank(standing: number): Rank | null {
  return RANKS.find((r) => r.min > standing) ?? null;
}

// ── Analyst-kit shop (the cash sink — proves earn→spend→benefit) ─────────────
export interface KitItem {
  id: string;
  label: string;
  cost: number;
  blurb: string;
}
export const KIT: KitItem[] = [
  {
    id: "intel-feed",
    label: "Threat-intel feed subscription",
    cost: 300,
    blurb: "Every case opens with the threat-intel enrichment already pulled — one less source to spend shift-time on.",
  },
];
export function owns(c: CareerState, gearId: string): boolean {
  return c.gear.includes(gearId);
}
export function buyKit(c: CareerState, item: KitItem): CareerState {
  if (owns(c, item.id) || c.cash < item.cost) return c;
  return { ...c, cash: c.cash - item.cost, gear: [...c.gear, item.id] };
}

// ── Earning ──────────────────────────────────────────────────────────────────
export interface ShiftReward {
  state: CareerState;
  cashGain: number;
  standingGain: number;
  rankUp: Rank | null; // the new rank if you ranked up, else null
}
/** Fold a completed shift's score into the career. Pure. */
export function awardForShift(c: CareerState, score: ShiftScore): ShiftReward {
  // Cash = completing work (per correct call) + a clean-shift bonus. Grind-friendly.
  const cashGain = score.verdictCorrect * 50 + (score.grade === "clean" ? 150 : 0);
  // Standing = doing WELL. A clean shift moves the rank; a rough/breached one barely does.
  const standingGain = score.grade === "clean" ? 40 : score.grade === "rough" ? 15 : 5;

  const state: CareerState = {
    ...c,
    cash: c.cash + cashGain,
    standing: c.standing + standingGain,
    shiftsCleaned: c.shiftsCleaned + (score.grade === "clean" ? 1 : 0),
  };
  const rankUp = rankFor(state.standing).id !== rankFor(c.standing).id ? rankFor(state.standing) : null;
  return { state, cashGain, standingGain, rankUp };
}

/** Credit the shared career wallet for a completed RED-seat run: your personal cut
 *  (cross-seat cash — the blue kit shop draws on the same wallet) + one run on record
 *  (which is what opens "the other chair", the handoff desk). Pure. The red seat keeps
 *  its own operational cash for gear; this is the personal bank that spans both seats. */
export const RED_RUN_CUT = 150;
export function awardRedRun(c: CareerState, cut: number = RED_RUN_CUT): CareerState {
  return { ...c, cash: c.cash + cut, redRunsDone: c.redRunsDone + 1 };
}

// ── Unlock gating (a shift's unlockStanding lives on the SHIFTS entry) ────────
export interface Unlockable {
  unlockStanding: number;
  requiresRedRun?: boolean;
}
export function isUnlocked(c: CareerState, shift: Unlockable): boolean {
  if (c.standing < shift.unlockStanding) return false;
  if (shift.requiresRedRun && c.redRunsDone < 1) return false;
  return true;
}

// ── Persistence (local-first; migrates to Supabase for beta) ─────────────────
const KEY = "sentry_career_v1";
export function loadCareer(): CareerState {
  if (typeof window === "undefined") return INITIAL_CAREER;
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return INITIAL_CAREER;
    return { ...INITIAL_CAREER, ...(JSON.parse(raw) as Partial<CareerState>) };
  } catch {
    return INITIAL_CAREER;
  }
}
export function saveCareer(c: CareerState): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(KEY, JSON.stringify(c));
  } catch {
    /* ignore */
  }
}
