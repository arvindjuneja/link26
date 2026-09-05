import Foundation
import Testing

@testable import SentryCore

/// The hand-built edge shifts of `scoring.json` — the states the seven corpus runs
/// never reach, and the ones where a Swift/TypeScript divergence would be silent:
/// an empty board, a board with no key sources at all, a result whose case no
/// longer exists, the five conjuncts of the `clean` rule isolated one at a time, a
/// meter driven past its ceiling, and the two `applyCall` invariants.
///
/// The rows reference three cases that are not in the bundle, so this suite grades
/// through an engine whose content also knows them.
@Suite("Golden scoring")
struct GoldenScoringTests {

  @Test("scoreShift matches the TypeScript engine", arguments: try Golden.scoringRows())
  func scoringParity(_ row: ScoringRow) throws {
    let engine = try Golden.scoringEngine()
    let score = engine.scoreShift(row.shift)

    #expect(score.total == row.score.total, "\(row.name) total")
    #expect(score.verdictCorrect == row.score.verdictCorrect, "\(row.name) verdictCorrect")
    #expect(
      score.dispositionCorrect == row.score.dispositionCorrect, "\(row.name) dispositionCorrect")
    #expect(score.missedDetections == row.score.missedDetections, "\(row.name) missedDetections")
    #expect(score.falseEscalations == row.score.falseEscalations, "\(row.name) falseEscalations")
    #expect(score.accuracyNumerator == row.score.accuracyNumerator, "\(row.name) accuracy ÷ num")
    #expect(
      score.accuracyDenominator == row.score.accuracyDenominator, "\(row.name) accuracy ÷ den")
    #expect(score.accuracy == row.score.accuracy, "\(row.name) accuracy")
    #expect(score.blindCalls == row.score.blindCalls, "\(row.name) blindCalls")
    #expect(score.thoroughCalls == row.score.thoroughCalls, "\(row.name) thoroughCalls")
    #expect(
      score.investigationRateNumerator == row.score.investigationRateNumerator,
      "\(row.name) investigationRate ÷ num")
    #expect(
      score.investigationRateDenominator == row.score.investigationRateDenominator,
      "\(row.name) investigationRate ÷ den")
    #expect(score.investigationRate == row.score.investigationRate, "\(row.name) investigationRate")
    #expect(score.grade == row.score.grade, "\(row.name) grade")
    #expect(score.breachRisk == row.score.breachRisk, "\(row.name) breachRisk")
    #expect(score.noise == row.score.noise, "\(row.name) noise")
    #expect(score == row.score, "\(row.name) score")

    #expect(
      engine.overallShiftStatus(row.shift) == row.overallStatus, "\(row.name) overallStatus")

    // Per-case investigation quality for every case the row can resolve.
    for investigation in row.investigations {
      let label = "\(row.name) · \(investigation.caseId)"
      let result = try #require(
        row.shift.results.first { $0.caseId == investigation.caseId }, "\(label): no result")
      let c = try #require(
        engine.content.case(investigation.caseId), "\(label): no case")
      #expect(engine.investigationOf(result, c) == investigation.quality, "\(label) quality")
    }
  }

  @Test("applyCall matches the TypeScript engine", arguments: try Golden.applyRows())
  func applyParity(_ row: ApplyRow) throws {
    let engine = try Golden.scoringEngine()
    let c = try #require(engine.content.case(row.caseId), "\(row.name): no case \(row.caseId)")
    let after = engine.applyCall(
      row.before, c, row.chosen,
      queriedSourceIds: row.queriedSourceIds, timeSpent: row.timeSpent)

    #expect(after.index == row.after.index, "\(row.name) index")
    #expect(after.breachRisk == row.after.breachRisk, "\(row.name) breachRisk")
    #expect(after.noise == row.after.noise, "\(row.name) noise")
    #expect(after.timeUsed == row.after.timeUsed, "\(row.name) timeUsed")
    #expect(after.results == row.after.results, "\(row.name) results")
    #expect(after == row.after, "\(row.name) state")
  }

  /// DV-1 spelled out: calling a case that has already been called replaces its
  /// result **where it already sits** — the JavaScript object spread does not move
  /// the key to the end — while the case pointer still advances.
  @Test("a second call on the same case replaces in place and keeps its position")
  func replaceInPlace() throws {
    let engine = try Golden.scoringEngine()
    let row = try #require(try Golden.applyRows().first { $0.name == "replace-in-place" })
    let positionBefore = try #require(row.before.results.firstIndex { $0.caseId == row.caseId })
    let c = try #require(engine.content.case(row.caseId))

    let after = engine.applyCall(
      row.before, c, row.chosen,
      queriedSourceIds: row.queriedSourceIds, timeSpent: row.timeSpent)

    #expect(after.results.count == row.before.results.count)
    #expect(after.results.firstIndex { $0.caseId == row.caseId } == positionBefore)
    #expect(after.results[positionBefore].chosen == row.chosen)
    #expect(after.index == row.before.index + 1)
    // The order of every other result is untouched.
    #expect(after.results.map(\.caseId) == row.before.results.map(\.caseId))
  }

  /// The documented duplicate-counting invariant (S6): `keySourcesPulled` counts
  /// the pulled ids, not the distinct ones, so a repeated id counts twice. The UI
  /// cannot produce one; a corrupted saved session can, and both engines agree.
  @Test("a duplicated pulled id is counted twice")
  func duplicateCountsTwice() throws {
    let engine = try Golden.scoringEngine()
    let row = try #require(try Golden.applyRows().first { $0.name == "duplicate-queried-id" })
    let c = try #require(engine.content.case(row.caseId))
    let result = engine.buildCaseResult(
      c, row.chosen, queriedSourceIds: row.queriedSourceIds, timeSpent: row.timeSpent)

    let expected = try #require(row.after.results.first { $0.caseId == row.caseId })
    #expect(result.keySourcesPulled == expected.keySourcesPulled)
    #expect(result.queriedSourceIds == row.queriedSourceIds)
    #expect(Set(row.queriedSourceIds).count < row.queriedSourceIds.count)
    #expect(result.keySourcesPulled == row.queriedSourceIds.count)
  }

  /// A result whose case is not in the content is SKIPPED, never fatal — the row
  /// that proves a saved session written before a case was renamed still scores.
  @Test("an unknown caseId is skipped, not fatal")
  func unknownCaseIsSkipped() throws {
    let engine = try Golden.scoringEngine()
    let row = try #require(try Golden.scoringRows().first { $0.name == "unknown-case-id" })
    let unknown = try #require(
      row.shift.results.first { engine.content.case($0.caseId) == nil })

    let resolved = row.shift.results.filter { engine.content.case($0.caseId) != nil }
    let score = engine.scoreShift(row.shift)

    // It still counts against the denominator — the skip happens after `total`.
    #expect(score.total == row.shift.results.count)
    #expect(score.accuracyDenominator == row.shift.results.count)
    #expect(score.total == resolved.count + 1)
    // …but contributes to nothing else, including the investigation sums.
    #expect(score.verdictCorrect == resolved.filter { $0.verdictCorrect }.count)
    #expect(
      score.investigationRateNumerator == resolved.reduce(0) { $0 + $1.keySourcesPulled })
    #expect(unknown.keySourcesPulled > 0)
    #expect(score == row.score)
  }

  /// The `clean` rule is a five-way conjunction, and every conjunct has a row that
  /// isolates it. This asserts the set is actually present, so a future edit cannot
  /// quietly drop one and still pass.
  @Test("every conjunct of the clean rule is isolated by a row")
  func cleanConjunctsAreCovered() throws {
    let rows = try Golden.scoringRows()
    let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) })

    let clean = try #require(byName["clean-accuracy-exactly-080"])
    #expect(clean.score.grade == .clean)
    #expect(clean.score.accuracy == Golden.pack.tuning.shift.cleanAccuracy)

    let below = try #require(byName["rough-accuracy-one-step-below"])
    #expect(below.score.grade == .rough)
    #expect(below.score.accuracy < Golden.pack.tuning.shift.cleanAccuracy)

    let blind = try #require(byName["rough-one-blind"])
    #expect(blind.score.grade == .rough)
    #expect(blind.score.blindCalls == 1)
    #expect(blind.score.accuracy == 1)

    let noisy = try #require(byName["rough-noise-lockdown"])
    #expect(noisy.score.grade == .rough)
    #expect(noisy.overallStatus == .lockdown)
    #expect(noisy.score.breachRisk < Golden.pack.tuning.trace.lockdown)

    let missed = try #require(byName["rough-one-missed-breach-30"])
    #expect(missed.score.grade == .rough)
    #expect(missed.score.missedDetections == 1)
    #expect(missed.score.breachRisk == Golden.pack.tuning.grade.tpMissedBreach)

    // …and the two `breached` triggers, which take precedence over all five.
    let lockdown = try #require(byName["breach-exactly-80"])
    #expect(lockdown.score.grade == .breached)
    #expect(lockdown.score.breachRisk == Golden.pack.tuning.trace.lockdown)
    #expect(lockdown.score.accuracy == 1)

    let twoMissed = try #require(byName["two-missed"])
    #expect(twoMissed.score.grade == .breached)
    #expect(
      twoMissed.score.missedDetections == Golden.pack.tuning.shift.breachedMissedDetections)
  }

  /// The two division guards, which are the only place a rate can be undefined:
  /// an empty board scores zero accuracy, and a board with no key sources to pull
  /// scores a full investigation rate rather than dividing by nothing.
  @Test("the empty board and the keyless board do not divide by zero")
  func divisionGuards() throws {
    let rows = try Golden.scoringRows()
    let empty = try #require(rows.first { $0.name == "empty-shift" })
    #expect(empty.score.total == 0)
    #expect(empty.score.accuracy == 0)
    #expect(empty.score.accuracyDenominator == 0)
    #expect(empty.score.investigationRate == 1)
    #expect(empty.score.investigationRateDenominator == 0)

    let keyless = try #require(rows.first { $0.name == "no-key-sources" })
    #expect(keyless.score.investigationRate == 1)
    #expect(keyless.score.investigationRateDenominator == 0)
    #expect(keyless.score.thoroughCalls == keyless.score.total)
    #expect(keyless.score.blindCalls == 0)
    // A case with nothing to pull reads thorough — there was nothing to miss.
    #expect(keyless.investigations.allSatisfy { $0.quality == .thorough })
  }

  /// The recorded side of the ceiling: `overflow-four-missed` is a shift whose four
  /// missed detections are worth more breach than the meter can hold, and every row
  /// in the file reports meters the band table covers. This reads the fixtures — it
  /// says nothing about `applyCall`, which `applyCallClampsBreach` /
  /// `applyCallClampsNoise` below drive for themselves.
  @Test("every recorded meter sits inside the band table")
  func meterOverflow() throws {
    let rows = try Golden.scoringRows()
    let overflow = try #require(rows.first { $0.name == "overflow-four-missed" })
    let t = Golden.pack.tuning
    #expect(overflow.score.breachRisk == t.trace.max)
    #expect(overflow.score.missedDetections * t.grade.tpMissedBreach > t.trace.max)
    #expect(overflow.score.grade == .breached)
    #expect(rows.allSatisfy { (t.trace.min...t.trace.max).contains($0.score.breachRisk) })
    #expect(rows.allSatisfy { (t.trace.min...t.trace.max).contains($0.score.noise) })
  }

  /// How many calls of one delta it takes to overrun the ceiling. Read off the
  /// tuning, never spelled, so a retune re-lengths the replay instead of breaking it.
  static func callsToOverrun(_ delta: Int, _ t: Tuning) -> Int {
    t.trace.max / delta + 1
  }

  /// The ceiling driven through `applyCall` itself, which is the only thing that
  /// moves a meter (DV-2). `overflow-four-missed` is a pre-built state handed to
  /// `scoreShift`, so it echoes a clamped field without ever exercising the clamp;
  /// this replays the same overflow one call at a time and pins the meter after
  /// every step, so dropping `Trace.clamp` from `applyCall` fails here.
  @Test("applyCall clamps breachRisk at the ceiling, every step")
  func applyCallClampsBreach() throws {
    let engine = Golden.engine
    let t = Golden.pack.tuning
    let delta = t.grade.tpMissedBreach
    let needed = Self.callsToOverrun(delta, t)
    let cases = Golden.pack.cases.filter { $0.truth == .truePositive }.prefix(needed)
    #expect(cases.count == needed, "the bundle is short of true positives to overrun with")

    var shift = engine.assembleShift("clamp-breach", cases.map(\.id))
    var unclamped = 0
    for (step, c) in cases.enumerated() {
      // Closing a true positive is the missed detection: breach only, noise never.
      shift = engine.applyCall(
        shift, c, .closeFalsePositive, queriedSourceIds: [], timeSpent: 0)
      unclamped += delta
      #expect(shift.breachRisk <= t.trace.max, "step \(step) climbed past the ceiling")
      #expect(shift.breachRisk >= t.trace.min, "step \(step) fell below the floor")
      #expect(shift.breachRisk == min(unclamped, t.trace.max), "step \(step) breachRisk")
      #expect(shift.noise == t.trace.min, "step \(step) noise moved")
    }

    #expect(unclamped > t.trace.max, "the replay never overran the ceiling")
    #expect(shift.breachRisk == t.trace.max)
    #expect(Trace.status(shift.breachRisk, t) == .lockdown)
    #expect(engine.overallShiftStatus(shift) == .lockdown)
    #expect(engine.scoreShift(shift).breachRisk == t.trace.max)
  }

  /// The same replay on the other meter: isolating a sanctioned activity is the
  /// heaviest noise delta in the tuning, and enough of them overrun the ceiling.
  @Test("applyCall clamps noise at the ceiling, every step")
  func applyCallClampsNoise() throws {
    let engine = Golden.engine
    let t = Golden.pack.tuning
    let delta = t.grade.btpIsolateNoise
    let needed = Self.callsToOverrun(delta, t)
    let cases = Golden.pack.cases.filter { $0.truth == .benignTruePositive }.prefix(needed)
    #expect(cases.count == needed, "the bundle is short of benign true positives to overrun with")

    var shift = engine.assembleShift("clamp-noise", cases.map(\.id))
    var unclamped = 0
    for (step, c) in cases.enumerated() {
      shift = engine.applyCall(
        shift, c, .escalateIRIsolate, queriedSourceIds: [], timeSpent: 0)
      unclamped += delta
      #expect(shift.noise <= t.trace.max, "step \(step) climbed past the ceiling")
      #expect(shift.noise >= t.trace.min, "step \(step) fell below the floor")
      #expect(shift.noise == min(unclamped, t.trace.max), "step \(step) noise")
      #expect(shift.breachRisk == t.trace.min, "step \(step) breachRisk moved")
    }

    #expect(unclamped > t.trace.max, "the replay never overran the ceiling")
    #expect(shift.noise == t.trace.max)
    #expect(Trace.status(shift.noise, t) == .lockdown)
    #expect(engine.overallShiftStatus(shift) == .lockdown)
    #expect(engine.scoreShift(shift).noise == t.trace.max)
  }

  /// `investigationOf` reads `keySourcesPulled >= total`, not `== total`. Only the
  /// documented duplicate-counting path (S6) can put a result strictly above its
  /// case's key total, and the shipped fixtures stay under it — so the strictly
  /// greater arm is pinned here instead: pull every key source, then pull one of
  /// them again, and the case still reads `thorough`.
  @Test("a result above its key total still reads thorough")
  func overCountedPullsAreThorough() throws {
    let engine = Golden.engine
    let c = try #require(
      Golden.pack.cases.first { !$0.keySourceIds.isEmpty }, "no case has key sources")
    let total = c.keySourceIds.count
    let first = try #require(c.keySourceIds.first)

    let over = engine.buildCaseResult(
      c, c.correctDisposition, queriedSourceIds: c.keySourceIds + [first], timeSpent: 0)
    #expect(over.keySourcesPulled > total, "the duplicate was not counted twice")
    #expect(engine.investigationOf(over, c) == .thorough)

    // The two neighbouring arms, so the boundary is read from both sides.
    let exact = engine.buildCaseResult(
      c, c.correctDisposition, queriedSourceIds: c.keySourceIds, timeSpent: 0)
    #expect(exact.keySourcesPulled == total)
    #expect(engine.investigationOf(exact, c) == .thorough)

    let none = engine.buildCaseResult(
      c, c.correctDisposition, queriedSourceIds: [], timeSpent: 0)
    #expect(none.keySourcesPulled == 0)
    #expect(engine.investigationOf(none, c) == .blind)
  }

  /// Drift-guard check #10 on this side: no grade and no investigation quality
  /// ships unread by this suite.
  @Test("the rows reach every grade and every investigation quality")
  func rowsCoverEveryBranch() throws {
    let rows = try Golden.scoringRows()
    #expect(rows.count >= 12)
    #expect(Set(rows.map(\.score.grade)) == Set(ShiftGrade.allCases))
    #expect(
      Set(rows.flatMap(\.investigations).map(\.quality)) == Set(InvestigationQuality.allCases))
  }
}
