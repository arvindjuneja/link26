import Foundation
import Testing

@testable import SentryCore

/// The seven golden files decode into the shipped model types, in full.
///
/// C2 does not grade anything — that is C3's and C4's parity work — but if the
/// fixtures cannot be read into these mirrors, those tickets discover it in their
/// own suite instead of here, where the fix is a schema change. So this suite reads
/// every row of every file once and pins the counts the spec names.
@Suite("Fixture decode")
struct FixtureDecodeTests {

  @Test("grades.json is 96 rows over the bundled cases")
  func grades() throws {
    let file = try Bundled.decodeFixture("grades", as: GradeFile.self)
    #expect(file.rows.count == 96)
    #expect(file.rows.allSatisfy { Bundled.pack.case($0.caseId) != nil })
    // 24 cases × 4 dispositions, each pair exactly once.
    #expect(Set(file.rows.map(\.caseId)).count == 24)
    #expect(Set(file.rows.map { "\($0.caseId)/\($0.disposition.rawValue)" }).count == 96)
    // The prose is the copy pack's, resolved by key — never a transcribed literal.
    for row in file.rows {
      #expect(row.outcome == Bundled.copy.outcomeText(row.outcomeKey))
    }
  }

  @Test("grades-synthetic.json reaches the arm the shipped corpus never does")
  func syntheticGrades() throws {
    let file = try Bundled.decodeFixture("grades-synthetic", as: SyntheticGradeFile.self)
    #expect(file.cases.count == 3)
    #expect(file.rows.count == 12)
    #expect(Set(file.rows.map(\.caseId)) == Set(file.cases.map(\.id)))
    #expect(file.rows.contains { $0.outcomeKey == .tpUnderContained })
    // D11: the dead branch really is dead over the 96 real rows.
    let real = try Bundled.decodeFixture("grades", as: GradeFile.self)
    #expect(!real.rows.contains { $0.outcomeKey == .tpUnderContained })
  }

  /// Drift check #4, mirrored on this side of the export: if someone adds a twelfth
  /// branch and no fixture reaches it, the Swift port ships untested.
  @Test("every OutcomeKey is reached by at least one golden row")
  func everyOutcomeKeyIsCovered() throws {
    let real = try Bundled.decodeFixture("grades", as: GradeFile.self)
    let synthetic = try Bundled.decodeFixture("grades-synthetic", as: SyntheticGradeFile.self)
    let reached = Set(real.rows.map(\.outcomeKey)).union(synthetic.rows.map(\.outcomeKey))
    #expect(reached == Set(OutcomeKey.allCases))
  }

  @Test("shift-runs.json is 7 stepped runs")
  func shiftRuns() throws {
    let file = try Bundled.decodeFixture("shift-runs", as: ShiftRunFile.self)
    #expect(file.runs.count == 7)
    for run in file.runs {
      #expect(!run.steps.isEmpty)
      #expect(run.steps.map(\.caseId) == run.caseIds)
      #expect(run.score.total == run.steps.count)
      // Every step's snapshot carries its results in call order (DV-1).
      for (index, step) in run.steps.enumerated() {
        #expect(step.after.results.count == index + 1)
        #expect(step.after.results.last?.caseId == step.caseId)
        #expect(step.after.index == index + 1)
      }
      #expect(Set(run.unlockedBefore).isSubset(of: Set(run.unlockedAfter)))
    }
  }

  /// D13 — the `?demo=complete` run is pinned to values the founder ran.
  @Test("the demo-complete run holds its pinned score")
  func demoCompleteRun() throws {
    let file = try Bundled.decodeFixture("shift-runs", as: ShiftRunFile.self)
    let run = try #require(file.runs.first { $0.name == "shift1-demo-complete" })
    #expect(run.score.total == 7)
    #expect(run.score.verdictCorrect == 6)
    #expect(run.score.dispositionCorrect == 6)
    #expect(run.score.missedDetections == 0)
    #expect(run.score.falseEscalations == 1)
    #expect(run.score.accuracy == 6.0 / 7.0)          // exact, not a tolerance
    #expect(run.score.accuracy == 0.8571428571428571)
    #expect(run.score.accuracyNumerator == 6)
    #expect(run.score.accuracyDenominator == 7)
    #expect(run.score.investigationRateNumerator == 14)
    #expect(run.score.investigationRateDenominator == 16)
    #expect(run.score.blindCalls == 1)
    #expect(run.score.thoroughCalls == 6)
    #expect(run.score.investigationRate == 0.875)
    #expect(run.score.grade == .rough)
    #expect(run.score.breachRisk == 0)
    #expect(run.score.noise == 12)
    #expect(run.reward.cashGain == 300)
    #expect(run.reward.standingGain == 15)
    #expect(run.reward.rankUp == nil)
    #expect(run.inbox.map(\.id) == ["ev-rough", "tip-kit"])
  }

