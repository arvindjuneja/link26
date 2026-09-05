// The drift guard (SPEC.md §2.5, amended by SPEC-ADDENDUM S6/S7/S11).
//
// Lives under `app/` because that is the verified vitest include glob
// (`app/**/*.test.ts`), so it runs inside the existing `npm test` and a content-only
// PR cannot merge with a stale export.
//
// Check #9 (`git diff --exit-code` over the four protected web directories) has MOVED
// to `ios/scripts/verify.sh` + the CI `guards` job per S7 — it needs a merge-base and
// does not belong in a unit-test process. Checks #1–#8 are here, plus #10
// (fixture exhaustiveness, S6) and the `copy.meters == intro.meters` assertion (S11).

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { SOC_CASES } from "@/app/lib/soc/cases";
import { gradeCall } from "@/app/lib/soc/engine";
import { DISPOSITIONS } from "@/app/lib/soc/types";
import { ALL_FILE_NAMES, buildAll, isContentFile, renderAll, type FileName } from "@/app/lib/soc/exporter/build";
import { COPY } from "@/app/lib/soc/exporter/copy";
import { deriveOutcomeKey } from "@/app/lib/soc/exporter/outcomes";
import { OUTCOME_KEYS, type ExportedCase, type OutcomeKey } from "@/app/lib/soc/exporter/schema";
import { SOURCE_PINS, sliceFor, verifyPins } from "@/app/lib/soc/exporter/sourcePins";
import { sha256Hex } from "@/app/lib/soc/exporter/canonical";
import { TUNING_NUMBER_COUNT, tuningNumbers } from "@/app/lib/soc/exporter/tuning";

const REPO_ROOT = fileURLToPath(new URL("../../../../", import.meta.url));
const CONTENT_DIR = `${REPO_ROOT}ios/SentryCore/Sources/SentryContent/Resources/`;
const FIXTURE_DIR = `${REPO_ROOT}ios/SentryCore/Sources/SentryFixtures/Resources/`;

const pathFor = (name: FileName): string => `${isContentFile(name) ? CONTENT_DIR : FIXTURE_DIR}${name}`;
const committed = (name: FileName): string => readFileSync(pathFor(name), "utf8");

// Built ONCE — the whole guard is one in-memory re-run of the exporter.
const files = buildAll();
const rendered = renderAll(files);

/** B4 (addendum) — the credibility guardrail, applied to the ARTEFACT, not the source. */
const PAY_FIGURE = /\$\s?\d|\bsalar(y|ies)\b|\bper year\b|\bpay\b\s*(range|band)|\b(USD|EUR|PLN)\b/i;

/** Walk every value in a JSON tree. */
function walk(value: unknown, visit: (key: string, value: unknown) => void, key = ""): void {
  visit(key, value);
  if (Array.isArray(value)) {
    for (const v of value) walk(v, visit, key);
    return;
  }
  if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) walk(v, visit, k);
  }
}

describe("drift guard · #1 byte equality", () => {
  it.each(ALL_FILE_NAMES)("%s is byte-identical to a fresh export", (name) => {
    expect(committed(name)).toBe(rendered[name]);
  });

  it("writes exactly 10 files", () => {
    expect(ALL_FILE_NAMES).toHaveLength(10);
  });

  it("is canonical — sorted keys, 2-space, LF, one trailing newline, no BOM", () => {
    for (const name of ALL_FILE_NAMES) {
      const raw = rendered[name];
      expect(raw.startsWith("﻿"), `${name} has a BOM`).toBe(false);
      expect(raw.includes("\r"), `${name} has CRLF`).toBe(false);
      expect(raw.endsWith("\n"), `${name} has no trailing newline`).toBe(true);
      expect(raw.endsWith("\n\n"), `${name} has more than one trailing newline`).toBe(false);
      expect(raw, `${name} is not 2-space indented`).toContain('\n  "');
      // sorted keys survive a re-serialise of the parsed value
      expect(`${JSON.stringify(JSON.parse(raw), null, 2)}\n`).toBe(raw);
    }
  });

  it("carries no timestamp and no git SHA", () => {
    for (const name of ALL_FILE_NAMES) {
      expect(rendered[name], `${name} looks like it embeds a date`).not.toMatch(
        /"(generatedAt|builtAt|timestamp|gitSha|commit)"/
      );
    }
  });
});

