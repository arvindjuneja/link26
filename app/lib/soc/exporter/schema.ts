// The exported content contract — FROZEN. Every other exporter module and every
// Swift Codable mirror (C2) is written against this file and nothing else.
//
// SPEC.md §2.2, amended by SPEC-ADDENDUM.md §2 (S1 chrome, S2 template sender,
// S4 coachSteps[].advance, S5 severityMeta/handlerToneMeta, S8 tuning typed
// `number`, S9 daily shiftTemplate).
//
// Rules this shape exists to make true:
//  - synthesised Swift `Codable` with NO custom `CodingKeys` (§3.4): field names are
//    1:1, `learn` is flat, `acceptableDispositions` is never absent, `handoff` is
//    `null` and never omitted;
//  - every number the engine branches on lives in `tuning` (D7);
//  - prose is resolved through a keyed `OutcomeKey`, never compared as a string (D2).

export const CONTENT_SCHEMA_VERSION = 1;

/**
 * Colour-run text. Rendered as AttributedString in SwiftUI. (D5)
 *
 * R2 — `orange` is the HUNT hue of the status ramp, added because the web's HIGH
 * severity chip is orange and amber was the wrong nearest neighbour: amber already
 * means "escalate to Tier-2" on the call sheet, so a HIGH chip in amber read as a
 * recommendation. Swift's `Tone` is a lenient raw value, so no model change (R2).
 */
export type Tone =
  | "cyan"
  | "emerald"
  | "rose"
  | "amber"
  | "orange"
  | "fuchsia"
  | "strong"
  | "em"
  | "muted";
export interface RichSegment {
  text: string;
  tone?: Tone;
}

/** The 11 debrief outcome strings of `engine.ts`, as keys. Closed in Swift (X1). */
export type OutcomeKey =
  | "tp.missed"
  | "tp.escalated-correct"
  | "tp.over-contained"
  | "tp.under-contained"
  | "fp.closed-fp"
  | "fp.closed-as-benign"
  | "fp.escalated"
  | "btp.closed-benign"
  | "btp.closed-as-fp"
  | "btp.escalated-t2"
  | "btp.isolated";

export const OUTCOME_KEYS: OutcomeKey[] = [
  "tp.missed",
  "tp.escalated-correct",
  "tp.over-contained",
  "tp.under-contained",
  "fp.closed-fp",
  "fp.closed-as-benign",
  "fp.escalated",
  "btp.closed-benign",
  "btp.closed-as-fp",
  "btp.escalated-t2",
  "btp.isolated",
];

// ── content.json ─────────────────────────────────────────────────────────────

export interface ExportedSource {
  id: string;
  label: string;
  question: string;
  cost: number;
}

export interface ExportedEvidence {
  id: string;
  sourceId: string;
  label: string;
  detail: string;
  weight: "decisive" | "supporting" | "neutral" | "noise";
}

export interface ExportedLearn {
  concept: string;
  mitreId: string | null;
  mitreName: string | null;
  pointer: string | null;
}

export interface ExportedCase {
  id: string;
  archetype: string; // lenient in Swift (D10)
  alertTitle: string;
  detectionRule: string;
  toolSeverity: string; // lenient in Swift (D10)
  trigger: string;
  asset: string;
  sourceIds: string[]; // → the top-level catalogue; 135 inline objects → 26 (D3)
  keySourceIds: string[];
  evidence: ExportedEvidence[];
  truth: "true-positive" | "false-positive" | "benign-true-positive";
  correctDisposition: string;
  acceptableDispositions: string[]; // [] never undefined → non-optional in Swift
  why: string;
  learn: ExportedLearn;
  handoff: { fromRun: string; operator: string } | null; // null, never omitted
}

export interface ExportedShift {
  id: string;
  label: string;
  caseIds: string[];
  unlockStanding: number;
  requiresRedRun: boolean;
  note: string | null;
  kind: "campaign" | "daily";
}

export interface ExportedRank {
  id: string;
  label: string;
  min: number;
}

export interface ExportedKitItem {
  id: string;
  label: string;
  cost: number;
  blurb: string;
}

/**
 * The 31 tuning numbers (S8, amended by R6): trace 5 · bpm 4 · timeBudgetDefault 1 ·
 * grade 8 · shift 2 · career 6 · heartbeat 3 · handler 2. Typed `number`, NOT
 * literals, so a designer retune is a zero-Swift-change operation (D7).
 */
