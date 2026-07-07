import { describe, expect, it } from "vitest";
import {
  INITIAL_CAREER,
  KIT,
  awardForShift,
  awardRedRun,
  buyKit,
  isUnlocked,
  nextRank,
  owns,
  rankFor,
} from "@/app/lib/career/state";
import { SHIFTS } from "@/app/lib/soc/cases";
import type { ShiftScore } from "@/app/lib/soc/engine";

const score = (grade: ShiftScore["grade"], verdictCorrect: number): ShiftScore => ({
  total: 7,
  verdictCorrect,
  dispositionCorrect: verdictCorrect,
  missedDetections: 0,
  falseEscalations: 0,
  accuracy: verdictCorrect / 7,
  blindCalls: 0,
  thoroughCalls: 7,
  investigationRate: 1,
  grade,
  breachRisk: 0,
  noise: 0,
});

describe("career — earning (cash by volume, standing by quality)", () => {
  it("a clean shift pays cash per call + a bonus, and moves standing", () => {
    const r = awardForShift(INITIAL_CAREER, score("clean", 7));
    expect(r.cashGain).toBe(7 * 50 + 150);
    expect(r.standingGain).toBe(40);
    expect(r.state.cash).toBe(500);
    expect(r.state.standing).toBe(40);
    expect(r.state.shiftsCleaned).toBe(1);
  });

  it("a breached shift barely moves standing (quality-gated)", () => {
    const r = awardForShift(INITIAL_CAREER, score("breached", 3));
    expect(r.standingGain).toBe(5);
    expect(r.state.shiftsCleaned).toBe(0);
  });

  it("reports a rank-up when standing crosses a threshold", () => {
    const r = awardForShift(INITIAL_CAREER, score("clean", 7)); // 0 → 40 = Tier-1
    expect(r.rankUp?.id).toBe("t1");
    // no rank-up when it doesn't cross
    expect(awardForShift(INITIAL_CAREER, score("rough", 4)).rankUp).toBeNull();
  });
});

describe("career — rank & unlocks", () => {
  it("rankFor / nextRank", () => {
    expect(rankFor(0).id).toBe("trainee");
    expect(rankFor(40).id).toBe("t1");
    expect(rankFor(10_000).id).toBe("t2");
    expect(nextRank(0)?.id).toBe("t1");
    expect(nextRank(10_000)).toBeNull();
  });

  it("isUnlocked gates by standing", () => {
    const c = { ...INITIAL_CAREER, standing: 90 };
    expect(isUnlocked(c, { unlockStanding: 0 })).toBe(true);
    expect(isUnlocked(c, { unlockStanding: 90 })).toBe(true);
    expect(isUnlocked(c, { unlockStanding: 150 })).toBe(false);
  });

  it("requiresRedRun blocks until a red run is done", () => {
    const c = { ...INITIAL_CAREER, standing: 300 };
    expect(isUnlocked(c, { unlockStanding: 150, requiresRedRun: true })).toBe(false);
    expect(isUnlocked({ ...c, redRunsDone: 1 }, { unlockStanding: 150, requiresRedRun: true })).toBe(true);
  });
});

describe("career — cross-seat (red runs credit the shared wallet)", () => {
  it("awardRedRun adds a personal cut and records a run", () => {
    const r = awardRedRun(INITIAL_CAREER);
    expect(r.redRunsDone).toBe(1);
    expect(r.cash).toBe(150);
    expect(awardRedRun(r).redRunsDone).toBe(2);
  });

  it("the handoff desk needs a red run even at high standing (cross-seat gate)", () => {
    const handoff = SHIFTS.find((s) => s.id === "handoff-shift");
    expect(handoff?.requiresRedRun).toBe(true);
    expect(isUnlocked({ ...INITIAL_CAREER, standing: 999 }, handoff!)).toBe(false);
    expect(isUnlocked({ ...INITIAL_CAREER, standing: 999, redRunsDone: 1 }, handoff!)).toBe(true);
  });
});

describe("career — spending", () => {
  it("buyKit deducts cash and grants gear when affordable; no-op otherwise", () => {
    const item = KIT[0];
    const rich = { ...INITIAL_CAREER, cash: item.cost + 10 };
    const bought = buyKit(rich, item);
    expect(owns(bought, item.id)).toBe(true);
    expect(bought.cash).toBe(10);
    expect(buyKit(bought, item)).toBe(bought); // can't buy twice
    expect(buyKit(INITIAL_CAREER, item)).toBe(INITIAL_CAREER); // can't afford
  });
});