describe("drift guard · #2 one contentHash", () => {
  it("is identical across all 10 files", () => {
    const hashes = new Set(ALL_FILE_NAMES.map((n) => (JSON.parse(rendered[n]) as { contentHash: string }).contentHash));
    expect([...hashes]).toHaveLength(1);
    expect([...hashes][0]).toMatch(/^sha256:[0-9a-f]{64}$/);
  });
});

describe("drift guard · #3 the 96-row matrix", () => {
  it("has exactly SOC_CASES.length × DISPOSITIONS.length rows", () => {
    expect(files["grades.json"].rows).toHaveLength(SOC_CASES.length * DISPOSITIONS.length);
    expect(SOC_CASES.length * DISPOSITIONS.length).toBe(96);
  });

  it("covers every (case, disposition) pair exactly once", () => {
    const seen = new Set(files["grades.json"].rows.map((r) => `${r.caseId}/${r.disposition}`));
    expect(seen.size).toBe(96);
  });

  it("has 12 synthetic rows over 3 constructed cases (D11)", () => {
    expect(files["grades-synthetic.json"].cases).toHaveLength(3);
    expect(files["grades-synthetic.json"].rows).toHaveLength(12);
  });
});

describe("drift guard · #4 outcome-key exhaustiveness", () => {
  const reached = new Set<OutcomeKey>([
    ...files["grades.json"].rows.map((r) => r.outcomeKey),
    ...files["grades-synthetic.json"].rows.map((r) => r.outcomeKey),
  ]);

  it.each(OUTCOME_KEYS)("%s is reached by at least one fixture row", (key) => {
    expect(reached.has(key)).toBe(true);
  });

  it("confirms D11 — the 96 real rows alone reach only 10 of the 11", () => {
    const real = new Set(files["grades.json"].rows.map((r) => r.outcomeKey));
    expect(real.size).toBe(10);
    expect(real.has("tp.under-contained")).toBe(false);
  });

  it("emits no key outside the closed set", () => {
    for (const key of reached) expect(OUTCOME_KEYS).toContain(key);
  });
});

describe("drift guard · #5 integer meters", () => {
  it("every delta and every meter in every fixture is an integer", () => {
    const INT_KEYS = new Set([
      "breachDelta",
      "noiseDelta",
      "breachRisk",
      "noise",
      "timeUsed",
      "timeSpent",
      "timeBudget",
      "index",
      "keySourcesPulled",
      "cashGain",
      "standingGain",
      "cash",
      "standing",
    ]);
    for (const name of ALL_FILE_NAMES) {
      walk(JSON.parse(rendered[name]), (key, value) => {
        if (INT_KEYS.has(key) && typeof value === "number") {
          expect(Number.isInteger(value), `${name}: ${key} = ${value} is not an integer`).toBe(true);
        }
      });
    }
  });
});