export interface ExportedTuning {
  trace: { min: number; max: number; alert: number; hunt: number; lockdown: number };
  bpm: { CALM: number; ALERT: number; HUNT: number; LOCKDOWN: number };
  timeBudgetDefault: number;
  grade: {
    tpMissedBreach: number;
    tpUnderContainBreach: number;
    tpOverContainNoise: number;
    fpEscalateT2Noise: number;
    fpEscalateIsolateNoise: number;
    btpClosedAsFpNoise: number;
    btpEscalateT2Noise: number;
    btpIsolateNoise: number;
  };
  shift: { cleanAccuracy: number; breachedMissedDetections: number };
  career: {
    cashPerCorrect: number;
    cleanBonus: number;
    standingClean: number;
    standingRough: number;
    standingBreached: number;
    redRunCut: number;
  };
  heartbeat: { minPeriodMs: number; autoSuspendMs: number; dubOffsetMs: number };
  /**
   * R6 — the two numbers `career/handler.ts` owns: the inbox wall and the standing
   * at which the red seat starts pulling at you. They are not economy values, which
   * is why they sat as literals in the handler until now; they are tuning all the
   * same, and `Inbox.swift` reads both from here rather than spelling them twice.
   */
  handler: { inboxCapacity: number; redRunNudgeStanding: number };
}

export interface ExportedBundle {
  schemaVersion: number;
  contentHash: string; // "sha256:<hex>" over the canonical JSON of content+copy+daily
  dispositions: string[]; // DISPOSITIONS order — the button order
  sources: ExportedSource[]; // 26 (D3)
  cases: ExportedCase[]; // 24, incl. the 3 handoff cases
  shifts: ExportedShift[]; // 5, blue-only ladder applied (D4)
  ranks: ExportedRank[]; // 4
  kit: ExportedKitItem[]; // 1
  tuning: ExportedTuning;
}

// ── copy.json ────────────────────────────────────────────────────────────────

export type CoachAnchor = "sources" | "evidence" | "call";
/** How a coach step ends (S4). `terminal` = the last step; the first real call closes it. */
export type CoachAdvance = "on-first-source-pulled" | "button" | "terminal";

export interface ExportedCoachStep {
  anchor: CoachAnchor;
  title: string;
  body: string;
  button: string | null;
  advance: CoachAdvance;
}

export type MeterKey = "breach" | "noise" | "time";
export interface ExportedMeter {
  label: string;
  fear: string;
}

/** Severity → chip label + tone (S5). `fallback` is the tone for an unknown severity. */
export interface ExportedToneMeta {
  label: string;
  tone: Tone;
}

/** A handler message body, keyed by message id (S2). Placeholders: {gap} {rank} {cash} {item} {queue}. */
export interface ExportedHandlerTemplate {
  sender: "vale" | "mercer";
  subject: string;
  body: string;
  tone: string;
}

export interface ExportedCopy {
  schemaVersion: number;
  contentHash: string;
  /** Screen chrome — labels, CTAs, eyebrows. Every letter the app draws lives here (S1). */
  chrome: Record<string, string>;
  verdictLabels: Record<string, string>;
  dispositionMeta: Record<string, { label: string; sub: string; tone: Tone }>;
  outcomes: Record<OutcomeKey, string>; // 11 (D12)
  debriefHeadlines: { good: string; verdictOnly: string; wrong: string };
  gradeMeta: Record<"clean" | "rough" | "breached", { label: string; line: string; tone: Tone }>;
  /** SEVERITY_TONE, plus the tone an unknown severity renders with (S5). */
  severityMeta: { entries: Record<string, ExportedToneMeta>; fallback: Tone };
  /** MSG_TONE, plus the tone an unknown handler tone renders with (S5). */
  handlerToneMeta: { entries: Record<string, ExportedToneMeta>; fallback: Tone };
  intro: {
    eyebrow: string;
    title: string; // "{n} alerts on the board."
    taxonomy: RichSegment[];
    severity: RichSegment[];
    meters: { key: MeterKey; label: string; fear: string }[];
    handoff: { blueOnly: RichSegment[]; redSeat: RichSegment[] };
    cta: string;
    disclaimer: string;
  };
  coachSteps: ExportedCoachStep[];
  ladder: { eyebrow: string; body: RichSegment[]; note: string };
  summary: { eyebrow: string; investigationLine: string; blindLine: string };
  firstRun: { title: string; body: string; cta: string };
  about: { fiction: string; privacy: string; promise: string; credits: string };
  meters: Record<MeterKey, ExportedMeter>;
  handler: {
    senders: Record<"vale" | "mercer", { from: string; role: string }>;
    templates: Record<string, ExportedHandlerTemplate>;
  };
}

