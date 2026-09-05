// buildFixtures(): the 7 golden files (SPEC.md §2.4, amended by SPEC-ADDENDUM S3/S6).
//
// Every expected value here is computed by the REAL TypeScript engine — `gradeCall`,
// `applyCall`, `scoreShift`, `awardForShift`, `inboxFor`, `getTraceStatus`. Nothing is
// hand-asserted, so a Swift port that disagrees disagrees with TypeScript, not with a
// transcription. The only hand-built things are the SHAPES: which shifts, which calls,
// which edge meters.

import { SHIFTS, SOC_CASES, SOC_CASES_BY_ID } from "@/app/lib/soc/cases";
import {
  applyCall,
  assembleShift,
  buildCaseResult,
  gradeCall,
  investigationOf,
  overallShiftStatus,
  scoreShift,
  type ShiftScore,
} from "@/app/lib/soc/engine";
import { clampLevel, getTraceStatus } from "@/app/lib/game/trace";
import {
  INITIAL_CAREER,
  KIT,
  RANKS,
  RED_RUN_CUT,
  awardForShift,
  awardRedRun,
  buyKit,
  isUnlocked,
  nextRank,
  rankFor,
  type CareerState,
} from "@/app/lib/career/state";
import { inboxFor, type HandlerEvent, type HandlerMessage } from "@/app/lib/career/handler";
import {
  DISPOSITIONS,
  type CaseResult,
  type DataSource,
  type Disposition,
  type ShiftState,
  type SocCase,
} from "@/app/lib/soc/types";
import { exportCase } from "@/app/lib/soc/exporter/bundle";
import { deriveOutcomeKey } from "@/app/lib/soc/exporter/outcomes";
import {
  CONTENT_SCHEMA_VERSION,
  type ApplyRow,
  type CareerFile,
  type CareerJSON,
  type CaseResultJSON,
  type ExportedBundle,
  type ExportedRank,
  type ExportedShift,
  type GradeFile,
  type GradeRow,
  type HandlerEventJSON,
  type HandlerFile,
  type HandlerMessageJSON,
  type HandlerScenario,
  type ScoringFile,
  type ScoringRow,
  type ShiftRun,
  type ShiftRunFile,
  type ShiftRunStep,
  type ShiftScoreJSON,
  type ShiftStateJSON,
  type ShiftStateSnapshot,
  type SyntheticGradeFile,
  type TraceFile,
} from "@/app/lib/soc/exporter/schema";

// ── small conversions ────────────────────────────────────────────────────────

const careerJSON = (c: CareerState): CareerJSON => ({
  cash: c.cash,
  standing: c.standing,
  shiftsCleaned: c.shiftsCleaned,
  redRunsDone: c.redRunsDone,
  gear: [...c.gear],
});

const rankJSON = (r: { id: string; label: string; min: number } | null): ExportedRank | null =>
  r ? { id: r.id, label: r.label, min: r.min } : null;

const resultJSON = (r: CaseResult): CaseResultJSON => ({
  caseId: r.caseId,
  chosen: r.chosen,
  verdictCorrect: r.verdictCorrect,
  dispositionCorrect: r.dispositionCorrect,
  queriedSourceIds: [...r.queriedSourceIds],
  keySourcesPulled: r.keySourcesPulled,
  timeSpent: r.timeSpent,
});

/** DV-1 — `Object.values` is TS insertion order; the export serialises that order. */
const orderedResults = (s: ShiftState): CaseResult[] => Object.values(s.results);

const snapshotOf = (s: ShiftState): ShiftStateSnapshot => ({
  index: s.index,
  breachRisk: s.breachRisk,
  noise: s.noise,
  timeUsed: s.timeUsed,
  results: orderedResults(s).map(resultJSON),
  overallStatus: overallShiftStatus(s),
});

const stateJSON = (s: ShiftState): ShiftStateJSON => ({
  shiftId: s.shiftId,
  caseIds: [...s.caseIds],
  index: s.index,
  timeBudget: s.timeBudget,
  breachRisk: s.breachRisk,
  noise: s.noise,
  timeUsed: s.timeUsed,
  results: orderedResults(s).map(resultJSON),
});

/** Rates carry numerator and denominator so a Swift failure localises to the counter. */
function scoreJSON(s: ShiftState, cases: Record<string, SocCase>): ShiftScoreJSON {
  const score = scoreShift(s, cases);
  let keyPulled = 0;
  let keyTotal = 0;
  for (const r of orderedResults(s)) {
    const c = cases[r.caseId];
    if (!c) continue;
    keyTotal += c.keySourceIds.length;
    keyPulled += r.keySourcesPulled;
  }
  return {
    total: score.total,
    verdictCorrect: score.verdictCorrect,
    dispositionCorrect: score.dispositionCorrect,
    missedDetections: score.missedDetections,
    falseEscalations: score.falseEscalations,
    accuracy: score.accuracy,
    accuracyNumerator: score.verdictCorrect,
    accuracyDenominator: score.total,
    blindCalls: score.blindCalls,
    thoroughCalls: score.thoroughCalls,
    investigationRate: score.investigationRate,
    investigationRateNumerator: keyPulled,
    investigationRateDenominator: keyTotal,
    grade: score.grade,
    breachRisk: score.breachRisk,
    noise: score.noise,
  };
}

