import Foundation

/// Grading the whole shift — the 16:00 scoreline of `app/lib/soc/engine.ts`,
/// ported literally, counter for counter and in the same loop order.
///
/// D7: no tuning literal. The numeric literals in this file are the `0` of each
/// counter's start, the `0` of an empty comparison, the `0` accuracy of a shift
/// with nothing on the board, and the `1` investigation rate of a shift with no key
/// sources to pull. All four are the TypeScript's own, and none is a tuning number.
extension SOCEngine {

  /// Per-case investigation quality, from the recorded result.
  ///
  /// A case with no key sources is `thorough` by definition — there was nothing to
  /// miss — which is the branch that keeps a content author from accidentally
  /// grading a whole board blind.
  public func investigationOf(_ r: CaseResult, _ c: SocCase) -> InvestigationQuality {
    let total = c.keySourceIds.count
    if total == 0 { return .thorough }
    if r.keySourcesPulled == 0 { return .blind }
    if r.keySourcesPulled >= total { return .thorough }
    return .partial
  }

  /// Score a finished (or abandoned) shift.
  ///
  /// **DV-1.** TypeScript reads `Object.values(shift.results)` — insertion order;
  /// `results` is already that array. Nothing here depends on the order, but the
  /// board strip and the read-only debrief do.
  ///
  /// **A result whose `caseId` is not in the content is SKIPPED, never fatal** (S6).
  /// TypeScript does `if (!c) continue;` and Swift does the same: a saved session
  /// written before a case was renamed still scores, one alert short, instead of
  /// trapping on the player. Note the skip happens *after* `total` is taken, so such
  /// a result still counts against accuracy — again, exactly as the TypeScript does.
  public func scoreShift(_ shift: ShiftState) -> ShiftScore {
    let results = shift.results
    let total = results.count
    var verdictCorrect = 0
    var dispositionCorrect = 0
    var missedDetections = 0
    var falseEscalations = 0
    var blindCalls = 0
    var thoroughCalls = 0
    var keyPulledSum = 0
    var keyTotalSum = 0

    for r in results {
      guard let c = content.casesByID[r.caseId] else { continue }
      if r.verdictCorrect { verdictCorrect += 1 }
      if r.dispositionCorrect { dispositionCorrect += 1 }
      let chosenVerdict = r.chosen.verdict
      if c.truth == .truePositive && chosenVerdict != .truePositive { missedDetections += 1 }
      if c.truth != .truePositive && chosenVerdict == .truePositive { falseEscalations += 1 }
      keyTotalSum += c.keySourceIds.count
      keyPulledSum += r.keySourcesPulled
      let quality = investigationOf(r, c)
      if quality == .blind {
        blindCalls += 1
      } else if quality == .thorough {
        thoroughCalls += 1
      }
    }

    let accuracy = total > 0 ? Double(verdictCorrect) / Double(total) : 0
    let investigationRate = keyTotalSum > 0 ? Double(keyPulledSum) / Double(keyTotalSum) : 1

    // The grade keys off the breach meter first — a breach on your watch is a rough
    // night regardless of raw accuracy — then accuracy. A clean shift also needs the
    // NOISE meter calm, AND no BLIND calls: a right verdict reached without pulling
    // the logs that answer the case is luck, not analysis.
    let noiseStatus = Trace.status(shift.noise, tuning)
    let grade: ShiftGrade
    if Trace.status(shift.breachRisk, tuning) == .lockdown
      || missedDetections >= tuning.shift.breachedMissedDetections {
      grade = .breached
    } else if accuracy >= tuning.shift.cleanAccuracy
      && missedDetections == 0
      && blindCalls == 0
      && noiseStatus != .hunt
      && noiseStatus != .lockdown {
      grade = .clean
    } else {
      grade = .rough
    }

    // The two rates carry their numerator and denominator alongside the `Double`, so
    // a parity failure localises to the counter instead of printing two long
    // decimals. They are the counters the rate was divided from, not a re-derivation.
    return ShiftScore(
      total: total,
      verdictCorrect: verdictCorrect,
      dispositionCorrect: dispositionCorrect,
      missedDetections: missedDetections,
      falseEscalations: falseEscalations,
      accuracy: accuracy,
      accuracyNumerator: verdictCorrect,
      accuracyDenominator: total,
      blindCalls: blindCalls,
      thoroughCalls: thoroughCalls,
      investigationRate: investigationRate,
      investigationRateNumerator: keyPulledSum,
      investigationRateDenominator: keyTotalSum,
      grade: grade,
      breachRisk: shift.breachRisk,
      noise: shift.noise)
  }
}