  @Test("trace.json covers every level and the clamp edges")
  func trace() throws {
    let file = try Bundled.decodeFixture("trace", as: TraceFile.self)
    #expect(file.status.count == 111)
    #expect(file.status.map(\.level) == Array(-5...105))
    #expect(file.clamp.count == 7)
    #expect(file.clamp.allSatisfy { (0...100).contains($0.value) })
  }

  @Test("career.json walks the ladder and the shop")
  func career() throws {
    let file = try Bundled.decodeFixture("career", as: CareerFile.self)
    #expect(file.awards.count == 12)
    #expect(file.buys.count == 3)
    #expect(!file.redRuns.isEmpty)
    #expect(file.awards.allSatisfy { $0.reward.state.standing >= $0.before.standing })
    #expect(file.awards.allSatisfy { row in
      row.unlockedIds.allSatisfy { Bundled.pack.shift($0) != nil }
    })
    // The blue-only build never earns a red-seat cut, but the row still parses.
    #expect(file.redRuns.allSatisfy { $0.after.redRunsDone == $0.before.redRunsDone + 1 })
  }

  @Test("handler.json is 14 scenarios, blue-only capped at four")
  func handler() throws {
    let file = try Bundled.decodeFixture("handler", as: HandlerFile.self)
    #expect(file.scenarios.count == 14)
    for scenario in file.scenarios {
      #expect(scenario.messagesBlueOnly.count <= 4)
      #expect(scenario.messagesAll.count <= 4)
      // S3: the blue-only inbox is the filtered one, never a different corpus.
      #expect(!scenario.messagesBlueOnly.contains { $0.id == "tip-redrun" })
      // Every message is either a template by name, or an unlock message whose id
      // is `ev-unlock-<shiftId>` — the one id the web builds per shift.
      #expect(scenario.messagesBlueOnly.allSatisfy { message in
        if Bundled.copy.handler.templates[message.id] != nil { return true }
        guard message.id.hasPrefix("ev-unlock-") else { return false }
        return Bundled.pack.shift(String(message.id.dropFirst("ev-unlock-".count))) != nil
      })
      #expect(scenario.messagesBlueOnly.allSatisfy { !$0.body.contains("{") })
      #expect(scenario.messagesBlueOnly.allSatisfy { $0.tone.isKnown })
    }
    // …and at least one scenario proves the suppression bites.
    #expect(file.scenarios.contains { $0.messagesAll.contains { $0.id == "tip-redrun" } })
  }

  @Test("scoring.json holds the hand-built edge shifts")
  func scoring() throws {
    let file = try Bundled.decodeFixture("scoring", as: ScoringFile.self)
    #expect(file.rows.count >= 12)                     // S6
    #expect(!file.applyRows.isEmpty)
    #expect(file.cases.allSatisfy { Bundled.pack.case($0.id) == nil })
    // The zero-key-source path, which is the whole reason those inline cases exist.
    #expect(file.cases.contains { $0.keySourceIds.isEmpty })
    #expect(file.rows.contains { $0.score.investigationRateDenominator == 0 })
    #expect(file.rows.contains { $0.score.grade == .breached })
    #expect(file.rows.contains { $0.score.grade == .clean })
    #expect(file.rows.contains { $0.overallStatus == .lockdown })
    // Meters never leave 0…100, which is what Swift's Int arithmetic must preserve.
    #expect(file.rows.allSatisfy { (0...100).contains($0.score.breachRisk) })
    #expect(file.rows.allSatisfy { (0...100).contains($0.score.noise) })
  }

  /// Drift-guard check #10 on this side: every grade and every investigation quality
  /// is exercised somewhere in the corpus, so no Swift branch ships unread.
  @Test("every ShiftGrade and InvestigationQuality appears in the fixtures")
  func gradesAndQualitiesAreCovered() throws {
    let scoring = try Bundled.decodeFixture("scoring", as: ScoringFile.self)
    let runs = try Bundled.decodeFixture("shift-runs", as: ShiftRunFile.self)
    let career = try Bundled.decodeFixture("career", as: CareerFile.self)

    var grades = Set(scoring.rows.map(\.score.grade))
    grades.formUnion(runs.runs.map(\.score.grade))
    grades.formUnion(career.awards.map(\.score.grade))
    #expect(grades == Set(ShiftGrade.allCases))

    let qualities = Set(scoring.rows.flatMap(\.investigations).map(\.quality))
    #expect(qualities == Set(InvestigationQuality.allCases))
  }
}
