// The blue seat — Tier-1 SOC analyst.
//
// This is the FIRST build of the career-sim pivot (decided 2026-06-23): the same
// world, a different chair. Where the red seat (GHOST26) triages the player's OWN
// rising exposure, the blue seat triages a QUEUE of alerts and makes the one call
// every Tier-1 analyst makes on every alert: True Positive / False Positive /
// Benign True Positive → escalate or close.
//
// Grounded in docs/research/soc-tier1-research.md (verified, adversarial). Like the
// red seat, the verbs are abstract: we depict the analyst's *mental model* (which
// log answers which question; encoding ≠ threat; correlate before you conclude),
// never a working detection/evasion technique. Evidence is plausible-but-fictional.
//
// Reuses the engine spine verbatim: trace.ts thresholds drive the BREACH-RISK
// heartbeat (the red seat's own-detection meter, inverted — now the meter is the
// adversary's dwell when you MISS), and grading is a deterministic predicate over
// the player's call (the same crisp, un-gameable shape as evaluateMission).

export type SocArchetype =
  | "encoded-powershell"
  | "auth-bruteforce"
  | "dns-c2"
  // round 2 (docs/research/soc-tier1-cases-round2.md)
  | "phishing"
  | "impossible-travel"
  | "mfa-fatigue"
  | "edr-malware"
  | "data-exfil"
  // round 3 (docs/research/soc-tier1-cases-round3.md)
  | "account-lockout"
  // round 4 (docs/research/soc-tier1-cases-round4.md)
  | "insider-threat";

// The three-way classification every Tier-1 alert resolves to (verified against
// Microsoft Defender/Sentinel taxonomy). Benign-TP is the subtle one: the
// behaviour the rule hunts for really happened, and it was sanctioned.
export type SocVerdict = "true-positive" | "false-positive" | "benign-true-positive";

// The player's call merges classification + disposition into one decision, so the
// three-way verdict AND the escalate/contain choice are made in a single move.
//   close-false-positive  → verdict FP            (the hunted behaviour never happened)
//   close-benign          → verdict Benign-TP     (it happened; a sanction covers it)
//   escalate-tier2        → verdict TP, hand up   (suspicious/confirmed, no isolation)
//   escalate-ir-isolate   → verdict TP, contain   (high-confidence active threat)
// The last is org-dependent authority (some SOCs reserve isolation for T2/IR) —
// modeled per-case via correctDisposition / acceptableDispositions rather than a flag.
export type Disposition =
  | "close-false-positive"
  | "close-benign"
  | "escalate-tier2"
  | "escalate-ir-isolate";

export const DISPOSITIONS: Disposition[] = [
  "close-false-positive",
  "close-benign",
  "escalate-tier2",
  "escalate-ir-isolate",
];

/** Which verdict a disposition encodes. */
export function verdictOf(d: Disposition): SocVerdict {
  switch (d) {
    case "close-false-positive":
      return "false-positive";
    case "close-benign":
      return "benign-true-positive";
    case "escalate-tier2":
    case "escalate-ir-isolate":
      return "true-positive";
  }
}

// A data source the analyst can pull during triage. The skill being taught is the
// "which log answers which question" mental model: each source carries the
// question it answers, and pulling the RIGHT ones surfaces the decisive evidence
// while pulling irrelevant ones just burns shift-minutes.
export interface DataSource {
  id: string;
  label: string; // "EDR — process tree & lineage"
  question: string; // "what spawned this, and what did it do after?"
  cost: number; // shift-minutes consumed to pull it
}

export type EvidenceWeight = "decisive" | "supporting" | "neutral" | "noise";

// A finding revealed when its source is queried. `decisive`/`supporting` point
// toward the truth; `noise` is a plausible red herring (the FP-dominant reality);
// `neutral` is "nothing notable here". Never a runnable command — a log line.
export interface SocEvidence {
  id: string;
  sourceId: string; // which DataSource reveals this
  label: string; // short card title
  detail: string; // the fictional log line / finding
  weight: EvidenceWeight;
}

export interface LearnForReal {
  concept: string; // the real-world skill this case maps to
  mitre?: { id: string; name: string }; // ATT&CK technique, codex-lookup only
  pointer?: string; // a legal sandbox / further reading (e.g. LetsDefend, a MITRE page)
}

export interface SocCase {
  id: string;
  archetype: SocArchetype;

  // The alert as it lands in the queue.
  alertTitle: string;
  detectionRule: string; // the SIEM/EDR rule that fired
  toolSeverity: "Low" | "Medium" | "High" | "Critical"; // what the tool THINKS (often wrong!)
  trigger: string; // the one-line "what fired" the analyst first reads
  asset: string; // host/user the alert concerns

  // Investigation surface.
  sources: DataSource[];
  evidence: SocEvidence[];
  // The sources that actually "answer the question" for this case — surfaced in the
  // debrief as investigation-quality feedback, and the teaching point for
  // log-to-question (pulling these is the move).
  keySourceIds: string[];

  // Ground truth.
  truth: SocVerdict;
  correctDisposition: Disposition;
  // Defensible-but-imperfect calls earn partial credit (e.g. escalate-T2 when
  // isolation was ideal, or vice-versa) instead of being scored as a miss.
  acceptableDispositions?: Disposition[];

  // Teaching debrief, shown after the call regardless of outcome.
  why: string; // why the truth is what it is
  learn: LearnForReal;

  // Set on cases GENERATED from a red-seat run (the "same board, two seats" bridge):
  // the operator's tradecraft becomes the analyst's evidence. See handoff.ts.
  handoff?: { fromRun: string; operator: string };
}

// ── Shift state ──────────────────────────────────────────────────────────────

export interface CaseResult {
  caseId: string;
  chosen: Disposition;
  verdictCorrect: boolean;
  dispositionCorrect: boolean; // exact or acceptable
  queriedSourceIds: string[];
  keySourcesPulled: number; // of the case's keySourceIds, how many were pulled
  timeSpent: number; // shift-minutes
}

// Two pressure meters, both reusing trace.ts thresholds (CALM/ALERT/HUNT/LOCKDOWN):
//   breachRisk — a real threat you closed/under-escalated is DWELLING undetected.
//                This drives the heartbeat: the dread is the adversary's clock now.
//   noise      — crying wolf. Escalating FPs / isolating authorized activity erodes
//                trust and buries the next analyst (alert fatigue made mechanical).
export interface ShiftState {
  shiftId: string;
  caseIds: string[];
  index: number; // current case pointer
  results: Record<string, CaseResult>;
  breachRisk: number; // 0..100
  noise: number; // 0..100
  timeUsed: number; // shift-minutes spent
  timeBudget: number; // soft budget — surfaced to the player; not (yet) scored
}

export type ShiftGrade = "clean" | "rough" | "breached";
