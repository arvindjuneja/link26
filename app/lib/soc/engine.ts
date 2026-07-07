// Pure SOC engine — no I/O, no side effects, unit-testable (mirrors missionLogic.ts
// + exposure.ts on the red side). The console component drives effects; this file
// only computes next-state from a call.

import { clampLevel, getTraceStatus } from "@/app/lib/game/trace";
import type { TraceStatus } from "@/types/game";
import {
  type CaseResult,
  type Disposition,
  type ShiftGrade,
  type ShiftState,
  type SocCase,
  verdictOf,
} from "@/app/lib/soc/types";

// ── Grading one call ─────────────────────────────────────────────────────────

export interface CallGrade {
  verdictCorrect: boolean;
  dispositionCorrect: boolean; // exact OR acceptable
  exact: boolean; // exactly the ideal disposition
  breachDelta: number; // added to breachRisk
  noiseDelta: number; // added to noise
  /** Plain-language outcome headline for the debrief. */
  outcome: string;
}

const isEscalate = (d: Disposition) =>
  d === "escalate-tier2" || d === "escalate-ir-isolate";

/**
 * Grade a disposition against a case's ground truth, and compute the consequence
 * to the two pressure meters. Pure.
 *
 * Consequence model (deliberately asymmetric — a missed live threat is the
 * cardinal sin of a SOC; crying wolf is the chronic one):
 *  - Miss a TP (close it)            → breachRisk spikes hard (it's dwelling).
 *  - Under-contain a TP (T2 vs IR)   → verdict right, small breach (partial dwell).
 *  - Over-contain a TP (isolate when it should be handed up, e.g. insider → HR/legal)
 *                                    → verdict right, NOISE (tipped off / burned the case).
 *  - Escalate an FP                  → noise (wasted T2 cycles).
 *  - Escalate authorized (Benign-TP) → noise; ISOLATING it also hits ops (worse).
 */
export function gradeCall(c: SocCase, chosen: Disposition): CallGrade {
  const chosenVerdict = verdictOf(chosen);
  const verdictCorrect = chosenVerdict === c.truth;
  const exact = chosen === c.correctDisposition;
  const dispositionCorrect = exact || (c.acceptableDispositions?.includes(chosen) ?? false);

  let breachDelta = 0;
  let noiseDelta = 0;
  let outcome: string;

  if (c.truth === "true-positive") {
    if (!isEscalate(chosen)) {
      // Closed a real threat. The worst call a Tier-1 can make.
      breachDelta = 30;
      outcome = "MISSED DETECTION — a live threat was closed and is now dwelling undetected.";
    } else if (dispositionCorrect) {
      outcome = "Good call — escalated a genuine threat with the right urgency.";
    } else if (chosen === "escalate-ir-isolate") {
      // Over-contained: isolated when this should have been handed up (e.g. an insider
      // case belongs with HR/legal, not a lone analyst). Nothing dwells — the exfil is
      // contained — so the harm is operational (you tipped them off and burned the
      // case), which hits NOISE, not breach, mirroring the benign-TP isolation case.
      noiseDelta = 12;
      outcome =
        "Right verdict, but over-reacted — this one should be handed up (HR/legal), not isolated. Isolating tips them off and burns the case.";
    } else {
      // Under-contained: escalated, but didn't contain when the threat needed
      // contain-now, so it had room to move — a partial dwell.
      breachDelta = 10;
      outcome = "Right verdict, but under-contained — the threat had room to move before IR caught up.";
    }
  } else if (c.truth === "false-positive") {
    if (!isEscalate(chosen)) {
      // Closed correctly. Closing as "benign" instead of "FP" is a near-miss on
      // reasoning but not operationally harmful — still counts (verdict differs).
      outcome = verdictCorrect
        ? "Correct — recognized the noise and closed it without burning Tier-2 cycles."
        : "Closed it (good), but as 'authorized' rather than 'false positive' — the detection itself was wrong.";
    } else {
      noiseDelta = chosen === "escalate-ir-isolate" ? 20 : 12;
      outcome = "False escalation — you sent noise up the chain. Do this often and Tier-2 stops trusting your tickets.";
    }
  } else {
    // benign-true-positive: detection was correct, activity authorized.
    if (chosen === "close-benign") {
      outcome = "Correct — found the authorization and closed it as a benign true positive.";
    } else if (chosen === "close-false-positive") {
      // Closed it (no breach), but mislabeled WHY — the detection was actually right.
      noiseDelta = 4;
      outcome = "Closed it (fine), but it wasn't a false positive — the detection was correct; the activity was just sanctioned.";
    } else if (chosen === "escalate-ir-isolate") {
      noiseDelta = 24;
      outcome = "You isolated a sanctioned operation — ops impact, and an angry change-owner. Always check for authorization first.";
    } else {
      noiseDelta = 14;
      outcome = "Escalated authorized activity — Tier-2 will bounce it back. The change ticket was right there.";
    }
  }

  return { verdictCorrect, dispositionCorrect, exact, breachDelta, noiseDelta, outcome };
}

// ── Applying a call to the shift ─────────────────────────────────────────────

export function buildCaseResult(
  c: SocCase,
  chosen: Disposition,
  queriedSourceIds: string[],
  timeSpent: number
): CaseResult {
  const grade = gradeCall(c, chosen);
  const keySet = new Set(c.keySourceIds);
  const keySourcesPulled = queriedSourceIds.filter((id) => keySet.has(id)).length;
  return {
    caseId: c.id,
    chosen,
    verdictCorrect: grade.verdictCorrect,
    dispositionCorrect: grade.dispositionCorrect,
    queriedSourceIds,
    keySourcesPulled,
    timeSpent,
  };
}

