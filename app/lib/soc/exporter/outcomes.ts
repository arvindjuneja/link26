// `outcomeKey` WITHOUT touching engine.ts (D2).
//
// `deriveOutcomeKey` re-implements the branch SHAPE of `gradeCall` — nothing else.
// The export then asserts, for all 96 (case × disposition) pairs,
//   gradeCall(c, d).outcome === COPY.outcomes[deriveOutcomeKey(c, d)]
// and aborts naming the pair on any mismatch. Swift compares a keyed enum, never prose.
//
// D12: 11 keys, 12 branch arms. `fp.escalated` covers two arms (escalate-tier2 → noise
// 12, escalate-ir-isolate → noise 20) because they share one outcome string; the
// deltas come from `tuning`, never from the key.

import type { Disposition, SocCase } from "@/app/lib/soc/types";
import { verdictOf } from "@/app/lib/soc/types";
import { OUTCOME_KEYS, type OutcomeKey } from "@/app/lib/soc/exporter/schema";

export { OUTCOME_KEYS };
export type { OutcomeKey };

const isEscalate = (d: Disposition) => d === "escalate-tier2" || d === "escalate-ir-isolate";

export function deriveOutcomeKey(c: SocCase, chosen: Disposition): OutcomeKey {
  const verdictCorrect = verdictOf(chosen) === c.truth;
  const exact = chosen === c.correctDisposition;
  const dispositionCorrect = exact || (c.acceptableDispositions?.includes(chosen) ?? false);

  if (c.truth === "true-positive") {
    if (!isEscalate(chosen)) return "tp.missed";
    if (dispositionCorrect) return "tp.escalated-correct";
    if (chosen === "escalate-ir-isolate") return "tp.over-contained";
    return "tp.under-contained";
  }

  if (c.truth === "false-positive") {
    if (!isEscalate(chosen)) return verdictCorrect ? "fp.closed-fp" : "fp.closed-as-benign";
    return "fp.escalated";
  }

  // benign-true-positive
  if (chosen === "close-benign") return "btp.closed-benign";
  if (chosen === "close-false-positive") return "btp.closed-as-fp";
  if (chosen === "escalate-ir-isolate") return "btp.isolated";
  return "btp.escalated-t2";
}
