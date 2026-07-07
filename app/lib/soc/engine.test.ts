import { describe, expect, it } from "vitest";
import {
  applyCall,
  assembleShift,
  gradeCall,
  investigationOf,
  overallShiftStatus,
  scoreShift,
  shiftComplete,
} from "@/app/lib/soc/engine";
import { SOC_CASES_BY_ID } from "@/app/lib/soc/cases";
import { verdictOf } from "@/app/lib/soc/types";

const c = (id: string) => {
  const x = SOC_CASES_BY_ID[id];
  if (!x) throw new Error(`missing case ${id}`);
  return x;
};

describe("verdictOf — disposition → verdict mapping", () => {
  it("maps the four dispositions to the three verdicts", () => {
    expect(verdictOf("close-false-positive")).toBe("false-positive");
    expect(verdictOf("close-benign")).toBe("benign-true-positive");
    expect(verdictOf("escalate-tier2")).toBe("true-positive");
    expect(verdictOf("escalate-ir-isolate")).toBe("true-positive");
  });
});

describe("gradeCall — the central deterministic predicate", () => {
  it("rewards the ideal call with no consequence", () => {
    const g = gradeCall(c("soc-ps-cradle"), "escalate-ir-isolate");
    expect(g.verdictCorrect).toBe(true);
    expect(g.exact).toBe(true);
    expect(g.breachDelta).toBe(0);
    expect(g.noiseDelta).toBe(0);
  });

  it("punishes a MISSED DETECTION (closing a true positive) with a breach spike", () => {
    const g = gradeCall(c("soc-ps-cradle"), "close-false-positive");
    expect(g.verdictCorrect).toBe(false);
    expect(g.breachDelta).toBeGreaterThanOrEqual(30);
    expect(g.noiseDelta).toBe(0);
  });

  it("gives partial credit for right-verdict, under-contained (T2 when isolate was ideal)", () => {
    const g = gradeCall(c("soc-ps-cradle"), "escalate-tier2");
    expect(g.verdictCorrect).toBe(true);
    expect(g.dispositionCorrect).toBe(true); // listed as acceptable
    expect(g.breachDelta).toBe(0);
  });

  it("penalizes escalating a false positive as NOISE, not breach", () => {
    const g = gradeCall(c("soc-auth-reset"), "escalate-tier2");
    expect(g.verdictCorrect).toBe(false);
    expect(g.noiseDelta).toBeGreaterThan(0);
    expect(g.breachDelta).toBe(0);
  });

  it("isolating authorized (benign) activity is the worst noise outcome", () => {
    const isolate = gradeCall(c("soc-auth-pentest"), "escalate-ir-isolate");
    const escalate = gradeCall(c("soc-auth-pentest"), "escalate-tier2");
    expect(isolate.noiseDelta).toBeGreaterThan(escalate.noiseDelta);
    expect(isolate.breachDelta).toBe(0); // no threat dwelt; the harm is operational
  });

  it("closing a benign-TP as a false positive avoids breach but is mildly noisy (wrong reasoning)", () => {
    const g = gradeCall(c("soc-ps-patch"), "close-false-positive");
    expect(g.verdictCorrect).toBe(false); // FP ≠ Benign-TP
    expect(g.breachDelta).toBe(0); // nothing dwelt
    expect(g.noiseDelta).toBeGreaterThan(0);
    expect(g.noiseDelta).toBeLessThan(10);
  });

  it("the insider TP's correct call is escalate (hand up), graded clean", () => {
    const g = gradeCall(c("soc-insider-departing"), "escalate-tier2");
    expect(g.verdictCorrect).toBe(true);
    expect(g.exact).toBe(true);
    expect(g.breachDelta).toBe(0);
    expect(g.noiseDelta).toBe(0);
  });

  it("OVER-containing an insider TP (isolate when you should hand up) hits NOISE, not breach", () => {
    const g = gradeCall(c("soc-insider-departing"), "escalate-ir-isolate");
    expect(g.verdictCorrect).toBe(true); // still the right verdict
    expect(g.dispositionCorrect).toBe(false);
    expect(g.noiseDelta).toBeGreaterThan(0); // operational blowback (tipped off / burned the case)
    expect(g.breachDelta).toBe(0); // nothing dwells — the exfil is contained
  });
});