/** Fold a graded call into the shift state (advances the case pointer). Pure. */
export function applyCall(
  shift: ShiftState,
  c: SocCase,
  chosen: Disposition,
  queriedSourceIds: string[],
  timeSpent: number
): ShiftState {
  const grade = gradeCall(c, chosen);
  const result = buildCaseResult(c, chosen, queriedSourceIds, timeSpent);
  return {
    ...shift,
    index: shift.index + 1,
    results: { ...shift.results, [c.id]: result },
    breachRisk: clampLevel(shift.breachRisk + grade.breachDelta),
    noise: clampLevel(shift.noise + grade.noiseDelta),
    timeUsed: shift.timeUsed + timeSpent,
  };
}

// ── Meters & grading the whole shift ─────────────────────────────────────────

/** Worst of the two pressure meters — drives the headline heartbeat. */
export function overallShiftStatus(shift: ShiftState): TraceStatus {
  const rank: Record<TraceStatus, number> = { CALM: 0, ALERT: 1, HUNT: 2, LOCKDOWN: 3 };
  const a = getTraceStatus(shift.breachRisk);
  const b = getTraceStatus(shift.noise);
  return rank[a] >= rank[b] ? a : b;
}

export interface ShiftScore {
  total: number; // cases resolved
  verdictCorrect: number;
  dispositionCorrect: number;
  missedDetections: number; // TP closed
  falseEscalations: number; // FP / Benign escalated
  accuracy: number; // verdictCorrect / total, 0..1
  // Investigation quality: pulling the sources that ANSWER the case, not guessing.
  blindCalls: number; // calls made with zero of the case's key sources pulled
  thoroughCalls: number; // calls made with ALL of the case's key sources pulled
  investigationRate: number; // key sources pulled / key sources available, 0..1
  grade: ShiftGrade;
  breachRisk: number;
  noise: number;
}

/** Per-case investigation quality, from the recorded result. */
export function investigationOf(
  result: { keySourcesPulled: number },
  c: SocCase
): "blind" | "partial" | "thorough" {
  const total = c.keySourceIds.length;
  if (total === 0) return "thorough";
  if (result.keySourcesPulled === 0) return "blind";
  if (result.keySourcesPulled >= total) return "thorough";
  return "partial";
}

export function scoreShift(shift: ShiftState, cases: Record<string, SocCase>): ShiftScore {
  const results = Object.values(shift.results);
  const total = results.length;
  let verdictCorrect = 0;
  let dispositionCorrect = 0;
  let missedDetections = 0;
  let falseEscalations = 0;
  let blindCalls = 0;
  let thoroughCalls = 0;
  let keyPulledSum = 0;
  let keyTotalSum = 0;

  for (const r of results) {
    const c = cases[r.caseId];
    if (!c) continue;
    if (r.verdictCorrect) verdictCorrect++;
    if (r.dispositionCorrect) dispositionCorrect++;
    const chosenVerdict = verdictOf(r.chosen);
    if (c.truth === "true-positive" && chosenVerdict !== "true-positive") missedDetections++;
    if (c.truth !== "true-positive" && chosenVerdict === "true-positive") falseEscalations++;
    keyTotalSum += c.keySourceIds.length;
    keyPulledSum += r.keySourcesPulled;
    const quality = investigationOf(r, c);
    if (quality === "blind") blindCalls++;
    else if (quality === "thorough") thoroughCalls++;
  }

  const accuracy = total > 0 ? verdictCorrect / total : 0;
  const investigationRate = keyTotalSum > 0 ? keyPulledSum / keyTotalSum : 1;
  // Grade keys off the breach meter first (a breach on your watch is a rough night
  // regardless of raw accuracy), then accuracy. A clean shift also needs the NOISE
  // meter calm (CALM/ALERT only), AND no BLIND calls — a right verdict reached without
  // pulling the logs that answer the case is luck, not analysis, and can't grade clean.
  const noiseStatus = getTraceStatus(shift.noise);
  let grade: ShiftGrade;
  if (getTraceStatus(shift.breachRisk) === "LOCKDOWN" || missedDetections >= 2) {
    grade = "breached";
  } else if (
    accuracy >= 0.8 &&
    missedDetections === 0 &&
    blindCalls === 0 &&
    noiseStatus !== "HUNT" &&
    noiseStatus !== "LOCKDOWN"
  ) {
    grade = "clean";
  } else {
    grade = "rough";
  }

  return {
    total,
    verdictCorrect,
    dispositionCorrect,
    missedDetections,
    falseEscalations,
    accuracy,
    blindCalls,
    thoroughCalls,
    investigationRate,
    grade,
    breachRisk: shift.breachRisk,
    noise: shift.noise,
  };
}

// ── Shift assembly ───────────────────────────────────────────────────────────

const DEFAULT_TIME_BUDGET = 90; // shift-minutes; soft

/** Build a fresh shift over the given ordered case ids. Pure. */
export function assembleShift(shiftId: string, caseIds: string[], timeBudget = DEFAULT_TIME_BUDGET): ShiftState {
  return {
    shiftId,
    caseIds,
    index: 0,
    results: {},
    breachRisk: 0,
    noise: 0,
    timeUsed: 0,
    timeBudget,
  };
}

export function shiftComplete(shift: ShiftState): boolean {
  return shift.index >= shift.caseIds.length;
}
