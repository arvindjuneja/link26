import { describe, expect, it } from "vitest";
import { RED_RUNS, caseFromRedRun, type RedRun } from "@/app/lib/soc/handoff";
import { HANDOFF_CASES, SOC_CASES_BY_ID } from "@/app/lib/soc/cases";
import { verdictOf, type DataSource } from "@/app/lib/soc/types";

// Minimal stand-in for the shared source catalogue (matching real ids), so the
// mapping can be unit-tested without importing the private cases.ts catalogue.
const SRC: Record<string, DataSource> = {
  authLogs: { id: "auth-logs", label: "Auth logs", question: "?", cost: 8 },
  signinLogs: { id: "signin-logs", label: "Sign-in logs", question: "?", cost: 8 },
  dlpHits: { id: "dlp-hits", label: "DLP hits", question: "?", cost: 6 },
  alertEvidence: { id: "alert-evidence", label: "AlertEvidence", question: "?", cost: 8 },
  changeTickets: { id: "change-tickets", label: "Change tickets", question: "?", cost: 6 },
};

const authorizedRun: RedRun = {
  id: "t-auth",
  operator: "ghost_x",
  targetLabel: "Test Target",
  objective: "exfil",
  tradecraft: ["osint", "cred-spray", "proxy-chain", "session", "exfil-copy"],
  authorized: true,
  roeRef: "RoE-9",
  quiet: true,
};
const unsanctionedRun: RedRun = { ...authorizedRun, id: "t-un", authorized: false, roeRef: undefined, quiet: false };

describe("caseFromRedRun — the Red↔Blue mapping", () => {
  it("is deterministic (same run → identical case)", () => {
    expect(caseFromRedRun(authorizedRun, SRC)).toEqual(caseFromRedRun(authorizedRun, SRC));
  });

  it("authorized run → Benign True Positive, close-benign", () => {
    const c = caseFromRedRun(authorizedRun, SRC);
    expect(c.truth).toBe("benign-true-positive");
    expect(c.correctDisposition).toBe("close-benign");
    expect(verdictOf(c.correctDisposition)).toBe(c.truth);
    expect(c.handoff).toEqual({ fromRun: "t-auth", operator: "ghost_x" });
  });

  it("SAME tradecraft, no authorization → True Positive, escalate-IR", () => {
    const c = caseFromRedRun(unsanctionedRun, SRC);
    expect(c.truth).toBe("true-positive");
    expect(c.correctDisposition).toBe("escalate-ir-isolate");
    expect(c.acceptableDispositions).toContain("escalate-tier2");
  });

  it("the authorization finding is always the decisive pivot", () => {
    const yes = caseFromRedRun(authorizedRun, SRC);
    const no = caseFromRedRun(unsanctionedRun, SRC);
    expect(yes.evidence.some((e) => e.sourceId === "change-tickets" && e.weight === "decisive")).toBe(true);
    expect(no.evidence.some((e) => e.sourceId === "change-tickets" && e.weight === "decisive")).toBe(true);
    // the ONLY verdict-relevant difference is authorization
    expect(yes.truth).not.toBe(no.truth);
  });

  it("impact drives the primary technique: an exfil run reads as data-exfil (not the access step)", () => {
    // authorizedRun's objective is exfil, so title + MITRE centre exfiltration even
    // though cred-spray is present as the access step (coherence fix).
    const c = caseFromRedRun(authorizedRun, SRC);
    expect(c.archetype).toBe("data-exfil");
    expect(c.learn.mitre?.id).toBe("T1567.002");
    expect(c.alertTitle).toMatch(/moved off/i);
  });

  it("a cred-spray-led run (no exfil/tamper) picks the auth-spray archetype + T1110.003", () => {
    const spray: RedRun = { id: "t-s", operator: "op", targetLabel: "T", objective: "identify", tradecraft: ["cred-spray", "session"], authorized: true, roeRef: "RoE-2", quiet: false };
    const c = caseFromRedRun(spray, SRC);
    expect(c.archetype).toBe("auth-bruteforce");
    expect(c.learn.mitre?.id).toBe("T1110.003");
    expect(c.evidence.some((e) => e.sourceId === "auth-logs" && /spray|4624/i.test(e.label))).toBe(true);
  });

  it("log-wipe surfaces the Event ID 1102 tell and maps to Clear-Event-Logs", () => {
    const wipe: RedRun = { id: "t-w", operator: "op", targetLabel: "T", objective: "modify", tradecraft: ["session", "log-wipe"], authorized: false, quiet: false };
    const c = caseFromRedRun(wipe, SRC);
    expect(c.evidence.some((e) => /1102/.test(e.detail))).toBe(true);
    expect(c.learn.mitre?.id).toBe("T1070.001");
  });

  it("off-host tradecraft (osint / rf-collect) leaves no host signal", () => {
    const recon: RedRun = { id: "t-r", operator: "op", targetLabel: "T", objective: "identify", tradecraft: ["osint", "rf-collect"], authorized: true, roeRef: "RoE-1", quiet: true };
    const c = caseFromRedRun(recon, SRC);
    // only the authorization finding — no fabricated host telemetry
    expect(c.evidence).toHaveLength(1);
    expect(c.evidence[0].sourceId).toBe("change-tickets");
  });

  it("keeps evidence within exposed sources and yields a valid, gradeable case", () => {
    for (const run of [authorizedRun, unsanctionedRun]) {
      const c = caseFromRedRun(run, SRC);
      const known = new Set(c.sources.map((s) => s.id));
      for (const e of c.evidence) expect(known.has(e.sourceId), `${run.id} ${e.id}`).toBe(true);
      expect(c.keySourceIds.every((k) => known.has(k))).toBe(true);
      expect(c.evidence.some((e) => e.weight === "decisive")).toBe(true);
    }
  });
});

describe("HANDOFF_CASES — the shipped generated cases", () => {
  it("all three runs generate cases present in the case index, flagged as handoff", () => {
    expect(HANDOFF_CASES.length).toBe(RED_RUNS.length);
    for (const c of HANDOFF_CASES) {
      expect(SOC_CASES_BY_ID[c.id], c.id).toBeDefined();
      expect(c.handoff, c.id).toBeDefined();
    }
  });

  it("teaches the bridge: authorized runs are Benign-TP, the unsanctioned one is a TP", () => {
    const benign = HANDOFF_CASES.filter((c) => c.truth === "benign-true-positive");
    const tp = HANDOFF_CASES.filter((c) => c.truth === "true-positive");
    expect(benign.length).toBeGreaterThanOrEqual(1);
    expect(tp.length).toBeGreaterThanOrEqual(1);
  });
});
