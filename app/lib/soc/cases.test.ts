import { describe, expect, it } from "vitest";
import {
  FIRST_SHIFT_CASE_IDS,
  INSIDER_SHIFT_CASE_IDS,
  LOCKOUT_SHIFT_CASE_IDS,
  SECOND_SHIFT_CASE_IDS,
  SHIFTS,
  SOC_CASES,
  SOC_CASES_BY_ID,
} from "@/app/lib/soc/cases";
import { type SocVerdict, verdictOf } from "@/app/lib/soc/types";

const VERDICTS: SocVerdict[] = ["true-positive", "false-positive", "benign-true-positive"];

// Guards every case against shipping broken/unwinnable or self-contradictory —
// the SOC analog of campaign.test.ts. Content correctness matters more here than
// on the arcade side (this seat is tied to real recruitment), so the invariants
// are strict.
describe("SOC_CASES — content integrity", () => {
  it("every case has a valid, internally-consistent ground truth", () => {
    for (const c of SOC_CASES) {
      expect(VERDICTS, c.id).toContain(c.truth);
      // the ideal disposition must encode the true verdict
      expect(verdictOf(c.correctDisposition), `${c.id} disposition vs truth`).toBe(c.truth);
      // any "acceptable" alternative must still be the RIGHT verdict (only the
      // containment differs — never a different classification)
      for (const d of c.acceptableDispositions ?? []) {
        expect(verdictOf(d), `${c.id} acceptable ${d}`).toBe(c.truth);
        expect(d, `${c.id} acceptable ≠ ideal`).not.toBe(c.correctDisposition);
      }
    }
  });

  it("evidence only references sources the case exposes, and source ids are unique", () => {
    for (const c of SOC_CASES) {
      const sourceIds = c.sources.map((s) => s.id);
      expect(new Set(sourceIds).size, `${c.id} duplicate source`).toBe(sourceIds.length);
      const known = new Set(sourceIds);
      for (const e of c.evidence) {
        expect(known.has(e.sourceId), `${c.id} evidence ${e.id} → unknown source ${e.sourceId}`).toBe(true);
      }
      const evidenceIds = c.evidence.map((e) => e.id);
      expect(new Set(evidenceIds).size, `${c.id} duplicate evidence id`).toBe(evidenceIds.length);
    }
  });

  it("every exposed source yields ≥1 finding — no dead buttons", () => {
    for (const c of SOC_CASES) {
      const withEvidence = new Set(c.evidence.map((e) => e.sourceId));
      for (const s of c.sources) {
        expect(withEvidence.has(s.id), `${c.id} exposes ${s.id} but it yields no evidence`).toBe(true);
      }
    }
  });

  it("key sources exist, are pullable, and each yields decisive-or-supporting evidence", () => {
    for (const c of SOC_CASES) {
      expect(c.keySourceIds.length, `${c.id} has no key sources`).toBeGreaterThan(0);
      const known = new Set(c.sources.map((s) => s.id));
      for (const k of c.keySourceIds) {
        expect(known.has(k), `${c.id} key source ${k} not exposed`).toBe(true);
        const signal = c.evidence.some(
          (e) => e.sourceId === k && (e.weight === "decisive" || e.weight === "supporting")
        );
        expect(signal, `${c.id} key source ${k} yields no signal`).toBe(true);
      }
    }
  });

  it("every case has at least one decisive finding and a teaching debrief", () => {
    for (const c of SOC_CASES) {
      expect(c.evidence.some((e) => e.weight === "decisive"), `${c.id} no decisive evidence`).toBe(true);
      expect(c.why.length, `${c.id} missing why`).toBeGreaterThan(20);
      expect(c.learn.concept.length, `${c.id} missing learn.concept`).toBeGreaterThan(20);
    }
  });

  it("respects the guardrail — no literal runnable exploit syntax in evidence", () => {
    // We depict the analyst's READ (patterns), never a working command/payload.
    const banned = [/IEX\s*\(/i, /Invoke-Expression/i, /DownloadString\s*\(/i, /FromBase64String\s*\(/i, /-e[nc]+\s+[A-Za-z0-9+/=]{16,}/];
    for (const c of SOC_CASES) {
      const text = c.evidence.map((e) => e.detail).join(" \n ") + " " + c.trigger;
      for (const re of banned) {
        expect(re.test(text), `${c.id} leaks runnable syntax: ${re}`).toBe(false);
      }
    }
  });

  it("case ids are globally unique", () => {
    const ids = SOC_CASES.map((c) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
  });
});

describe("FIRST_SHIFT_CASE_IDS — the first shift", () => {
  it("references only real cases, no repeats", () => {
    for (const id of FIRST_SHIFT_CASE_IDS) {
      expect(SOC_CASES_BY_ID[id], `shift references missing case ${id}`).toBeDefined();
    }
    expect(new Set(FIRST_SHIFT_CASE_IDS).size).toBe(FIRST_SHIFT_CASE_IDS.length);
  });

  it("exercises all three verdicts and all three archetypes", () => {
    const cases = FIRST_SHIFT_CASE_IDS.map((id) => SOC_CASES_BY_ID[id]);
    expect(new Set(cases.map((c) => c.truth))).toEqual(new Set(VERDICTS));
    expect(new Set(cases.map((c) => c.archetype)).size).toBe(3);
  });

  it("tilts toward not-a-threat (FP + Benign ≥ TP) — real triage isn't mostly escalations", () => {
    const cases = FIRST_SHIFT_CASE_IDS.map((id) => SOC_CASES_BY_ID[id]);
    const tp = cases.filter((c) => c.truth === "true-positive").length;
    const notThreat = cases.length - tp;
    expect(notThreat).toBeGreaterThanOrEqual(tp);
  });
});

describe("SECOND_SHIFT_CASE_IDS — the round-2 shift", () => {
  it("references only real cases, no repeats", () => {
    for (const id of SECOND_SHIFT_CASE_IDS) {
      expect(SOC_CASES_BY_ID[id], `shift references missing case ${id}`).toBeDefined();
    }
    expect(new Set(SECOND_SHIFT_CASE_IDS).size).toBe(SECOND_SHIFT_CASE_IDS.length);
  });

  it("exercises all three verdicts and every round-2 archetype", () => {
    const cases = SECOND_SHIFT_CASE_IDS.map((id) => SOC_CASES_BY_ID[id]);
    expect(new Set(cases.map((c) => c.truth))).toEqual(new Set(VERDICTS));
    expect(new Set(cases.map((c) => c.archetype))).toEqual(
      new Set(["phishing", "impossible-travel", "mfa-fatigue", "edr-malware", "data-exfil"])
    );
  });

  it("tilts toward not-a-threat (FP + Benign ≥ TP)", () => {
    const cases = SECOND_SHIFT_CASE_IDS.map((id) => SOC_CASES_BY_ID[id]);
    const tp = cases.filter((c) => c.truth === "true-positive").length;
    expect(cases.length - tp).toBeGreaterThanOrEqual(tp);
  });
});

describe("LOCKOUT_SHIFT_CASE_IDS — the round-3 lockout queue", () => {
  it("references only real account-lockout cases, exercises all three verdicts, FP/benign-heavy", () => {
    const cases = LOCKOUT_SHIFT_CASE_IDS.map((id) => SOC_CASES_BY_ID[id]);
    for (let i = 0; i < cases.length; i++) {
      expect(cases[i], `missing ${LOCKOUT_SHIFT_CASE_IDS[i]}`).toBeDefined();
      expect(cases[i].archetype).toBe("account-lockout");
    }
    expect(new Set(cases.map((c) => c.truth))).toEqual(new Set(VERDICTS));
    const tp = cases.filter((c) => c.truth === "true-positive").length;
    expect(cases.length - tp).toBeGreaterThanOrEqual(tp);
  });
});

describe("INSIDER_SHIFT_CASE_IDS — the round-4 insider desk", () => {
  it("references only real insider cases, exercises all three verdicts, FP/benign-heavy", () => {
    const cases = INSIDER_SHIFT_CASE_IDS.map((id) => SOC_CASES_BY_ID[id]);
    for (let i = 0; i < cases.length; i++) {
      expect(cases[i], `missing ${INSIDER_SHIFT_CASE_IDS[i]}`).toBeDefined();
      expect(cases[i].archetype).toBe("insider-threat");
    }
    expect(new Set(cases.map((c) => c.truth))).toEqual(new Set(VERDICTS));
    const tp = cases.filter((c) => c.truth === "true-positive").length;
    expect(cases.length - tp).toBeGreaterThanOrEqual(tp);
  });

  it("the insider TP escalates WITHOUT isolating (hand up to HR/legal, don't confront)", () => {
    const tp = INSIDER_SHIFT_CASE_IDS.map((id) => SOC_CASES_BY_ID[id]).find((c) => c.truth === "true-positive");
    expect(tp?.correctDisposition).toBe("escalate-tier2");
    expect(tp?.acceptableDispositions ?? []).not.toContain("escalate-ir-isolate");
  });
});

describe("SHIFTS — the playable shift registry", () => {
  it("every shift references real cases and has a non-empty queue", () => {
    expect(SHIFTS.length).toBeGreaterThan(0);
    const ids = SHIFTS.map((s) => s.id);
    expect(new Set(ids).size, "duplicate shift id").toBe(ids.length);
    for (const s of SHIFTS) {
      expect(s.caseIds.length, `${s.id} empty`).toBeGreaterThan(0);
      for (const id of s.caseIds) {
        expect(SOC_CASES_BY_ID[id], `${s.id} → missing case ${id}`).toBeDefined();
      }
    }
  });
});