const messageJSON = (m: HandlerMessage): HandlerMessageJSON => ({
  id: m.id,
  from: m.from,
  role: m.role,
  subject: m.subject,
  body: m.body,
  tone: m.tone,
});

/** S3 — the exporter WRAPS `inboxFor`; it never re-implements the selection order. */
export const messagesAll = (c: CareerState, ev: HandlerEvent): HandlerMessageJSON[] =>
  inboxFor(c, ev).map(messageJSON);

/** S3 — iOS has no red seat, so the cross-seat nudge is dropped; the cap is re-applied. */
export const messagesBlueOnly = (c: CareerState, ev: HandlerEvent): HandlerMessageJSON[] =>
  inboxFor(c, ev)
    .filter((m) => m.id !== "tip-redrun")
    .slice(0, 4)
    .map(messageJSON);

const eventJSON = (ev: HandlerEvent): HandlerEventJSON => ({
  type: ev.type ?? null,
  rankUp: rankJSON(ev.rankUp ?? null),
  unlocked: (ev.unlocked ?? []).map((u) => ({ id: u.id, label: u.label })),
});

// ── shift helpers ────────────────────────────────────────────────────────────

const sourceCost = (c: SocCase, id: string): number => c.sources.find((s) => s.id === id)?.cost ?? 0;
const timeFor = (c: SocCase, queried: string[]): number =>
  queried.reduce((a, id) => a + sourceCost(c, id), 0);

/** Every DataSource in the corpus, so synthetic cases reuse the 26-entry catalogue. */
const SOURCE_BY_ID: Record<string, DataSource> = (() => {
  const out: Record<string, DataSource> = {};
  for (const c of SOC_CASES) for (const s of c.sources) out[s.id] = s;
  return out;
})();

const src = (id: string): DataSource => {
  const s = SOURCE_BY_ID[id];
  if (!s) throw new Error(`synthetic case references an unknown source: ${id}`);
  return s;
};

function unlockedIds(c: CareerState, shifts: ExportedShift[]): string[] {
  return shifts
    .filter((s) => isUnlocked(c, { unlockStanding: s.unlockStanding, requiresRedRun: s.requiresRedRun }))
    .map((s) => s.id);
}

// ── grades.json — 96 rows ────────────────────────────────────────────────────

function gradeRow(c: SocCase, d: Disposition): GradeRow {
  const g = gradeCall(c, d);
  const key = deriveOutcomeKey(c, d);
  return {
    caseId: c.id,
    disposition: d,
    verdictCorrect: g.verdictCorrect,
    dispositionCorrect: g.dispositionCorrect,
    exact: g.exact,
    breachDelta: g.breachDelta,
    noiseDelta: g.noiseDelta,
    outcomeKey: key,
    outcome: g.outcome,
  };
}

function buildGrades(contentHash: string): GradeFile {
  const rows: GradeRow[] = [];
  for (const c of SOC_CASES) for (const d of DISPOSITIONS) rows.push(gradeRow(c, d));
  return { schemaVersion: CONTENT_SCHEMA_VERSION, contentHash, rows };
}

// ── grades-synthetic.json — the DEAD BRANCH (D11) ────────────────────────────
//
// 0 of the 96 real rows produce `breachDelta == 10`: every TP whose correct call is
// `escalate-ir-isolate` also accepts `escalate-tier2`, and the two whose correct call
// IS `escalate-tier2` have empty acceptables, so isolating them lands in OVER-contained.
// These three constructed cases reach `tp.under-contained` and the 12th branch arm.

