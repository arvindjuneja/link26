import Foundation
import Testing

@testable import SentryCore

/// The three constructed cases of `grades-synthetic.json` × four dispositions.
///
/// They exist for one reason: the shipped corpus never reaches the under-contained
/// arm (D11), so without them a transcription bug in that branch ships undetected
/// and detonates the first time a true positive is authored without acceptables.
/// Their cases are NOT in the bundle, so the case comes from the fixture itself.
@Suite("Synthetic grades")
struct SyntheticGradeTests {

  @Test("gradeCall matches the TypeScript engine", arguments: try Golden.syntheticRows())
  func syntheticParity(_ row: GradeRow) throws {
    let file = try Golden.syntheticFile()
    let c = try #require(
      file.cases.first { $0.id == row.caseId },
      "grades-synthetic.json has no case \(row.caseId)")
    let g = Golden.engine.gradeCall(c, row.disposition)

    #expect(g.verdictCorrect == row.verdictCorrect, "\(row.testDescription) verdictCorrect")
    #expect(
      g.dispositionCorrect == row.dispositionCorrect, "\(row.testDescription) dispositionCorrect")
    #expect(g.exact == row.exact, "\(row.testDescription) exact")
    #expect(g.breachDelta == row.breachDelta, "\(row.testDescription) breachDelta")
    #expect(g.noiseDelta == row.noiseDelta, "\(row.testDescription) noiseDelta")
    #expect(g.outcomeKey == row.outcomeKey, "\(row.testDescription) outcomeKey")
    #expect(
      Golden.engine.outcomeText(g.outcomeKey) == row.outcome,
      "\(row.testDescription) outcome prose")
  }

  @Test("the synthetic set is three cases by four dispositions")
  func shape() throws {
    let file = try Golden.syntheticFile()
    #expect(file.cases.count == 3)
    #expect(file.rows.count == 12)
    #expect(Set(file.rows.map(\.caseId)) == Set(file.cases.map(\.id)))
    // They are fixture-only: none of them is in the shipped bundle.
    #expect(file.cases.allSatisfy { Golden.pack.case($0.id) == nil })
  }

  /// The whole point of the file: with the real 96 rows it reaches all eleven copy
  /// keys, so no branch of `gradeCall` ships unread.
  @Test("the two grade files together reach all eleven outcome keys")
  func allKeysReached() throws {
    let real = try Golden.grades()
    let synthetic = try Golden.syntheticRows()
    let reached = Set(real.map(\.outcomeKey)).union(synthetic.map(\.outcomeKey))
    #expect(reached == Set(OutcomeKey.allCases))
    #expect(reached.count == 11)
    // …and the dead arm is reached by the synthetic set alone.
    #expect(synthetic.contains { $0.outcomeKey == .tpUnderContained })
  }

  /// Eleven keys, twelve arms: the two false-positive escalations share one
  /// headline and are told apart only by their noise delta, which comes from
  /// tuning. This is the assertion that would catch the two being collapsed.
  @Test("the twelfth arm is distinguishable by its delta, not by its key")
  func twelfthArm() throws {
    let rows = try Golden.grades()
    let escalated = rows.filter { $0.outcomeKey == .fpEscalated }
    let t2 = escalated.filter { $0.disposition == .escalateTier2 }
    let isolate = escalated.filter { $0.disposition == .escalateIRIsolate }
    #expect(!t2.isEmpty)
    #expect(!isolate.isEmpty)
    #expect(t2.allSatisfy { $0.noiseDelta == Golden.pack.tuning.grade.fpEscalateT2Noise })
    #expect(
      isolate.allSatisfy { $0.noiseDelta == Golden.pack.tuning.grade.fpEscalateIsolateNoise })
  }
}
