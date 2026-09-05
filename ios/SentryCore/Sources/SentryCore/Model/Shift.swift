import Foundation

/// The 11 debrief outcome strings of `engine.ts`, as keys. Closed (D10/D12): the
/// prose is resolved through `CopyPack.outcomeText(_:)`, never compared as a string,
/// so a wording change in the web tree can never desync the two engines — and a
/// twelfth branch fails to decode and names itself.
///
/// 11 keys cover 12 branch arms: `fp.escalated` covers both escalations because
/// they share one string. Deltas therefore come from `tuning`, never from the key.
public enum OutcomeKey: String, Codable, Sendable, Hashable, CaseIterable, CodingKeyRepresentable {
  case tpMissed           = "tp.missed"
  case tpEscalatedCorrect = "tp.escalated-correct"
  case tpOverContained    = "tp.over-contained"
  case tpUnderContained   = "tp.under-contained"
  case fpClosedFP         = "fp.closed-fp"
  case fpClosedAsBenign   = "fp.closed-as-benign"
  case fpEscalated        = "fp.escalated"
  case btpClosedBenign    = "btp.closed-benign"
  case btpClosedAsFP      = "btp.closed-as-fp"
  case btpEscalatedT2     = "btp.escalated-t2"
  case btpIsolated        = "btp.isolated"
}

/// How a shift reads at 16:00. Closed (D10).
public enum ShiftGrade: String, Codable, Sendable, Hashable, CaseIterable, CodingKeyRepresentable {
  case clean
  case rough
  case breached
}

/// One graded call, with the consequence it carries into the meters.
///
/// The prose headline is deliberately absent: `outcomeKey` is the copy key and
/// `CopyPack.outcomeText(_:)` resolves it (D2/D12).
public struct CallGrade: Codable, Sendable, Hashable {
  public let verdictCorrect: Bool
  /// Exact **or** acceptable.
  public let dispositionCorrect: Bool
  /// Exactly the ideal disposition.
  public let exact: Bool
  /// Added to `breachRisk`.
  public let breachDelta: Int
  /// Added to `noise`.
  public let noiseDelta: Int
  public let outcomeKey: OutcomeKey

  public init(
    verdictCorrect: Bool, dispositionCorrect: Bool, exact: Bool,
    breachDelta: Int, noiseDelta: Int, outcomeKey: OutcomeKey
  ) {
    self.verdictCorrect = verdictCorrect
    self.dispositionCorrect = dispositionCorrect
    self.exact = exact
    self.breachDelta = breachDelta
    self.noiseDelta = noiseDelta
    self.outcomeKey = outcomeKey
  }
}

/// One resolved alert. Decodes 1:1 from the fixtures' `CaseResultJSON`.
public struct CaseResult: Codable, Sendable, Hashable {
  public let caseId: String
  public let chosen: Disposition
  public let verdictCorrect: Bool
  public let dispositionCorrect: Bool
  public let queriedSourceIds: [String]
  /// Of the case's `keySourceIds`, how many were pulled. A duplicated id in
  /// `queriedSourceIds` counts twice — a documented invariant of the web engine (S6).
  public let keySourcesPulled: Int
  /// Shift-minutes.
  public let timeSpent: Int

  public init(
    caseId: String, chosen: Disposition, verdictCorrect: Bool, dispositionCorrect: Bool,
    queriedSourceIds: [String], keySourcesPulled: Int, timeSpent: Int
  ) {
    self.caseId = caseId
    self.chosen = chosen
    self.verdictCorrect = verdictCorrect
    self.dispositionCorrect = dispositionCorrect
    self.queriedSourceIds = queriedSourceIds
    self.keySourcesPulled = keySourcesPulled
    self.timeSpent = timeSpent
  }
}

