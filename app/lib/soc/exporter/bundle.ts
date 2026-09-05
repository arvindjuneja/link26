// buildBundle(): the real TypeScript modules → `content.json`.
//
// This file WRAPS the engine; it never re-implements it. Everything structural
// (`SOC_CASES`, `SHIFTS`, `RANKS`, `KIT`, `DISPOSITIONS`) is read from the read-only
// web tree (D1); the only transforms are:
//   · 135 inline `DataSource` objects → a 26-entry catalogue + per-case `sourceIds` (D3);
//   · `learn.mitre` flattened, `acceptableDispositions` defaulted to [], `handoff`
//     defaulted to null — so Swift's synthesised Codable needs no CodingKeys (§3.4);
//   · the blue-only ladder and the §3.2 re-voicings (D4, B1).
//
// `caseFromRedRun` runs HERE, at export time: `HANDOFF_CASES` is already
// `RED_RUNS.map(...)` at module load, so the three generated cases leave as ordinary
// literal data and ~270 lines of generator logic never reach Swift.

import { SHIFTS, SOC_CASES } from "@/app/lib/soc/cases";
import { gradeCall } from "@/app/lib/soc/engine";
import { KIT, RANKS } from "@/app/lib/career/state";
import { DISPOSITIONS, type SocCase } from "@/app/lib/soc/types";
import {
  BLUE_ONLY_HANDOFF_SHIFT,
  BLUE_ONLY_UNLOCK_STANDING,
  applyOverride,
  overriddenCaseIds,
} from "@/app/lib/soc/exporter/blueOnly";
import { COPY } from "@/app/lib/soc/exporter/copy";
import { deriveOutcomeKey } from "@/app/lib/soc/exporter/outcomes";
import {
  CONTENT_SCHEMA_VERSION,
  type ExportedBundle,
  type ExportedCase,
  type ExportedShift,
  type ExportedSource,
} from "@/app/lib/soc/exporter/schema";
import { TUNING, TUNING_NUMBER_COUNT, tuningNumbers } from "@/app/lib/soc/exporter/tuning";

const HANDOFF_SHIFT_ID = "handoff-shift";

/** D3 — the 26-source catalogue, derived by de-duplicating every case's `sources`. */
export function buildSources(): ExportedSource[] {
  const byId = new Map<string, ExportedSource>();
  for (const c of SOC_CASES) {
    for (const s of c.sources) {
      const seen = byId.get(s.id);
      const next: ExportedSource = { id: s.id, label: s.label, question: s.question, cost: s.cost };
      if (seen && (seen.label !== next.label || seen.question !== next.question || seen.cost !== next.cost)) {
        throw new Error(`source catalogue conflict for "${s.id}" — two cases describe it differently`);
      }
      byId.set(s.id, next);
    }
  }
  return [...byId.values()].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

const OVERRIDDEN = new Set(overriddenCaseIds());

export function exportCase(c: SocCase): ExportedCase {
  const why = OVERRIDDEN.has(c.id) ? applyOverride(`${c.id}.why`, c.why) : c.why;
  return {
    id: c.id,
    archetype: c.archetype,
    alertTitle: c.alertTitle,
    detectionRule: c.detectionRule,
    toolSeverity: c.toolSeverity,
    trigger: c.trigger,
    asset: c.asset,
    sourceIds: c.sources.map((s) => s.id),
    keySourceIds: [...c.keySourceIds],
    evidence: c.evidence.map((e) => ({
      id: e.id,
      sourceId: e.sourceId,
      label: e.label,
      detail: e.detail,
      weight: e.weight,
    })),
    truth: c.truth,
    correctDisposition: c.correctDisposition,
    acceptableDispositions: [...(c.acceptableDispositions ?? [])],
    why,
    learn: {
      concept: c.learn.concept,
      mitreId: c.learn.mitre?.id ?? null,
      mitreName: c.learn.mitre?.name ?? null,
      pointer: c.learn.pointer ?? null,
    },
    handoff: c.handoff ? { fromRun: c.handoff.fromRun, operator: c.handoff.operator } : null,
  };
}

/** D4 / B1 — the 0/40/80/120/160 ladder, `requiresRedRun: false` on every shift. */
export function buildShifts(): ExportedShift[] {
  return SHIFTS.map((s) => {
    const unlockStanding = BLUE_ONLY_UNLOCK_STANDING[s.id];
    if (unlockStanding === undefined) {
      throw new Error(`stale override: shifts — no blue-only unlockStanding for "${s.id}"`);
    }
    const handoff = s.id === HANDOFF_SHIFT_ID;
    return {
      id: s.id,
      label: handoff ? BLUE_ONLY_HANDOFF_SHIFT.label : s.label,
      caseIds: [...s.caseIds],
      unlockStanding,
      requiresRedRun: false,
      note: handoff ? BLUE_ONLY_HANDOFF_SHIFT.note : (s.note ?? null),
      kind: "campaign",
    };
  });
}

/**
 * D2 — the 96-pair cross-assert. Any wording change in `engine.ts` aborts the export
 * naming the pair, and Swift is then free to compare a keyed enum instead of prose.
 */
export function assertOutcomeKeyParity(): void {
  for (const c of SOC_CASES) {
    for (const d of DISPOSITIONS) {
      const engineText = gradeCall(c, d).outcome;
      const key = deriveOutcomeKey(c, d);
      const copyText = COPY.outcomes[key];
      if (engineText !== copyText) {
        throw new Error(
          `outcomeKey mismatch: ${c.id} / ${d}\n` +
            `  derived key : ${key}\n` +
            `  engine.ts   : ${JSON.stringify(engineText)}\n` +
            `  copy.outcomes: ${JSON.stringify(copyText)}`
        );
      }
    }
  }
}

export function buildBundle(): ExportedBundle {
  assertOutcomeKeyParity();

  const numbers = tuningNumbers();
  if (numbers.length !== TUNING_NUMBER_COUNT) {
    throw new Error(`tuning must hold exactly ${TUNING_NUMBER_COUNT} numbers, found ${numbers.length}`);
  }

  return {
    schemaVersion: CONTENT_SCHEMA_VERSION,
    contentHash: "",
    dispositions: [...DISPOSITIONS] as string[],
    sources: buildSources(),
    cases: SOC_CASES.map(exportCase),
    shifts: buildShifts(),
    ranks: RANKS.map((r) => ({ id: r.id, label: r.label, min: r.min })),
    kit: KIT.map((k) => ({ id: k.id, label: k.label, cost: k.cost, blurb: k.blurb })),
    tuning: TUNING,
  };
}
