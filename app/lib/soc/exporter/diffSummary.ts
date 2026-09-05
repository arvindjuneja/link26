// The human "what changed" report printed to stdout (SPEC.md §2.5).
//
// This is the answer to failure mode X3 — "regenerating fixtures blesses a mistake".
// A silent regeneration is impossible: the exporter names every grade row whose
// deltas moved, every shift run whose score moved, and every file whose byte count
// changed, and the PR template requires pasting it.

import type { GradeFile, ShiftRunFile } from "@/app/lib/soc/exporter/schema";

export interface DiffInput {
  /** filename → the bytes currently on disk (absent = a new file). */
  previous: Record<string, string | null>;
  /** filename → the bytes this run produced. */
  next: Record<string, string>;
}

function parse<T>(raw: string | null): T | null {
  if (raw === null) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

function gradeRowDiff(prev: string | null, next: string): string[] {
  const a = parse<GradeFile>(prev);
  const b = parse<GradeFile>(next);
  if (!a || !b) return [];
  const key = (r: { caseId: string; disposition: string }) => `${r.caseId}/${r.disposition}`;
  const before = new Map(a.rows.map((r) => [key(r), r]));
  const lines: string[] = [];
  for (const row of b.rows) {
    const was = before.get(key(row));
    if (!was) {
      lines.push(`  + ${key(row)} — new row (${row.outcomeKey})`);
      continue;
    }
    const changes: string[] = [];
    if (was.breachDelta !== row.breachDelta) changes.push(`breachDelta ${was.breachDelta}→${row.breachDelta}`);
    if (was.noiseDelta !== row.noiseDelta) changes.push(`noiseDelta ${was.noiseDelta}→${row.noiseDelta}`);
    if (was.outcomeKey !== row.outcomeKey) changes.push(`outcomeKey ${was.outcomeKey}→${row.outcomeKey}`);
    if (was.verdictCorrect !== row.verdictCorrect) changes.push(`verdictCorrect ${was.verdictCorrect}→${row.verdictCorrect}`);
    if (was.dispositionCorrect !== row.dispositionCorrect)
      changes.push(`dispositionCorrect ${was.dispositionCorrect}→${row.dispositionCorrect}`);
    if (was.exact !== row.exact) changes.push(`exact ${was.exact}→${row.exact}`);
    if (was.outcome !== row.outcome) changes.push("outcome prose changed");
    if (changes.length > 0) lines.push(`  ~ ${key(row)} ${changes.join(", ")}`);
  }
  for (const k of before.keys()) {
    if (!b.rows.some((r) => key(r) === k)) lines.push(`  - ${k} — row removed`);
  }
  return lines;
}

function shiftRunDiff(prev: string | null, next: string): string[] {
  const a = parse<ShiftRunFile>(prev);
  const b = parse<ShiftRunFile>(next);
  if (!a || !b) return [];
  const before = new Map(a.runs.map((r) => [r.name, r]));
  const lines: string[] = [];
  for (const run of b.runs) {
    const was = before.get(run.name);
    if (!was) {
      lines.push(`  + ${run.name} — new run (${run.score.grade})`);
      continue;
    }
    const changes: string[] = [];
    if (was.score.grade !== run.score.grade) changes.push(`grade ${was.score.grade}→${run.score.grade}`);
    if (was.score.accuracy !== run.score.accuracy) changes.push(`accuracy ${was.score.accuracy}→${run.score.accuracy}`);
    if (was.score.breachRisk !== run.score.breachRisk)
      changes.push(`breachRisk ${was.score.breachRisk}→${run.score.breachRisk}`);
    if (was.score.noise !== run.score.noise) changes.push(`noise ${was.score.noise}→${run.score.noise}`);
    if (was.reward.cashGain !== run.reward.cashGain)
      changes.push(`cashGain ${was.reward.cashGain}→${run.reward.cashGain}`);
    if (was.reward.standingGain !== run.reward.standingGain)
      changes.push(`standingGain ${was.reward.standingGain}→${run.reward.standingGain}`);
    if (changes.length > 0) lines.push(`  ~ ${run.name} ${changes.join(", ")}`);
  }
  return lines;
}

/** True when the two files differ ONLY in the `contentHash` stamp. */
function hashOnly(prev: string, next: string): boolean {
  const strip = (raw: string): string | null => {
    const v = parse<Record<string, unknown>>(raw);
    if (!v || typeof v.contentHash !== "string") return null;
    return JSON.stringify({ ...v, contentHash: "" });
  };
  const a = strip(prev);
  const b = strip(next);
  return a !== null && a === b;
}

export function diffSummary({ previous, next }: DiffInput): string {
  const out: string[] = [];
  const names = Object.keys(next).sort();

  const unchanged: string[] = [];
  const restamped: string[] = [];
  for (const name of names) {
    const prev = previous[name] ?? null;
    if (prev === next[name]) {
      unchanged.push(name);
      continue;
    }
    if (prev === null) {
      out.push(`${name}: NEW (${next[name].length} bytes)`);
      continue;
    }
    if (hashOnly(prev, next[name])) {
      restamped.push(name);
      continue;
    }
    out.push(`${name}: changed (${prev.length} → ${next[name].length} bytes)`);
    const detail = name === "grades.json" ? gradeRowDiff(prev, next[name]) : name === "shift-runs.json" ? shiftRunDiff(prev, next[name]) : [];
    out.push(...detail.slice(0, 40));
    if (detail.length > 40) out.push(`  … and ${detail.length - 40} more`);
  }

  if (restamped.length > 0) {
    out.push(`contentHash restamped only (no content change): ${restamped.join(", ")}`);
  }
  if (out.length === 0) return "No change — the export is byte-identical to what is on disk.";
  if (unchanged.length > 0) out.push(`unchanged: ${unchanged.join(", ")}`);
  return out.join("\n");
}
