import Foundation

// The `fixtures` half of the frozen schema (SPEC.md §2.2 · `schema.ts`), mirrored
// 1:1 so the golden suites decode rather than hand-parse. The runtime types are
// reused wherever the exporter's `*JSON` alias is structurally identical:
//
//   CaseResultJSON     → CaseResult          ShiftScoreJSON  → ShiftScore
//   ShiftStateJSON     → ShiftState          ShiftRewardJSON → ShiftReward
//   CareerJSON         → CareerState         ExportedRank    → Rank
//   HandlerEventJSON   → HandlerEvent        HandlerMessageJSON → HandlerMessage
//   ExportedCase       → SocCase
//
// String-typed fields in the schema are decoded into their closed Swift enums
// (`disposition`, `grade`, `overallStatus`, `quality`, `outcomeKey`) so a fixture
// that grows an unknown value fails loudly instead of comparing equal to nothing.
//
// These types ship in the library, not the fixture data: `SentryFixtures` is a
// test-only target, so the ~230 KB of JSON never reaches the app (D23).

// ── grades.json · grades-synthetic.json ──────────────────────────────────────

/// One (case × disposition) pair, graded by the real TypeScript engine.
public struct GradeRow: Codable, Sendable, Hashable {
  public let caseId: String
  public let disposition: Disposition
  public let verdictCorrect: Bool
  public let dispositionCorrect: Bool
  public let exact: Bool
  public let breachDelta: Int
  public let noiseDelta: Int
  public let outcomeKey: OutcomeKey
  /// The prose the web engine produced. Swift compares it against
  /// `CopyPack.outcomeText(outcomeKey)`, never against a transcribed literal.
  public let outcome: String

  public init(
    caseId: String, disposition: Disposition, verdictCorrect: Bool, dispositionCorrect: Bool,
    exact: Bool, breachDelta: Int, noiseDelta: Int, outcomeKey: OutcomeKey, outcome: String
  ) {
    self.caseId = caseId
    self.disposition = disposition
    self.verdictCorrect = verdictCorrect
    self.dispositionCorrect = dispositionCorrect
    self.exact = exact
    self.breachDelta = breachDelta
    self.noiseDelta = noiseDelta
    self.outcomeKey = outcomeKey
    self.outcome = outcome
  }
}

/// `grades.json` — 96 rows = 24 cases × 4 dispositions.
public struct GradeFile: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  public let contentHash: String
  public let rows: [GradeRow]
}

/// `grades-synthetic.json` — 3 constructed cases × 4 dispositions = 12 rows,
/// which is what reaches the `tp.under-contained` arm the shipped corpus never
/// touches (D11). Its `cases` are NOT in the bundle.
public struct SyntheticGradeFile: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  public let contentHash: String
  public let cases: [SocCase]
  public let rows: [GradeRow]
}

// ── shift-runs.json ──────────────────────────────────────────────────────────

/// The `after` of one scripted step — the meters and the ORDERED results (D8/DV-1).
public struct ShiftStateSnapshot: Codable, Sendable, Hashable {
  public let index: Int
  public let breachRisk: Int
  public let noise: Int
  public let timeUsed: Int
  public let results: [CaseResult]
  public let overallStatus: TraceStatus
}

public struct ShiftRunStep: Codable, Sendable, Hashable {
  public let caseId: String
  public let chosen: Disposition
  public let queriedSourceIds: [String]
  public let timeSpent: Int
  public let after: ShiftStateSnapshot
}

/// One scripted run, asserted after **every** step and then field-by-field on the score.
public struct ShiftRun: Codable, Sendable, Hashable {
  public let name: String
  public let shiftId: String
  public let caseIds: [String]
  public let careerBefore: CareerState
  public let steps: [ShiftRunStep]
  public let score: ShiftScore
  public let reward: ShiftReward
  public let unlockedBefore: [String]
  public let unlockedAfter: [String]
  public let event: HandlerEvent
  /// What the iOS hub shows — the blue-only inbox (S3).
  public let inbox: [HandlerMessage]
  /// The unfiltered web inbox, for the `.all` feature set (S3).
  public let inboxAll: [HandlerMessage]
}

public struct ShiftRunFile: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  public let contentHash: String
  public let runs: [ShiftRun]
}

// ── trace.json ───────────────────────────────────────────────────────────────

public struct TraceStatusRow: Codable, Sendable, Hashable {
  public let level: Int
  public let status: TraceStatus
}

public struct TraceClampRow: Codable, Sendable, Hashable {
  public let level: Int
  public let value: Int
}

public struct TraceFile: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  public let contentHash: String
  /// −5…105 → 111 rows.
  public let status: [TraceStatusRow]
  public let clamp: [TraceClampRow]
}

// ── career.json ──────────────────────────────────────────────────────────────

public struct CareerAwardRow: Codable, Sendable, Hashable {
  public let name: String
  public let score: ShiftScore
  public let before: CareerState
  public let reward: ShiftReward
  public let rank: Rank
  public let nextRank: Rank?
  public let unlockedIds: [String]
}

public struct CareerRedRunRow: Codable, Sendable, Hashable {
  public let name: String
  public let before: CareerState
  public let cut: Int?
  public let after: CareerState
}

public struct CareerBuyRow: Codable, Sendable, Hashable {
  public let name: String
  public let before: CareerState
  public let itemId: String
  public let after: CareerState
}

public struct CareerFile: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  public let contentHash: String
  public let awards: [CareerAwardRow]
  public let redRuns: [CareerRedRunRow]
  public let buys: [CareerBuyRow]
}

// ── handler.json ─────────────────────────────────────────────────────────────

/// One `(CareerState, HandlerEvent)` triple rendered under both feature sets (S3).
public struct HandlerScenario: Codable, Sendable, Hashable {
  public let name: String
  public let career: CareerState
  public let event: HandlerEvent
  /// `features: .all` — the web inbox.
  public let messagesAll: [HandlerMessage]
  /// `features: .iOS` — `tip-redrun` filtered out, then the 4-message cap re-applied.
  public let messagesBlueOnly: [HandlerMessage]
}

public struct HandlerFile: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  public let contentHash: String
  public let scenarios: [HandlerScenario]
}

// ── scoring.json ─────────────────────────────────────────────────────────────

public struct InvestigationRow: Codable, Sendable, Hashable {
  public let caseId: String
  public let quality: InvestigationQuality
}

/// A hand-built edge shift the corpus runs never reach (S6).
public struct ScoringRow: Codable, Sendable, Hashable {
  public let name: String
  public let shift: ShiftState
  public let score: ShiftScore
  public let overallStatus: TraceStatus
  public let investigations: [InvestigationRow]
}

/// One `applyCall` transition, including the replace-in-place case.
public struct ApplyRow: Codable, Sendable, Hashable {
  public let name: String
  public let before: ShiftState
  public let caseId: String
  public let chosen: Disposition
  public let queriedSourceIds: [String]
  public let timeSpent: Int
  public let after: ShiftState
}

public struct ScoringFile: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  public let contentHash: String
  /// Cases referenced by rows that are NOT in the bundle (S6's `keySourceIds: []` set).
  public let cases: [SocCase]
  public let rows: [ScoringRow]
  public let applyRows: [ApplyRow]
}