/// The board in flight. Decodes 1:1 from the fixtures' `ShiftStateJSON`.
///
/// **DV-1:** `results` is an ordered array, not the TypeScript `Record`. TS iterates
/// `Object.values()` in insertion order; a Swift `Dictionary` has none, and the board
/// glyph strip, the read-only debrief and `session.json` all want order.
///
/// **DV-2:** the meters are `public internal(set)`, so meter arithmetic outside
/// `SentryCore` is a compile error rather than a convention (D8).
public struct ShiftState: Codable, Sendable, Hashable {
  public let shiftId: String
  public let caseIds: [String]
  /// Soft budget — surfaced to the player, never scored.
  public let timeBudget: Int
  public internal(set) var index: Int
  public internal(set) var results: [CaseResult]
  public internal(set) var breachRisk: Int
  public internal(set) var noise: Int
  public internal(set) var timeUsed: Int

  public init(
    shiftId: String, caseIds: [String], timeBudget: Int, index: Int = 0,
    results: [CaseResult] = [], breachRisk: Int = 0, noise: Int = 0, timeUsed: Int = 0
  ) {
    self.shiftId = shiftId
    self.caseIds = caseIds
    self.timeBudget = timeBudget
    self.index = index
    self.results = results
    self.breachRisk = breachRisk
    self.noise = noise
    self.timeUsed = timeUsed
  }

  public func result(for caseId: String) -> CaseResult? {
    results.first { $0.caseId == caseId }
  }
}

/// The 16:00 scoreline. Decodes 1:1 from the fixtures' `ShiftScoreJSON`.
///
/// The rates carry their numerator and denominator alongside the `Double` (§2.4) so
/// a parity failure localises to the counter instead of printing two long decimals.
/// The exporter derives them as: `accuracyNumerator = verdictCorrect`,
/// `accuracyDenominator = total`, `investigationRateNumerator = Σ keySourcesPulled`
/// and `investigationRateDenominator = Σ keySourceIds.count`, both summed over the
/// results whose case resolves.
public struct ShiftScore: Codable, Sendable, Hashable {
  /// Cases resolved.
  public let total: Int
  public let verdictCorrect: Int
  public let dispositionCorrect: Int
  /// TP closed.
  public let missedDetections: Int
  /// FP / Benign escalated.
  public let falseEscalations: Int
  /// `verdictCorrect / total`, 0…1.
  public let accuracy: Double
  public let accuracyNumerator: Int
  public let accuracyDenominator: Int
  /// Calls made with zero of the case's key sources pulled.
  public let blindCalls: Int
  /// Calls made with ALL of the case's key sources pulled.
  public let thoroughCalls: Int
  /// Key sources pulled / key sources available, 0…1.
  public let investigationRate: Double
  public let investigationRateNumerator: Int
  public let investigationRateDenominator: Int
  public let grade: ShiftGrade
  public let breachRisk: Int
  public let noise: Int

  public init(
    total: Int, verdictCorrect: Int, dispositionCorrect: Int, missedDetections: Int,
    falseEscalations: Int, accuracy: Double, accuracyNumerator: Int, accuracyDenominator: Int,
    blindCalls: Int, thoroughCalls: Int, investigationRate: Double,
    investigationRateNumerator: Int, investigationRateDenominator: Int,
    grade: ShiftGrade, breachRisk: Int, noise: Int
  ) {
    self.total = total
    self.verdictCorrect = verdictCorrect
    self.dispositionCorrect = dispositionCorrect
    self.missedDetections = missedDetections
    self.falseEscalations = falseEscalations
    self.accuracy = accuracy
    self.accuracyNumerator = accuracyNumerator
    self.accuracyDenominator = accuracyDenominator
    self.blindCalls = blindCalls
    self.thoroughCalls = thoroughCalls
    self.investigationRate = investigationRate
    self.investigationRateNumerator = investigationRateNumerator
    self.investigationRateDenominator = investigationRateDenominator
    self.grade = grade
    self.breachRisk = breachRisk
    self.noise = noise
  }
}
