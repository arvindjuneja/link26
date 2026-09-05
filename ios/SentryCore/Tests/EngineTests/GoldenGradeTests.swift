import Foundation
import Testing

@testable import SentryCore

/// `gradeCall` against every (case × disposition) pair the shipped corpus has —
/// 24 cases × 4 dispositions = 96 rows, each computed by the real TypeScript engine
/// at export time.
///
/// Every field is compared with exact `==`, including the headline, which is
/// resolved through `copy.outcomes[outcomeKey]` rather than transcribed. Each row is
/// its own named test result: a failure reads `soc-ps-cradle · close-benign`.
@Suite("Golden grades")
struct GoldenGradeTests {

  @Test("gradeCall matches the TypeScript engine", arguments: try Golden.grades())
  func gradeParity(_ row: GradeRow) throws {
    let c = try #require(
      Golden.pack.case(row.caseId),
      "content.json has no case \(row.caseId)")
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
    // The keyed accessor is the same branch tree, so it must never disagree.
    #expect(
      Golden.engine.outcomeKey(c, row.disposition) == g.outcomeKey,
      "\(row.testDescription) outcomeKey accessor")
  }

  @Test("the golden matrix is the whole corpus, once each")
  func matrixIsComplete() throws {
    let rows = try Golden.grades()
    #expect(rows.count == Golden.pack.cases.count * Disposition.allCases.count)
    #expect(rows.count == 96)
    #expect(Set(rows.map { "\($0.caseId)/\($0.disposition.rawValue)" }).count == rows.count)
  }

  /// The consequence model, stated as the invariant rather than as a table of
  /// numbers: breach is only ever spent on a true positive, noise only ever on
  /// crying wolf, and the two are never traded against each other in one call.
  @Test("the asymmetry holds across all 96 rows", arguments: try Golden.grades())
  func asymmetryHolds(_ row: GradeRow) throws {
    let c = try #require(Golden.pack.case(row.caseId))
    let g = Golden.engine.gradeCall(c, row.disposition)
    #expect(!(g.breachDelta > 0 && g.noiseDelta > 0), "\(row.testDescription) spent both meters")
    if g.breachDelta > 0 { #expect(c.truth == .truePositive) }
    #expect(g.breachDelta >= 0)
    #expect(g.noiseDelta >= 0)
    // `exact` is the strict half of `dispositionCorrect`, never the other way round.
    if g.exact { #expect(g.dispositionCorrect) }
  }

  /// D11, re-derived on this side: the under-contained arm is dead over the shipped
  /// corpus, which is what makes `grades-synthetic.json` mandatory rather than nice
  /// to have. If a content author ever authors a TP without acceptables, this test
  /// fails and the fixture set gets one more real row — a good failure.
  @Test("the under-contained arm is unreachable from the shipped corpus")
  func underContainedIsDead() throws {
    let rows = try Golden.grades()
    #expect(!rows.contains { $0.outcomeKey == .tpUnderContained })
    #expect(!rows.contains { $0.breachDelta == Golden.pack.tuning.grade.tpUnderContainBreach })
  }
}