const SYNTHETIC_GRADE_CASES: SocCase[] = [
  {
    id: "syn-tp-isolate-only",
    archetype: "edr-malware",
    alertTitle: "Unsigned binary beaconing from a build agent",
    detectionRule: "EDR · unsigned image with fixed-interval outbound",
    toolSeverity: "High",
    trigger:
      "An unsigned binary on BLD-AGENT-03 has been reaching the same external host on a fixed interval since 03:40.",
    asset: "BLD-AGENT-03 · service account svc-build",
    sources: [src("edr-process-tree"), src("network-proxy"), src("change-tickets")],
    keySourceIds: ["edr-process-tree", "network-proxy"],
    evidence: [
      {
        id: "syn1-tree",
        sourceId: "edr-process-tree",
        label: "Spawned by the agent service, not a job",
        detail:
          "The binary's parent is the build-agent service itself, with no pipeline job in the lineage — nothing scheduled it.",
        weight: "decisive",
      },
      {
        id: "syn1-net",
        sourceId: "network-proxy",
        label: "Fixed-interval outbound to a young domain",
        detail: "Outbound every 47 seconds to a domain registered four days ago, with no other host in the estate talking to it.",
        weight: "decisive",
      },
      {
        id: "syn1-cab",
        sourceId: "change-tickets",
        label: "No change record",
        detail: "No change ticket, maintenance window or engagement covers BLD-AGENT-03 this week.",
        weight: "supporting",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-ir-isolate",
    acceptableDispositions: [],
    why: "Live, unauthorized code with a live channel out of a build host is contain-now: the build agent signs artefacts the whole estate trusts. Handing it to Tier-2 without containment leaves the channel open while the ticket queues, which is the under-contained call this fixture exists to grade.",
    learn: {
      concept:
        "Containment urgency is a property of the ASSET as much as the alert: a host that signs or distributes artefacts is contained first and triaged second.",
      mitre: { id: "T1071", name: "Application Layer Protocol" },
      pointer: "Fixture-only case — it exists to reach the under-contained branch.",
    },
  },
  {
    id: "syn-tp-t2-with-isolate",
    archetype: "insider-threat",
    alertTitle: "Bulk export by an account already under review",
    detectionRule: "DLP · volume anomaly on a flagged account",
    toolSeverity: "Medium",
    trigger: "mokoro exported 4.2 GB from the deal room at 22:10, a week after HR opened a review.",
    asset: "user mokoro (Corporate Development)",
    sources: [src("dlp-hits"), src("hr-directory"), src("cloud-activity")],
    keySourceIds: ["dlp-hits", "hr-directory"],
    evidence: [
      {
        id: "syn2-dlp",
        sourceId: "dlp-hits",
        label: "Volume far above the user's own baseline",
        detail: "4.2 GB against a 90-day median of 60 MB, all from one folder, in one sitting.",
        weight: "decisive",
      },
      {
        id: "syn2-hr",
        sourceId: "hr-directory",
        label: "Open review, no departure date",
        detail: "HR opened a conduct review on 4 June. No leaving date is recorded.",
        weight: "decisive",
      },
      {
        id: "syn2-cloud",
        sourceId: "cloud-activity",
        label: "Destination is a personal account",
        detail: "The egress lands in a consumer storage account, not the corporate tenant.",
        weight: "supporting",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-tier2",
    acceptableDispositions: ["escalate-ir-isolate"],
    why: "This is real, unauthorized movement of company data, so it escalates — but an insider under an open HR review belongs with Tier-2, HR and legal before a single analyst isolates the person's device. Isolation is defensible here, which is exactly why this case carries it as an acceptable call.",
    learn: {
      concept:
        "Insider cases are escalated, not contained unilaterally: the evidence chain and the employment process both break if the subject learns they are being watched.",
      mitre: { id: "T1567", name: "Exfiltration Over Web Service" },
      pointer: "Fixture-only case — it exists to grade an acceptable-but-not-exact escalation.",
    },
  },
  {
    id: "syn-btp-strict",
    archetype: "encoded-powershell",
    alertTitle: "Encoded PowerShell during a patch window",
    detectionRule: "EDR · powershell.exe launched with -EncodedCommand",
    toolSeverity: "High",
    trigger: "An encoded PowerShell command ran on PATCH-RELAY-02 at 02:05, inside the monthly maintenance window.",
    asset: "PATCH-RELAY-02 · service account svc-patch",
    sources: [src("edr-process-tree"), src("decoded-command"), src("change-tickets")],
    keySourceIds: ["change-tickets", "decoded-command"],
    evidence: [
      {
        id: "syn3-tree",
        sourceId: "edr-process-tree",
        label: "Parent is the management agent",
        detail: "The lineage is the patch-management agent, running as its own service account — the estate's normal deployment path.",
        weight: "supporting",
      },
      {
        id: "syn3-decode",
        sourceId: "decoded-command",
        label: "Decodes to an inventory query",
        detail: "The decoded block reads local package versions and writes them to the management server. Nothing leaves the estate.",
        weight: "decisive",
      },
      {
        id: "syn3-cab",
        sourceId: "change-tickets",
        label: "CHG-5104 covers the window",
        detail: "CHG-5104 names PATCH-RELAY-02, the agent and the 02:00–04:00 window, approved by the platform team.",
        weight: "decisive",
      },
    ],
    truth: "benign-true-positive",
    correctDisposition: "close-benign",
    acceptableDispositions: [],
    why: "The behaviour the rule hunts for really happened — encoded PowerShell ran — and a named change ticket sanctions it. That is a Benign True Positive: the detection is right and the activity is authorized. Closing it as a false positive would tell the next analyst the rule misfired, and it did not.",
    learn: {
      concept:
        "Encoding is not the threat; the sanction artifact is the discriminator. A named change ticket turns a correct detection into a benign true positive without touching the rule's logic.",
      mitre: { id: "T1059.001", name: "Command and Scripting Interpreter: PowerShell" },
      pointer: "Fixture-only case — it exists to grade a Benign-TP with no acceptable alternatives.",
    },
  },
];

function buildSyntheticGrades(contentHash: string): SyntheticGradeFile {
  const rows: GradeRow[] = [];
  for (const c of SYNTHETIC_GRADE_CASES) for (const d of DISPOSITIONS) rows.push(gradeRow(c, d));
  return {
    schemaVersion: CONTENT_SCHEMA_VERSION,
    contentHash,
    cases: SYNTHETIC_GRADE_CASES.map(exportCase),
    rows,
  };
}

// ── shift-runs.json — 7 scripted runs ────────────────────────────────────────

interface RunSpec {
  name: string;
  shiftIndex: number;
  careerBefore: CareerState;
  /** caseId → the call; anything absent uses `correctDisposition`. */
  calls?: Record<string, Disposition>;
  /** caseId → the sources pulled; anything absent uses `keySourceIds`. */
  queries?: Record<string, string[]>;
  /** Flat per-case time, as `?demo=complete` uses; otherwise the pulled sources' cost. */
  flatTime?: number;
}

const RUN_SPECS: RunSpec[] = [
  { name: "shift1-clean", shiftIndex: 0, careerBefore: INITIAL_CAREER },
  {
    // D13 — verbatim from SocConsole.tsx's `?demo=complete` block (pin #demo-complete).
    name: "shift1-demo-complete",
    shiftIndex: 0,
    careerBefore: INITIAL_CAREER,
    calls: {
      "soc-ps-cradle": "escalate-ir-isolate",
      "soc-auth-reset": "escalate-tier2",
      "soc-ps-patch": "close-benign",
      "soc-dns-beacon": "escalate-ir-isolate",
      "soc-auth-bruteforce": "escalate-ir-isolate",
      "soc-dns-cdn": "close-false-positive",
      "soc-auth-pentest": "close-benign",
    },
    queries: { "soc-dns-cdn": [] },
    flatTime: 18,
  },
  {
    name: "shift1-breached",
    shiftIndex: 0,
    careerBefore: INITIAL_CAREER,
    calls: { "soc-ps-cradle": "close-false-positive", "soc-dns-beacon": "close-benign" },
  },
  {
    name: "shift2-clean",
    shiftIndex: 1,
    careerBefore: { cash: 300, standing: 40, shiftsCleaned: 1, redRunsDone: 0, gear: [] },
  },
  {
    name: "shift3-rough",
    shiftIndex: 2,
    careerBefore: { cash: 600, standing: 80, shiftsCleaned: 2, redRunsDone: 0, gear: ["intel-feed"] },
    calls: { "soc-lockout-stale": "escalate-tier2" },
  },
  {
    name: "shift4-clean",
    shiftIndex: 3,
    careerBefore: { cash: 900, standing: 120, shiftsCleaned: 3, redRunsDone: 0, gear: ["intel-feed"] },
  },
  {
    name: "shift5-rough",
    shiftIndex: 4,
    careerBefore: { cash: 1200, standing: 160, shiftsCleaned: 4, redRunsDone: 0, gear: ["intel-feed"] },
    calls: { "soc-insider-departing": "escalate-ir-isolate" },
    queries: { "soc-insider-baseline": [] },
  },
];

function buildRun(spec: RunSpec, shifts: ExportedShift[]): ShiftRun {
  const def = SHIFTS[spec.shiftIndex];
  let state = assembleShift(def.id, def.caseIds);
  const steps: ShiftRunStep[] = [];

  for (const id of def.caseIds) {
    const c = SOC_CASES_BY_ID[id];
    const chosen = spec.calls?.[id] ?? c.correctDisposition;
    const queried = spec.queries?.[id] ?? [...c.keySourceIds];
    const timeSpent = spec.flatTime ?? timeFor(c, queried);
    state = applyCall(state, c, chosen, queried, timeSpent);
    steps.push({ caseId: id, chosen, queriedSourceIds: queried, timeSpent, after: snapshotOf(state) });
  }

  const score = scoreShift(state, SOC_CASES_BY_ID);
  const before = spec.careerBefore;
  const wasUnlocked = new Set(unlockedIds(before, shifts));
  const reward = awardForShift(before, score);
  const unlocked = shifts
    .filter((s) => !wasUnlocked.has(s.id))
    .filter((s) => isUnlocked(reward.state, { unlockStanding: s.unlockStanding, requiresRedRun: s.requiresRedRun }))
    .map((s) => ({ id: s.id, label: s.label }));

  const ev: HandlerEvent = {
    type: score.grade === "clean" ? "shift-clean" : score.grade === "rough" ? "shift-rough" : "shift-breached",
    rankUp: reward.rankUp,
    unlocked,
  };

  return {
    name: spec.name,
    shiftId: def.id,
    caseIds: [...def.caseIds],
    careerBefore: careerJSON(before),
    steps,
    score: scoreJSON(state, SOC_CASES_BY_ID),
    reward: {
      state: careerJSON(reward.state),
      cashGain: reward.cashGain,
      standingGain: reward.standingGain,
      rankUp: rankJSON(reward.rankUp),
    },
    unlockedBefore: [...wasUnlocked],
    unlockedAfter: unlockedIds(reward.state, shifts),
    event: eventJSON(ev),
    inbox: messagesBlueOnly(reward.state, ev),
    inboxAll: messagesAll(reward.state, ev),
  };
}

/** D13 — the `?demo=complete` run is pinned to values run against the live engine. */
function assertDemoRun(run: ShiftRun): void {
  const expected: Partial<ShiftScoreJSON> = {
    total: 7,
    verdictCorrect: 6,
    dispositionCorrect: 6,
    missedDetections: 0,
    falseEscalations: 1,
    accuracy: 0.8571428571428571,
    blindCalls: 1,
    thoroughCalls: 6,
    investigationRate: 0.875,
    grade: "rough",
    breachRisk: 0,
    noise: 12,
  };
  for (const [k, v] of Object.entries(expected)) {
    const actual = (run.score as unknown as Record<string, unknown>)[k];
    if (actual !== v) {
      throw new Error(`D13 golden run drift: score.${k} is ${JSON.stringify(actual)}, expected ${JSON.stringify(v)}`);
    }
  }
  if (run.reward.cashGain !== 300 || run.reward.standingGain !== 15 || run.reward.rankUp !== null) {
    throw new Error(
      `D13 golden run drift: reward is ${JSON.stringify(run.reward)}, expected +300¢ / +15⬢ / no rank-up`
    );
  }
  const s = run.reward.state;
  if (s.cash !== 300 || s.standing !== 15 || s.shiftsCleaned !== 0) {
    throw new Error(`D13 golden run drift: career after is ${JSON.stringify(s)}`);
  }
  const ids = run.inbox.map((m) => m.id).join(",");
  if (ids !== "ev-rough,tip-kit") {
    throw new Error(`D13 golden run drift: inbox is [${ids}], expected [ev-rough, tip-kit]`);
  }
}

function buildShiftRuns(contentHash: string, shifts: ExportedShift[]): ShiftRunFile {
  const runs = RUN_SPECS.map((s) => buildRun(s, shifts));
  const demo = runs.find((r) => r.name === "shift1-demo-complete");
  if (!demo) throw new Error("the D13 golden run is missing from shift-runs.json");
  assertDemoRun(demo);
  return { schemaVersion: CONTENT_SCHEMA_VERSION, contentHash, runs };
}

// ── trace.json ───────────────────────────────────────────────────────────────

function buildTrace(contentHash: string): TraceFile {
  const status = [];
  for (let level = -5; level <= 105; level++) status.push({ level, status: getTraceStatus(level) });
  const clamp = [-5, -1, 0, 50, 100, 101, 150].map((level) => ({ level, value: clampLevel(level) }));
  return { schemaVersion: CONTENT_SCHEMA_VERSION, contentHash, status, clamp };
}

// ── career.json ──────────────────────────────────────────────────────────────

function score(grade: ShiftScore["grade"], verdictCorrect: number, total: number): ShiftScoreJSON {
  const accuracy = total > 0 ? verdictCorrect / total : 0;
  return {
    total,
    verdictCorrect,
    dispositionCorrect: verdictCorrect,
    missedDetections: grade === "breached" ? 2 : 0,
    falseEscalations: total - verdictCorrect,
    accuracy,
    accuracyNumerator: verdictCorrect,
    accuracyDenominator: total,
    blindCalls: grade === "clean" ? 0 : 1,
    thoroughCalls: verdictCorrect,
    investigationRate: 1,
    investigationRateNumerator: total,
    investigationRateDenominator: total,
    grade,
    breachRisk: grade === "breached" ? 80 : 0,
    noise: 0,
  };
}

const AWARD_LADDER: { name: string; s: ShiftScoreJSON }[] = [
  { name: "clean-7", s: score("clean", 7, 7) },
  { name: "clean-8", s: score("clean", 8, 8) },
  { name: "clean-3", s: score("clean", 3, 3) },
  { name: "rough-2of3", s: score("rough", 2, 3) },
  { name: "clean-3-again", s: score("clean", 3, 3) },
  { name: "breached-1of3", s: score("breached", 1, 3) },
  { name: "rough-5of8", s: score("rough", 5, 8) },
  { name: "rough-4of7", s: score("rough", 4, 7) },
  { name: "clean-5", s: score("clean", 5, 5) },
  { name: "rough-3of5", s: score("rough", 3, 5) },
  { name: "breached-2of5", s: score("breached", 2, 5) },
  { name: "clean-7-again", s: score("clean", 7, 7) },
];

function buildCareer(contentHash: string, shifts: ExportedShift[]): CareerFile {
  let state: CareerState = INITIAL_CAREER;
  const awards = AWARD_LADDER.map(({ name, s }) => {
    const before = state;
    const reward = awardForShift(before, s as unknown as ShiftScore);
    state = reward.state;
    return {
      name,
      score: s,
      before: careerJSON(before),
      reward: {
        state: careerJSON(reward.state),
        cashGain: reward.cashGain,
        standingGain: reward.standingGain,
        rankUp: rankJSON(reward.rankUp),
      },
      rank: rankJSON(rankFor(state.standing))!,
      nextRank: rankJSON(nextRank(state.standing)),
      unlockedIds: unlockedIds(state, shifts),
    };
  });

  const base: CareerState = { cash: 100, standing: 20, shiftsCleaned: 1, redRunsDone: 0, gear: [] };
  const redRuns = [
    { name: "default-cut", before: careerJSON(base), cut: null, after: careerJSON(awardRedRun(base)) },
    {
      name: "explicit-cut",
      before: careerJSON(base),
      cut: RED_RUN_CUT + 100,
      after: careerJSON(awardRedRun(base, RED_RUN_CUT + 100)),
    },
  ];

  const feed = KIT[0];
  const afford: CareerState = { cash: feed.cost + 50, standing: 40, shiftsCleaned: 1, redRunsDone: 0, gear: [] };
  const unafford: CareerState = { cash: feed.cost - 1, standing: 40, shiftsCleaned: 1, redRunsDone: 0, gear: [] };
  const owned: CareerState = { cash: feed.cost * 2, standing: 40, shiftsCleaned: 1, redRunsDone: 0, gear: [feed.id] };
  const buys = [
    { name: "afford", before: careerJSON(afford), itemId: feed.id, after: careerJSON(buyKit(afford, feed)) },
    { name: "unafford", before: careerJSON(unafford), itemId: feed.id, after: careerJSON(buyKit(unafford, feed)) },
    { name: "already-owned", before: careerJSON(owned), itemId: feed.id, after: careerJSON(buyKit(owned, feed)) },
  ];

  return { schemaVersion: CONTENT_SCHEMA_VERSION, contentHash, awards, redRuns, buys };
}

// ── handler.json — 14 scenarios (S3) ─────────────────────────────────────────

const HANDOFF_LABEL = "Shift 4 · the other chair (a red team's runs)";
const LOCKOUT_LABEL = "Shift 3 · the lockout queue (mostly not a threat)";

const career = (
  cash: number,
  standing: number,
  shiftsCleaned: number,
  redRunsDone: number,
  gear: string[] = []
): CareerState => ({ cash, standing, shiftsCleaned, redRunsDone, gear });

const HANDLER_SCENARIOS: { name: string; c: CareerState; ev: HandlerEvent }[] = [
  { name: "welcome-fresh", c: INITIAL_CAREER, ev: {} },
  { name: "shift-clean", c: career(100, 40, 1, 1), ev: { type: "shift-clean" } },
  { name: "shift-rough", c: career(100, 55, 1, 1), ev: { type: "shift-rough" } },
  { name: "shift-breached", c: career(100, 45, 1, 1), ev: { type: "shift-breached" } },
  { name: "rankup-trainee", c: career(0, 0, 0, 1), ev: { rankUp: RANKS[0] } },
  { name: "rankup-t1", c: career(100, 40, 1, 1), ev: { rankUp: RANKS[1] } },
  { name: "rankup-t1-senior", c: career(100, 150, 3, 0), ev: { rankUp: RANKS[2] } },
  { name: "rankup-t2-clean", c: career(100, 210, 5, 1), ev: { type: "shift-clean", rankUp: RANKS[3] } },
  {
    name: "unlock-queues",
    c: career(100, 120, 3, 1),
    ev: {
      unlocked: [
        { id: "lockout-shift", label: LOCKOUT_LABEL },
        { id: "handoff-shift", label: HANDOFF_LABEL },
      ],
    },
  },
  { name: "tip-kit", c: career(350, 40, 1, 1), ev: {} },
  { name: "tip-redrun", c: career(100, 120, 1, 0), ev: {} },
  { name: "standing-90-nudge", c: career(0, 90, 1, 0), ev: {} },
  {
    // 5 messages → the cap keeps 4; the blue-only filter then drops tip-redrun, so the
    // iOS inbox is SHORTER than the cap. That asymmetry is the point of this row.
    name: "cap-four",
    c: career(400, 120, 2, 0),
    ev: { type: "shift-clean", rankUp: RANKS[2], unlocked: [{ id: "handoff-shift", label: HANDOFF_LABEL }] },
  },
  { name: "fresh-rankup", c: INITIAL_CAREER, ev: { rankUp: RANKS[1] } },
];

function buildHandler(contentHash: string): HandlerFile {
  const scenarios: HandlerScenario[] = HANDLER_SCENARIOS.map(({ name, c, ev }) => ({
    name,
    career: careerJSON(c),
    event: eventJSON(ev),
    messagesAll: messagesAll(c, ev),
    messagesBlueOnly: messagesBlueOnly(c, ev),
  }));
  return { schemaVersion: CONTENT_SCHEMA_VERSION, contentHash, scenarios };
}

// ── scoring.json — the edge shifts the corpus runs never reach (S6) ──────────

const NO_KEY_CASES: SocCase[] = (
  [
    ["syn-nokeys-fp", "false-positive", "close-false-positive"],
    ["syn-nokeys-btp", "benign-true-positive", "close-benign"],
    ["syn-nokeys-tp", "true-positive", "escalate-tier2"],
  ] as const
).map(([id, truth, correctDisposition]) => ({
  id,
  archetype: "impossible-travel" as const,
  alertTitle: "Sign-in from an unfamiliar network",
  detectionRule: "Entra ID Protection · anomalous sign-in",
  toolSeverity: "Low" as const,
  trigger: "A sign-in for this account arrived from a network the directory has not seen before.",
  asset: "account fixture-user (Fixtures)",
  sources: [src("signin-logs"), src("named-locations")],
  // The point of these three: no key sources at all, so keyTotalSum is 0.
  keySourceIds: [],
  evidence: [
    {
      id: `${id}-signin`,
      sourceId: "signin-logs",
      label: "One sign-in, one device",
      detail: "A single interactive sign-in from the account's usual registered device.",
      weight: "neutral" as const,
    },
  ],
  truth,
  correctDisposition,
  acceptableDispositions: [],
  why: "A fixture case with no key sources, so investigation coverage divides by zero and the engine must report a full rate rather than a NaN.",
  learn: {
    concept: "Fixture-only case — it exists to pin the zero-key-source path through scoreShift.",
    pointer: "Fixture-only case.",
  },
}));

const SCORING_CASES: Record<string, SocCase> = Object.fromEntries(NO_KEY_CASES.map((c) => [c.id, c]));
const ALL_SCORING_CASES: Record<string, SocCase> = { ...SOC_CASES_BY_ID, ...SCORING_CASES };

const CASE = (id: string): SocCase => {
  const c = ALL_SCORING_CASES[id];
  if (!c) throw new Error(`scoring fixture references an unknown case: ${id}`);
  return c;
};

interface Call {
  id: string;
  chosen?: Disposition;
  queried?: string[];
}

/** Build a state by folding real calls, then optionally overriding the edge meters. */
function buildState(
  shiftId: string,
  calls: Call[],
  meters?: Partial<Pick<ShiftState, "breachRisk" | "noise" | "timeUsed">>
): ShiftState {
  let s = assembleShift(
    shiftId,
    calls.map((c) => c.id)
  );
  for (const call of calls) {
    const c = CASE(call.id);
    const chosen = call.chosen ?? c.correctDisposition;
    const queried = call.queried ?? [...c.keySourceIds];
    s = applyCall(s, c, chosen, queried, timeFor(c, queried));
  }
  return meters ? { ...s, ...meters } : s;
}

/** A case with ≥2 key sources, pulled down to exactly one → `partial`. */
function partialQuery(id: string): string[] {
  const c = CASE(id);
  if (c.keySourceIds.length < 2) throw new Error(`${id} cannot produce a partial investigation`);
  return c.keySourceIds.slice(0, 1);
}

function scoringRow(name: string, s: ShiftState): ScoringRow {
  return {
    name,
    shift: stateJSON(s),
    score: scoreJSON(s, ALL_SCORING_CASES),
    overallStatus: overallShiftStatus(s),
    investigations: orderedResults(s)
      .filter((r) => ALL_SCORING_CASES[r.caseId] !== undefined)
      .map((r) => ({ caseId: r.caseId, quality: investigationOf(r, ALL_SCORING_CASES[r.caseId]) })),
  };
}

function buildScoring(contentHash: string): ScoringFile {
  const rows: ScoringRow[] = [];

  rows.push(scoringRow("empty-shift", assembleShift("synthetic-empty", [])));

  rows.push(
    scoringRow(
      "all-blind",
      buildState("synthetic-all-blind", [
        { id: "soc-ps-cradle", queried: [] },
        { id: "soc-auth-reset", queried: [] },
        { id: "soc-ps-patch", queried: [] },
      ])
    )
  );

  rows.push(
    scoringRow(
      "two-missed",
      buildState("synthetic-two-missed", [
        { id: "soc-ps-cradle", chosen: "close-false-positive" },
        { id: "soc-dns-beacon", chosen: "close-benign" },
        { id: "soc-ps-patch" },
      ])
    )
  );

  rows.push(
    scoringRow(
      "noise-hunt-perfect",
      buildState(
        "synthetic-noise-hunt",
        [
          { id: "soc-ps-cradle" },
          { id: "soc-ps-patch", queried: partialQuery("soc-ps-patch") },
          { id: "soc-auth-reset" },
        ],
        { noise: 50 }
      )
    )
  );

  rows.push(
    scoringRow(
      "breach-exactly-80",
      buildState(
        "synthetic-breach-80",
        [{ id: "soc-ps-cradle" }, { id: "soc-auth-reset" }, { id: "soc-ps-patch" }],
        { breachRisk: 80 }
      )
    )
  );

  rows.push(
    scoringRow(
      "no-key-sources",
      buildState("synthetic-no-keys", [
        { id: "syn-nokeys-fp" },
        { id: "syn-nokeys-btp" },
        { id: "syn-nokeys-tp" },
      ])
    )
  );

  // A `results` entry whose caseId is not in the map — Swift must SKIP it, not crash.
  // It still counts toward `total`, which is what dilutes accuracy here.
  const known = buildState("synthetic-unknown-case", [{ id: "soc-ps-cradle" }, { id: "soc-auth-reset" }]);
  const ghost: CaseResult = {
    caseId: "soc-case-that-no-longer-exists",
    chosen: "close-benign",
    verdictCorrect: true,
    dispositionCorrect: true,
    queriedSourceIds: ["change-tickets"],
    keySourcesPulled: 1,
    timeSpent: 6,
  };
  rows.push(
    scoringRow("unknown-case-id", {
      ...known,
      index: known.index + 1,
      results: { ...known.results, [ghost.caseId]: ghost },
      timeUsed: known.timeUsed + ghost.timeSpent,
    })
  );

  rows.push(
    scoringRow(
      "clean-accuracy-exactly-080",
      buildState("synthetic-clean-080", [
        { id: "soc-ps-cradle" },
        { id: "soc-ps-patch" },
        { id: "soc-dns-beacon" },
        { id: "soc-auth-pentest" },
        { id: "soc-auth-reset", chosen: "close-benign" },
      ])
    )
  );

  rows.push(
    scoringRow(
      "rough-accuracy-one-step-below",
      buildState("synthetic-rough-060", [
        { id: "soc-ps-cradle" },
        { id: "soc-ps-patch" },
        { id: "soc-dns-beacon" },
        { id: "soc-auth-reset", chosen: "close-benign" },
        { id: "soc-dns-cdn", chosen: "close-benign" },
      ])
    )
  );

  rows.push(
    scoringRow(
      "rough-one-blind",
      buildState("synthetic-one-blind", [
        { id: "soc-ps-cradle" },
        { id: "soc-ps-patch" },
        { id: "soc-dns-beacon" },
        { id: "soc-auth-reset", queried: [] },
      ])
    )
  );

  rows.push(
    scoringRow(
      "rough-noise-lockdown",
      buildState(
        "synthetic-noise-lockdown",
        [{ id: "soc-ps-cradle" }, { id: "soc-auth-reset" }, { id: "soc-ps-patch" }],
        { noise: 80 }
      )
    )
  );

  rows.push(
    scoringRow(
      "rough-one-missed-breach-30",
      buildState("synthetic-one-missed", [
        { id: "soc-ps-cradle", chosen: "close-false-positive" },
        { id: "soc-auth-reset" },
        { id: "soc-ps-patch" },
      ])
    )
  );

  // Four missed TPs → 4 × 30 = 120, clamped to 100 by clampLevel.
  rows.push(
    scoringRow(
      "overflow-four-missed",
      buildState("synthetic-overflow", [
        { id: "soc-ps-cradle", chosen: "close-false-positive" },
        { id: "soc-dns-beacon", chosen: "close-false-positive" },
        { id: "soc-auth-bruteforce", chosen: "close-false-positive" },
        { id: "soc-phish-harvest", chosen: "close-false-positive" },
      ])
    )
  );

  // applyCall edges.
  const twoCalls = buildState("synthetic-replace", [{ id: "soc-ps-cradle" }, { id: "soc-auth-reset" }]);
  const cradle = CASE("soc-ps-cradle");
  const replaced = applyCall(twoCalls, cradle, "close-false-positive", [], 0);

  const fresh = assembleShift("synthetic-duplicate", ["soc-ps-cradle"]);
  const dupKey = cradle.keySourceIds[0];
  const dupQuery = [dupKey, dupKey];
  const duplicated = applyCall(fresh, cradle, cradle.correctDisposition, dupQuery, timeFor(cradle, dupQuery));

  const applyRows: ApplyRow[] = [
    {
      // A second call on a caseId already in `results` REPLACES it and keeps its
      // position — which is why `results` is an ordered array in Swift (DV-1).
      name: "replace-in-place",
      before: stateJSON(twoCalls),
      caseId: cradle.id,
      chosen: "close-false-positive",
      queriedSourceIds: [],
      timeSpent: 0,
      after: stateJSON(replaced),
    },
    {
      // A duplicated id in `queriedSourceIds` is counted TWICE. Documented invariant:
      // `buildCaseResult` filters the queried list, it does not de-duplicate it.
      name: "duplicate-queried-id",
      before: stateJSON(fresh),
      caseId: cradle.id,
      chosen: cradle.correctDisposition,
      queriedSourceIds: dupQuery,
      timeSpent: timeFor(cradle, dupQuery),
      after: stateJSON(duplicated),
    },
  ];

  const check = buildCaseResult(cradle, cradle.correctDisposition, dupQuery, 0);
  if (check.keySourcesPulled !== 2) {
    throw new Error(
      `the duplicate-queried-id invariant changed: keySourcesPulled is ${check.keySourcesPulled}, expected 2`
    );
  }

  return {
    schemaVersion: CONTENT_SCHEMA_VERSION,
    contentHash,
    cases: NO_KEY_CASES.map(exportCase),
    rows,
    applyRows,
  };
}

// ── the whole fixture set ────────────────────────────────────────────────────

export interface Fixtures {
  "grades.json": GradeFile;
  "grades-synthetic.json": SyntheticGradeFile;
  "shift-runs.json": ShiftRunFile;
  "trace.json": TraceFile;
  "career.json": CareerFile;
  "handler.json": HandlerFile;
  "scoring.json": ScoringFile;
}

export function buildFixtures(bundle: ExportedBundle, contentHash: string): Fixtures {
  return {
    "grades.json": buildGrades(contentHash),
    "grades-synthetic.json": buildSyntheticGrades(contentHash),
    "shift-runs.json": buildShiftRuns(contentHash, bundle.shifts),
    "trace.json": buildTrace(contentHash),
    "career.json": buildCareer(contentHash, bundle.shifts),
    "handler.json": buildHandler(contentHash),
    "scoring.json": buildScoring(contentHash),
  };
}