// ── daily.json ───────────────────────────────────────────────────────────────

/**
 * The daily shift's ShiftDef, minus the board (S9). `{date}` interpolates the
 * player-facing date in `label`; `id` is `idPrefix + <ISO date>`.
 *
 * `unlockStanding`, `requiresRedRun` and `kind` are carried here (beyond S9's three
 * fields) because `ContentPack.dailyShift(on:)` builds a whole `ExportedShift` and
 * D7 forbids a numeric literal in Swift. R3 adds `requiresRedRun` so that build is a
 * pure field copy rather than a hardcoded `false` sitting next to the copied fields.
 */
export interface ExportedDailyTemplate {
  idPrefix: string;
  label: string;
  note: string | null;
  unlockStanding: number;
  /** Always `false` — this build is blue-only (B1), daily-kind shifts included. */
  requiresRedRun: boolean;
  kind: "daily";
}

export interface ExportedDailyDay {
  date: string; // "2026-09-05"
  caseIds: string[]; // 5
}

export interface ExportedDaily {
  schemaVersion: number;
  contentHash: string;
  horizonStart: string; // "2026-09-05"
  shiftTemplate: ExportedDailyTemplate;
  days: ExportedDailyDay[]; // 730 (D6)
}

// ── fixtures ─────────────────────────────────────────────────────────────────

export interface GradeRow {
  caseId: string;
  disposition: string;
  verdictCorrect: boolean;
  dispositionCorrect: boolean;
  exact: boolean;
  breachDelta: number;
  noiseDelta: number;
  outcomeKey: OutcomeKey;
  outcome: string;
}

export interface GradeFile {
  schemaVersion: number;
  contentHash: string;
  rows: GradeRow[]; // 96 = 24 cases × 4 dispositions
}

export interface SyntheticGradeFile {
  schemaVersion: number;
  contentHash: string;
  cases: ExportedCase[]; // 3 constructed cases (D11)
  rows: GradeRow[]; // 12 = 3 × 4
}

export interface CaseResultJSON {
  caseId: string;
  chosen: string;
  verdictCorrect: boolean;
  dispositionCorrect: boolean;
  queriedSourceIds: string[];
  keySourcesPulled: number;
  timeSpent: number;
}

/** The `after` of one scripted step — the meters and the ORDERED results (D8/DV-1). */
export interface ShiftStateSnapshot {
  index: number;
  breachRisk: number;
  noise: number;
  timeUsed: number;
  results: CaseResultJSON[];
  overallStatus: string;
}

/** A whole `ShiftState`, for fixtures that feed one in rather than build it up. */
export interface ShiftStateJSON {
  shiftId: string;
  caseIds: string[];
  index: number;
  timeBudget: number;
  breachRisk: number;
  noise: number;
  timeUsed: number;
  results: CaseResultJSON[];
}

export interface CareerJSON {
  cash: number;
  standing: number;
  shiftsCleaned: number;
  redRunsDone: number;
  gear: string[];
}

/** Rates carry numerator and denominator so a Swift failure localises to the counter. */
export interface ShiftScoreJSON {
  total: number;
  verdictCorrect: number;
  dispositionCorrect: number;
  missedDetections: number;
  falseEscalations: number;
  accuracy: number;
  accuracyNumerator: number;
  accuracyDenominator: number;
  blindCalls: number;
  thoroughCalls: number;
  investigationRate: number;
  investigationRateNumerator: number;
  investigationRateDenominator: number;
  grade: string;
  breachRisk: number;
  noise: number;
}

export interface ShiftRewardJSON {
  state: CareerJSON;
  cashGain: number;
  standingGain: number;
  rankUp: ExportedRank | null;
}

export interface HandlerEventJSON {
  type: string | null;
  rankUp: ExportedRank | null;
  unlocked: { id: string; label: string }[];
}