describe("applyCall + scoreShift — folding calls into a shift", () => {
  it("a flawless shift grades clean with full accuracy and zero breach", () => {
    let shift = assembleShift("test", [...["soc-ps-cradle", "soc-auth-reset", "soc-ps-patch"]]);
    for (const id of shift.caseIds) {
      const cs = c(id);
      shift = applyCall(shift, cs, cs.correctDisposition, cs.keySourceIds, 20);
    }
    expect(shiftComplete(shift)).toBe(true);
    const score = scoreShift(shift, SOC_CASES_BY_ID);
    expect(score.total).toBe(3);
    expect(score.accuracy).toBe(1);
    expect(score.missedDetections).toBe(0);
    expect(score.breachRisk).toBe(0);
    expect(score.grade).toBe("clean");
  });

  it("two missed detections force a 'breached' shift regardless of the rest", () => {
    let shift = assembleShift("test", ["soc-ps-cradle", "soc-dns-beacon", "soc-auth-reset"]);
    shift = applyCall(shift, c("soc-ps-cradle"), "close-false-positive", [], 10);
    shift = applyCall(shift, c("soc-dns-beacon"), "close-false-positive", [], 10);
    shift = applyCall(shift, c("soc-auth-reset"), "close-false-positive", [], 10);
    const score = scoreShift(shift, SOC_CASES_BY_ID);
    expect(score.missedDetections).toBe(2);
    expect(score.grade).toBe("breached");
    expect(overallShiftStatus(shift)).not.toBe("CALM");
  });

  it("counts false escalations (FP/benign escalated)", () => {
    let shift = assembleShift("test", ["soc-auth-reset", "soc-auth-pentest"]);
    shift = applyCall(shift, c("soc-auth-reset"), "escalate-tier2", [], 10);
    shift = applyCall(shift, c("soc-auth-pentest"), "escalate-ir-isolate", [], 10);
    const score = scoreShift(shift, SOC_CASES_BY_ID);
    expect(score.falseEscalations).toBe(2);
    expect(score.noise).toBeGreaterThan(0);
  });

  it("records which key sources were pulled (investigation quality)", () => {
    let shift = assembleShift("test", ["soc-ps-cradle"]);
    shift = applyCall(shift, c("soc-ps-cradle"), "escalate-ir-isolate", ["edr-process-tree"], 10);
    expect(shift.results["soc-ps-cradle"].keySourcesPulled).toBe(1);
  });
});

describe("investigation quality — blind guessing can't grade clean", () => {
  it("investigationOf classifies blind / partial / thorough", () => {
    const cs = c("soc-ps-cradle"); // 3 key sources
    expect(investigationOf({ keySourcesPulled: 0 }, cs)).toBe("blind");
    expect(investigationOf({ keySourcesPulled: 1 }, cs)).toBe("partial");
    expect(investigationOf({ keySourcesPulled: 3 }, cs)).toBe("thorough");
  });

  it("a perfectly-accurate shift called BLIND grades rough, not clean", () => {
    const ids = ["soc-ps-cradle", "soc-auth-reset", "soc-ps-patch"];
    let shift = assembleShift("test", ids);
    for (const id of ids) {
      const cs = c(id);
      shift = applyCall(shift, cs, cs.correctDisposition, [], 3); // queried [] → blind
    }
    const score = scoreShift(shift, SOC_CASES_BY_ID);
    expect(score.accuracy).toBe(1);
    expect(score.blindCalls).toBe(3);
    expect(score.investigationRate).toBe(0);
    expect(score.grade).toBe("rough"); // right verdicts, but no analysis → not clean
  });

  it("the same shift, investigated thoroughly, grades clean", () => {
    const ids = ["soc-ps-cradle", "soc-auth-reset", "soc-ps-patch"];
    let shift = assembleShift("test", ids);
    for (const id of ids) {
      const cs = c(id);
      shift = applyCall(shift, cs, cs.correctDisposition, cs.keySourceIds, 20);
    }
    const score = scoreShift(shift, SOC_CASES_BY_ID);
    expect(score.blindCalls).toBe(0);
    expect(score.thoroughCalls).toBe(3);
    expect(score.investigationRate).toBe(1);
    expect(score.grade).toBe("clean");
  });
});