describe("drift guard · #6 referential integrity", () => {
  const catalogue = new Set(files["content.json"].sources.map((s) => s.id));

  const everyCase: ExportedCase[] = [
    ...files["content.json"].cases,
    ...files["grades-synthetic.json"].cases,
    ...files["scoring.json"].cases,
  ];

  it("has a 26-source catalogue (D3)", () => {
    expect(catalogue.size).toBe(26);
    expect(files["content.json"].sources).toHaveLength(26);
  });

  it("resolves every sourceId, keySourceId and evidence.sourceId", () => {
    for (const c of everyCase) {
      for (const id of c.sourceIds) expect(catalogue.has(id), `${c.id}: unknown source ${id}`).toBe(true);
      const own = new Set(c.sourceIds);
      for (const id of c.keySourceIds) {
        expect(catalogue.has(id), `${c.id}: unknown key source ${id}`).toBe(true);
        expect(own.has(id), `${c.id}: key source ${id} is not one of the case's own sources`).toBe(true);
      }
      for (const e of c.evidence) {
        expect(own.has(e.sourceId), `${c.id}: evidence ${e.id} points outside the case`).toBe(true);
      }
    }
  });

  it("resolves every shift's caseIds and every daily board", () => {
    const byId = new Set(files["content.json"].cases.map((c) => c.id));
    for (const s of files["content.json"].shifts) {
      for (const id of s.caseIds) expect(byId.has(id), `${s.id}: unknown case ${id}`).toBe(true);
    }
    for (const day of files["daily.json"].days) {
      expect(day.caseIds).toHaveLength(5);
      for (const id of day.caseIds) expect(byId.has(id), `${day.date}: unknown case ${id}`).toBe(true);
    }
  });

  it("applies the blue-only ladder to every shift (B1)", () => {
    const ladder = files["content.json"].shifts.map((s) => s.unlockStanding);
    expect(ladder).toEqual([0, 40, 80, 120, 160]);
    for (const s of files["content.json"].shifts) expect(s.requiresRedRun).toBe(false);
  });
});

describe("drift guard · #7 the credibility guardrail (B4)", () => {
  it.each(ALL_FILE_NAMES)("%s states no pay figure", (name) => {
    const hit = PAY_FIGURE.exec(rendered[name]);
    const context = hit ? rendered[name].slice(Math.max(0, hit.index - 80), hit.index + 80) : "";
    expect(hit, `${name} matched the pay-figure guardrail near: ${context}`).toBeNull();
  });
});

describe("drift guard · #8 the pins and the 96-pair cross-assert", () => {
  it("every sourcePins.ts SHA still matches", () => {
    expect(() => verifyPins()).not.toThrow();
  });

  it("names the region when a pin goes stale", () => {
    for (const p of SOURCE_PINS) expect(sha256Hex(sliceFor(p))).toBe(p.sha256);
  });

  it("gradeCall's prose equals copy.outcomes[deriveOutcomeKey] for all 96 pairs (D2)", () => {
    for (const c of SOC_CASES) {
      for (const d of DISPOSITIONS) {
        expect(gradeCall(c, d).outcome, `${c.id} / ${d}`).toBe(COPY.outcomes[deriveOutcomeKey(c, d)]);
      }
    }
  });

  it("every fixture row's outcome matches its key", () => {
    for (const row of [...files["grades.json"].rows, ...files["grades-synthetic.json"].rows]) {
      expect(row.outcome, `${row.caseId} / ${row.disposition}`).toBe(COPY.outcomes[row.outcomeKey]);
    }
  });
});