export interface HandlerMessageJSON {
  id: string;
  from: string;
  role: string;
  subject: string;
  body: string;
  tone: string;
}

export interface ShiftRunStep {
  caseId: string;
  chosen: string;
  queriedSourceIds: string[];
  timeSpent: number;
  after: ShiftStateSnapshot;
}

export interface ShiftRun {
  name: string;
  shiftId: string;
  caseIds: string[];
  careerBefore: CareerJSON;
  steps: ShiftRunStep[];
  score: ShiftScoreJSON;
  reward: ShiftRewardJSON;
  unlockedBefore: string[];
  unlockedAfter: string[];
  event: HandlerEventJSON;
  /** What the iOS hub shows — the blue-only inbox (R1). */
  inbox: HandlerMessageJSON[];
  /** The unfiltered web inbox, for the `.all` feature set (R1). */
  inboxAll: HandlerMessageJSON[];
}

export interface ShiftRunFile {
  schemaVersion: number;
  contentHash: string;
  runs: ShiftRun[]; // 7
}

export interface TraceStatusRow {
  level: number;
  status: string;
}
export interface TraceClampRow {
  level: number;
  value: number;
}
export interface TraceFile {
  schemaVersion: number;
  contentHash: string;
  status: TraceStatusRow[]; // -5…105 → 111 rows
  clamp: TraceClampRow[];
}

export interface CareerAwardRow {
  name: string;
  score: ShiftScoreJSON;
  before: CareerJSON;
  reward: ShiftRewardJSON;
  rank: ExportedRank;
  nextRank: ExportedRank | null;
  unlockedIds: string[];
}
export interface CareerRedRunRow {
  name: string;
  before: CareerJSON;
  cut: number | null;
  after: CareerJSON;
}
export interface CareerBuyRow {
  name: string;
  before: CareerJSON;
  itemId: string;
  after: CareerJSON;
}
export interface CareerFile {
  schemaVersion: number;
  contentHash: string;
  awards: CareerAwardRow[]; // 12
  redRuns: CareerRedRunRow[];
  buys: CareerBuyRow[]; // 3
}

export interface HandlerScenario {
  name: string;
  career: CareerJSON;
  event: HandlerEventJSON;
  /** `features: .all` — the raw `inboxFor(c, ev)`, Mercer and the nudge and all. */
  messagesAll: HandlerMessageJSON[];
  /**
   * `features: .iOS` (R1) — the same engine run against a career that has already
   * sat in the other chair, so `tip-redrun` is never emitted and the cap is free to
   * admit the message behind it, plus the two DESIGN §3.2 re-voicings.
   */
  messagesBlueOnly: HandlerMessageJSON[];
}
export interface HandlerFile {
  schemaVersion: number;
  contentHash: string;
  scenarios: HandlerScenario[]; // 14 (S3)
}

export interface ScoringRow {
  name: string;
  shift: ShiftStateJSON;
  score: ShiftScoreJSON;
  overallStatus: string;
  investigations: { caseId: string; quality: string }[];
}
export interface ApplyRow {
  name: string;
  before: ShiftStateJSON;
  caseId: string;
  chosen: string;
  queriedSourceIds: string[];
  timeSpent: number;
  after: ShiftStateJSON;
}
export interface ScoringFile {
  schemaVersion: number;
  contentHash: string;
  /** Cases referenced by rows that are NOT in the bundle (S6's `keySourceIds: []` set). */
  cases: ExportedCase[];
  rows: ScoringRow[]; // ≥12 (S6)
  applyRows: ApplyRow[];
}

// ── the whole export ─────────────────────────────────────────────────────────

/** The 10 generated files, keyed by their filename. */
export interface ExportedFiles {
  "content.json": ExportedBundle;
  "copy.json": ExportedCopy;
  "daily.json": ExportedDaily;
  "grades.json": GradeFile;
  "grades-synthetic.json": SyntheticGradeFile;
  "shift-runs.json": ShiftRunFile;
  "trace.json": TraceFile;
  "career.json": CareerFile;
  "handler.json": HandlerFile;
  "scoring.json": ScoringFile;
}

export const CONTENT_FILES = ["content.json", "copy.json", "daily.json"] as const;
export const FIXTURE_FILES = [
  "career.json",
  "grades-synthetic.json",
  "grades.json",
  "handler.json",
  "scoring.json",
  "shift-runs.json",
  "trace.json",
] as const;
