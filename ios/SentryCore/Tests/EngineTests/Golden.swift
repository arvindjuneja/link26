import Foundation
import SentryFixtures
import Testing

@testable import SentryCore

// A parameterised failure has to name the row, not print the whole struct. The
// library cannot carry these conformances — `SentryCore` imports Foundation only
// (D15) — so they live here, in the target that needs them. `SocCase` and
// `ShiftDef` are deliberately NOT conformed here: `ContentTests` already does, and
// two conformances of one type in one test bundle is a runtime warning.

extension GradeRow: CustomTestStringConvertible {
  public var testDescription: String { "\(caseId) · \(disposition.rawValue)" }
}

extension ShiftRun: CustomTestStringConvertible {
  public var testDescription: String { name }
}

extension ScoringRow: CustomTestStringConvertible {
  public var testDescription: String { name }
}

extension ApplyRow: CustomTestStringConvertible {
  public var testDescription: String { name }
}

extension TraceStatusRow: CustomTestStringConvertible {
  public var testDescription: String { "level \(level)" }
}

extension TraceClampRow: CustomTestStringConvertible {
  public var testDescription: String { "clamp \(level)" }
}

/// Shared handles for the parity suites.
///
/// Every fixture was produced by running the **real TypeScript engine** at export
/// time, so a disagreement here is a transcription bug in the Swift port — not a
/// disagreement about what the game should do. Nothing in this target re-derives an
/// expected value; it only decodes one and compares.
enum Golden {

  /// The shipped bundle, and the engine over it.
  static let pack = ContentPack.bundled
  static let engine = SOCEngine(content: ContentPack.bundled)

  struct MissingFixture: Error, CustomStringConvertible {
    let name: String
    var description: String { "SentryFixtures is missing \(name).json" }
  }

  static func decode<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    guard let url = SentryFixtures.bundle.url(forResource: name, withExtension: "json") else {
      throw MissingFixture(name: name)
    }
    return try JSONDecoder().decode(type, from: try Data(contentsOf: url))
  }

  // ── the six files this ticket grades against ───────────────────────────────

  static func grades() throws -> [GradeRow] {
    try decode("grades", as: GradeFile.self).rows
  }

  static func syntheticFile() throws -> SyntheticGradeFile {
    try decode("grades-synthetic", as: SyntheticGradeFile.self)
  }

  static func syntheticRows() throws -> [GradeRow] {
    try syntheticFile().rows
  }

  static func traceFile() throws -> TraceFile {
    try decode("trace", as: TraceFile.self)
  }

  static func traceStatusRows() throws -> [TraceStatusRow] {
    try traceFile().status
  }

  static func traceClampRows() throws -> [TraceClampRow] {
    try traceFile().clamp
  }

  static func runs() throws -> [ShiftRun] {
    try decode("shift-runs", as: ShiftRunFile.self).runs
  }

  static func scoringFile() throws -> ScoringFile {
    try decode("scoring", as: ScoringFile.self)
  }

  static func scoringRows() throws -> [ScoringRow] {
    try scoringFile().rows
  }

  static func applyRows() throws -> [ApplyRow] {
    try scoringFile().applyRows
  }

  // ── engines over the fixture-inline cases ──────────────────────────────────

  /// A pack that also knows cases which are not in the bundle — the constructed
  /// sets of `grades-synthetic.json` and `scoring.json`. `scoreShift` resolves a
  /// result through `content.casesByID`, so those rows need an engine that can see
  /// them; `gradeCall` is handed the case and needs nothing.
  ///
  /// Built through the real `ContentPack` initialiser, so the inline cases get
  /// their `sources` expanded from the same 26-entry catalogue the bundle uses.
  static func extendedPack(with extra: [SocCase]) -> ContentPack {
    let base = pack
    let bundle = ContentBundle(
      schemaVersion: base.schemaVersion,
      contentHash: base.contentHash,
      dispositions: base.dispositions,
      sources: base.sources,
      cases: base.cases + extra,
      shifts: base.shifts,
      ranks: base.ranks,
      kit: base.kit,
      tuning: base.tuning)
    return ContentPack(bundle: bundle, copy: base.copy, daily: base.daily)
  }

  static func engine(alsoKnowing extra: [SocCase]) -> SOCEngine {
    SOCEngine(content: extendedPack(with: extra))
  }

  /// The engine the `scoring.json` rows are scored by: the bundle plus that file's
  /// three zero-key-source cases.
  static func scoringEngine() throws -> SOCEngine {
    engine(alsoKnowing: try scoringFile().cases)
  }
}