describe("drift guard · #10 fixture exhaustiveness (S6)", () => {
  const grades = new Set<string>([
    ...files["shift-runs.json"].runs.map((r) => r.score.grade),
    ...files["scoring.json"].rows.map((r) => r.score.grade),
    ...files["career.json"].awards.map((a) => a.score.grade),
  ]);
  const qualities = new Set(files["scoring.json"].rows.flatMap((r) => r.investigations.map((i) => i.quality)));

  it.each(["clean", "rough", "breached"])("ShiftGrade %s appears in a fixture", (g) => {
    expect(grades.has(g)).toBe(true);
  });

  it.each(["blind", "partial", "thorough"])("InvestigationQuality %s appears in a fixture", (q) => {
    expect(qualities.has(q)).toBe(true);
  });

  it("scoring.json carries at least 12 rows", () => {
    expect(files["scoring.json"].rows.length).toBeGreaterThanOrEqual(12);
  });

  it("covers the S6 edges by name", () => {
    const names = new Set(files["scoring.json"].rows.map((r) => r.name));
    for (const n of [
      "empty-shift",
      "all-blind",
      "two-missed",
      "noise-hunt-perfect",
      "breach-exactly-80",
      "no-key-sources",
      "unknown-case-id",
      "clean-accuracy-exactly-080",
      "rough-accuracy-one-step-below",
      "rough-one-blind",
      "rough-noise-lockdown",
      "rough-one-missed-breach-30",
      "overflow-four-missed",
    ]) {
      expect(names.has(n), `scoring.json is missing the ${n} row`).toBe(true);
    }
    const applies = new Set(files["scoring.json"].applyRows.map((r) => r.name));
    expect(applies.has("replace-in-place")).toBe(true);
    expect(applies.has("duplicate-queried-id")).toBe(true);
  });

  it("keyTotalSum == 0 yields investigationRate 1 and a thorough read", () => {
    const row = files["scoring.json"].rows.find((r) => r.name === "no-key-sources");
    expect(row?.score.investigationRateDenominator).toBe(0);
    expect(row?.score.investigationRate).toBe(1);
    expect(row?.investigations.every((i) => i.quality === "thorough")).toBe(true);
  });

  it("a meter overflow clamps to 100", () => {
    const row = files["scoring.json"].rows.find((r) => r.name === "overflow-four-missed");
    expect(row?.score.breachRisk).toBe(100);
    expect(row?.score.missedDetections).toBe(4);
  });

  it("applyCall replaces a repeated caseId in place", () => {
    const row = files["scoring.json"].applyRows.find((r) => r.name === "replace-in-place");
    expect(row?.after.results.map((r) => r.caseId)).toEqual(row?.before.results.map((r) => r.caseId));
    expect(row?.after.index).toBe((row?.before.index ?? 0) + 1);
  });

  it("a duplicated queried id is counted twice", () => {
    const row = files["scoring.json"].applyRows.find((r) => r.name === "duplicate-queried-id");
    expect(row?.queriedSourceIds[0]).toBe(row?.queriedSourceIds[1]);
    expect(row?.after.results[0].keySourcesPulled).toBe(2);
  });
});

describe("drift guard · copy invariants (S11)", () => {
  it("copy.meters deep-equals intro.meters", () => {
    const intro = files["copy.json"].intro.meters;
    const meters = files["copy.json"].meters;
    expect(intro.map((m) => m.key).sort()).toEqual(Object.keys(meters).sort());
    for (const m of intro) {
      expect({ label: m.label, fear: m.fear }, `meter ${m.key}`).toEqual(meters[m.key]);
    }
  });

  it("the first-run block is reprinted verbatim under About (§5.11)", () => {
    expect(files["copy.json"].about.fiction).toBe(files["copy.json"].firstRun.body);
    expect(files["copy.json"].firstRun.body.length).toBeGreaterThan(120);
  });

  it("carries all 11 outcome strings and all 4 disposition buttons", () => {
    expect(Object.keys(files["copy.json"].outcomes).sort()).toEqual([...OUTCOME_KEYS].sort());
    expect(Object.keys(files["copy.json"].dispositionMeta).sort()).toEqual([...DISPOSITIONS].sort());
    expect(files["content.json"].dispositions).toEqual([...DISPOSITIONS]);
  });

  it("carries a coach step for each anchor, with an advance rule (S4)", () => {
    const steps = files["copy.json"].coachSteps;
    expect(steps.map((s) => s.anchor)).toEqual(["sources", "evidence", "call"]);
    expect(steps.map((s) => s.advance)).toEqual(["on-first-source-pulled", "button", "terminal"]);
    expect(steps[0].body).toContain("tap it");
    expect(steps[1].body).toContain("SOURCES");
  });

  it("gives every severity and every handler tone a fallback (S5)", () => {
    expect(Object.keys(files["copy.json"].severityMeta.entries).sort()).toEqual([
      "Critical",
      "High",
      "Low",
      "Medium",
    ]);
    expect(files["copy.json"].severityMeta.fallback).toBeTruthy();
    expect(Object.keys(files["copy.json"].handlerToneMeta.entries).sort()).toEqual([
      "milestone",
      "tip",
      "warm",
      "warn",
    ]);
    expect(files["copy.json"].handlerToneMeta.fallback).toBeTruthy();
  });

  it("gives every handler template a sender (S2)", () => {
    for (const [id, t] of Object.entries(files["copy.json"].handler.templates)) {
      expect(["vale", "mercer"], `template ${id}`).toContain(t.sender);
      expect(t.subject.length, `template ${id}`).toBeGreaterThan(0);
      expect(t.body.length, `template ${id}`).toBeGreaterThan(0);
    }
  });

  it("has no empty chrome string", () => {
    for (const [k, v] of Object.entries(files["copy.json"].chrome)) {
      expect(v.length, `chrome.${k} is empty`).toBeGreaterThan(0);
    }
  });
});

