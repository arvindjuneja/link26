import Foundation
import Testing

@testable import SentryCore

/// The seven scripted runs of `shift-runs.json`, replayed call by call.
///
/// The state is asserted after **every step**, not just at the end: a meter that
/// clamps one call too early and a meter that clamps one call too late produce the
/// same final number on a run that ends pinned, and only the intermediate snapshots
/// tell them apart. Then the whole `ShiftScore` is compared field by field, with
/// exact `==` on both `Double` rates (D13 — JS and Swift agree bit-for-bit).
@Suite("Golden shift runs")
struct GoldenShiftRunTests {

  @Test("every step of every run reproduces the TypeScript state", arguments: try Golden.runs())
  func runParity(_ run: ShiftRun) throws {
    var state = Golden.engine.assembleShift(run.shiftId, run.caseIds)

    // The board as assembled, before a single call.
    #expect(state.shiftId == run.shiftId, "\(run.name) shiftId")
    #expect(state.caseIds == run.caseIds, "\(run.name) caseIds")
    #expect(state.timeBudget == Golden.pack.tuning.timeBudgetDefault, "\(run.name) timeBudget")
    #expect(state.index == 0, "\(run.name) opening index")
    #expect(state.results.isEmpty, "\(run.name) opening results")
    #expect(state.breachRisk == 0, "\(run.name) opening breachRisk")
    #expect(state.noise == 0, "\(run.name) opening noise")
    #expect(state.timeUsed == 0, "\(run.name) opening timeUsed")
    #expect(!Golden.engine.shiftComplete(state), "\(run.name) complete before any call")

    for (n, step) in run.steps.enumerated() {
      let label = "\(run.name) step \(n) · \(step.caseId)"
      let c = try #require(Golden.pack.case(step.caseId), "\(label): no such case")

      state = Golden.engine.applyCall(
        state, c, step.chosen,
        queriedSourceIds: step.queriedSourceIds,
        timeSpent: step.timeSpent)

      #expect(state.index == step.after.index, "\(label) index")
      #expect(state.breachRisk == step.after.breachRisk, "\(label) breachRisk")
      #expect(state.noise == step.after.noise, "\(label) noise")
      #expect(state.timeUsed == step.after.timeUsed, "\(label) timeUsed")
      // DV-1: the whole ordered array, not a set and not just the last entry.
      #expect(state.results == step.after.results, "\(label) results")
      #expect(
        Golden.engine.overallShiftStatus(state) == step.after.overallStatus,
        "\(label) overallStatus")
      // The board is only finished once, on the last call.
      #expect(
        Golden.engine.shiftComplete(state) == (n == run.steps.count - 1),
        "\(label) shiftComplete")
    }

    let score = Golden.engine.scoreShift(state)
    #expect(score.total == run.score.total, "\(run.name) total")
    #expect(score.verdictCorrect == run.score.verdictCorrect, "\(run.name) verdictCorrect")
    #expect(
      score.dispositionCorrect == run.score.dispositionCorrect, "\(run.name) dispositionCorrect")
    #expect(score.missedDetections == run.score.missedDetections, "\(run.name) missedDetections")
    #expect(score.falseEscalations == run.score.falseEscalations, "\(run.name) falseEscalations")
    #expect(score.accuracyNumerator == run.score.accuracyNumerator, "\(run.name) accuracy ÷ num")
    #expect(
      score.accuracyDenominator == run.score.accuracyDenominator, "\(run.name) accuracy ÷ den")
    #expect(score.accuracy == run.score.accuracy, "\(run.name) accuracy")
    #expect(score.blindCalls == run.score.blindCalls, "\(run.name) blindCalls")
    #expect(score.thoroughCalls == run.score.thoroughCalls, "\(run.name) thoroughCalls")
    #expect(
      score.investigationRateNumerator == run.score.investigationRateNumerator,
      "\(run.name) investigationRate ÷ num")
    #expect(
      score.investigationRateDenominator == run.score.investigationRateDenominator,
      "\(run.name) investigationRate ÷ den")
    #expect(score.investigationRate == run.score.investigationRate, "\(run.name) investigationRate")
    #expect(score.grade == run.score.grade, "\(run.name) grade")
    #expect(score.breachRisk == run.score.breachRisk, "\(run.name) breachRisk")
    #expect(score.noise == run.score.noise, "\(run.name) noise")
    // Nothing left over: the struct compares equal as a whole too.
    #expect(score == run.score, "\(run.name) score")
  }

  /// Per-case investigation quality, replayed off the same runs — the counter
  /// `scoreShift` folds into `blindCalls` / `thoroughCalls`, checked one case at a
  /// time so a mis-summed total localises.
  @Test("investigation quality is consistent with the counters", arguments: try Golden.runs())
  func investigationCounters(_ run: ShiftRun) throws {
    let last = try #require(run.steps.last, "\(run.name) has no steps")
    var blind = 0
    var thorough = 0
    for result in last.after.results {
      guard let c = Golden.pack.case(result.caseId) else { continue }
      switch Golden.engine.investigationOf(result, c) {
      case .blind: blind += 1
      case .thorough: thorough += 1
      case .partial: break
      }
    }
    #expect(blind == run.score.blindCalls, "\(run.name) blindCalls")
    #expect(thorough == run.score.thoroughCalls, "\(run.name) thoroughCalls")
  }

  /// D13 — the `?demo=complete` run, pinned to the values the founder ran. The one
  /// row in the corpus that fixes the float claim: JS `0.8571428571428571` decodes
  /// in Swift to exactly `6.0 / 7.0`, so this asserts `==`, not a tolerance.
  @Test("the demo-complete run reproduces its pinned score")
  func demoComplete() throws {
    let run = try #require(try Golden.runs().first { $0.name == "shift1-demo-complete" })
    var state = Golden.engine.assembleShift(run.shiftId, run.caseIds)
    for step in run.steps {
      let c = try #require(Golden.pack.case(step.caseId))
      state = Golden.engine.applyCall(
        state, c, step.chosen,
        queriedSourceIds: step.queriedSourceIds, timeSpent: step.timeSpent)
    }
    let score = Golden.engine.scoreShift(state)
    #expect(score.total == 7)
    #expect(score.verdictCorrect == 6)
    #expect(score.dispositionCorrect == 6)
    #expect(score.missedDetections == 0)
    #expect(score.falseEscalations == 1)
    #expect(score.accuracy == 6.0 / 7.0)
    #expect(score.accuracy == 0.8571428571428571)
    #expect(score.blindCalls == 1)
    #expect(score.thoroughCalls == 6)
    #expect(score.investigationRate == 0.875)
    #expect(score.grade == .rough)
    #expect(score.breachRisk == 0)
    #expect(score.noise == 12)
    #expect(Golden.engine.overallShiftStatus(state) == .calm)
  }

  /// The seven runs are the whole ladder, and between them they reach every grade —
  /// which is what stops a grade branch from shipping unread.
  @Test("the run set covers the ladder and every grade")
  func runSetIsComplete() throws {
    let runs = try Golden.runs()
    #expect(runs.count == 7)
    #expect(Set(runs.map(\.shiftId)).count == 5)
    #expect(Set(runs.map(\.score.grade)) == Set(ShiftGrade.allCases))
    #expect(runs.allSatisfy { $0.steps.map(\.caseId) == $0.caseIds })
  }
}