describe("drift guard · tuning (D7, S8)", () => {
  it("holds exactly 29 numbers", () => {
    expect(tuningNumbers()).toHaveLength(TUNING_NUMBER_COUNT);
    expect(TUNING_NUMBER_COUNT).toBe(29);
  });

  it("matches the thresholds the web engine actually branches on", () => {
    const t = files["content.json"].tuning;
    expect(t.trace).toEqual({ min: 0, max: 100, alert: 25, hunt: 50, lockdown: 80 });
    expect(t.bpm).toEqual({ CALM: 50, ALERT: 76, HUNT: 112, LOCKDOWN: 150 });
    expect(t.shift.cleanAccuracy).toBe(0.8);
    expect(t.shift.breachedMissedDetections).toBe(2);
  });
});

describe("drift guard · the D13 golden run", () => {
  const run = files["shift-runs.json"].runs.find((r) => r.name === "shift1-demo-complete");

  it("matches the pinned ?demo=complete score exactly", () => {
    expect(run).toBeDefined();
    expect(run?.score.accuracy).toBe(0.8571428571428571);
    expect(run?.score.accuracy).toBe(6 / 7);
    expect(run?.score).toMatchObject({
      total: 7,
      verdictCorrect: 6,
      dispositionCorrect: 6,
      missedDetections: 0,
      falseEscalations: 1,
      blindCalls: 1,
      thoroughCalls: 6,
      investigationRate: 0.875,
      grade: "rough",
      breachRisk: 0,
      noise: 12,
    });
    expect(run?.reward.cashGain).toBe(300);
    expect(run?.reward.standingGain).toBe(15);
    expect(run?.reward.rankUp).toBeNull();
    expect(run?.reward.state).toMatchObject({ cash: 300, standing: 15, shiftsCleaned: 0 });
    expect(run?.inbox.map((m) => m.id)).toEqual(["ev-rough", "tip-kit"]);
  });

  it("carries a ShiftState snapshot after every step of all 7 runs", () => {
    expect(files["shift-runs.json"].runs).toHaveLength(7);
    for (const r of files["shift-runs.json"].runs) {
      expect(r.steps.length, r.name).toBe(r.caseIds.length);
      r.steps.forEach((step, i) => {
        expect(step.after.index, `${r.name} step ${i}`).toBe(i + 1);
        expect(step.after.results, `${r.name} step ${i}`).toHaveLength(i + 1);
      });
    }
  });
});

describe("drift guard · the blue-only inbox (S3)", () => {
  it("suppresses tip-redrun and re-applies the cap", () => {
    for (const s of files["handler.json"].scenarios) {
      expect(s.messagesAll.length, s.name).toBeLessThanOrEqual(4);
      expect(s.messagesBlueOnly.length, s.name).toBeLessThanOrEqual(4);
      expect(s.messagesBlueOnly.some((m) => m.id === "tip-redrun"), s.name).toBe(false);
      expect(s.messagesBlueOnly).toEqual(s.messagesAll.filter((m) => m.id !== "tip-redrun"));
    }
  });

  it("covers 14 distinct scenarios", () => {
    expect(files["handler.json"].scenarios).toHaveLength(14);
    expect(new Set(files["handler.json"].scenarios.map((s) => s.name)).size).toBe(14);
  });

  it("exercises the cap AND the suppression together", () => {
    const cap = files["handler.json"].scenarios.find((s) => s.name === "cap-four");
    expect(cap?.messagesAll).toHaveLength(4);
    expect(cap?.messagesBlueOnly).toHaveLength(3);
  });
});
