import Foundation

/// Applying a call to the shift, and the shift's own lifecycle — the second half of
/// `app/lib/soc/engine.ts`, ported literally.
///
/// D7: no tuning literal. The only numeric literal in this file is the `1` of the
/// case pointer's single-step increment.
extension SOCEngine {

  // ── Shift assembly ─────────────────────────────────────────────────────────

  /// Build a fresh shift over the given ordered case ids. Pure.
  ///
  /// TypeScript defaults the budget to a module constant; here it defaults to
  /// `tuning.timeBudgetDefault`, which is that constant exported. The budget is
  /// soft — surfaced to the player, never scored.
  public func assembleShift(
    _ shiftId: String, _ caseIds: [String], timeBudget: Int? = nil
  ) -> ShiftState {
    ShiftState(
      shiftId: shiftId,
      caseIds: caseIds,
      timeBudget: timeBudget ?? tuning.timeBudgetDefault)
  }

  public func shiftComplete(_ shift: ShiftState) -> Bool {
    shift.index >= shift.caseIds.count
  }

  // ── Applying a call ────────────────────────────────────────────────────────

  /// The record of one resolved alert.
  ///
  /// `keySourcesPulled` filters the pulled ids against the key set and counts what
  /// is left — so a **duplicated id in `queriedSourceIds` counts twice**. That is a
  /// documented invariant of the web engine (S6), not a Swift artefact, and
  /// `scoring.json`'s `duplicate-queried-id` row pins it on both sides. The UI never
  /// produces a duplicate; a corrupted saved session could.
  public func buildCaseResult(
    _ c: SocCase, _ chosen: Disposition, queriedSourceIds: [String], timeSpent: Int
  ) -> CaseResult {
    let grade = gradeCall(c, chosen)
    let keySet = Set(c.keySourceIds)
    let keySourcesPulled = queriedSourceIds.filter { keySet.contains($0) }.count
    return CaseResult(
      caseId: c.id,
      chosen: chosen,
      verdictCorrect: grade.verdictCorrect,
      dispositionCorrect: grade.dispositionCorrect,
      queriedSourceIds: queriedSourceIds,
      keySourcesPulled: keySourcesPulled,
      timeSpent: timeSpent)
  }

  /// Fold a graded call into the shift state (advances the case pointer). Pure.
  ///
  /// **DV-1.** TypeScript writes `results: { ...shift.results, [c.id]: result }`.
  /// A JavaScript object spread onto an id that is already present **replaces the
  /// value and keeps the original key position** — it does not move the entry to
  /// the end. `results` here is an ordered array (D8), so that behaviour has to be
  /// spelled out: replace in place when the case has already been called, append
  /// otherwise. `scoring.json`'s `replace-in-place` row pins it.
  ///
  /// **DV-2.** The meters are `internal(set)` on `ShiftState`, so this is the only
  /// kind of place in the whole package that can move them. Note that `index` still
  /// advances on a replacement, exactly as the TypeScript does — the pointer counts
  /// calls made, not distinct cases.
  public func applyCall(
    _ shift: ShiftState, _ c: SocCase, _ chosen: Disposition,
    queriedSourceIds: [String], timeSpent: Int
  ) -> ShiftState {
    let grade = gradeCall(c, chosen)
    let result = buildCaseResult(
      c, chosen, queriedSourceIds: queriedSourceIds, timeSpent: timeSpent)

    var next = shift
    next.index = shift.index + 1
    if let existing = next.results.firstIndex(where: { $0.caseId == c.id }) {
      next.results[existing] = result
    } else {
      next.results.append(result)
    }
    next.breachRisk = Trace.clamp(shift.breachRisk + grade.breachDelta, tuning)
    next.noise = Trace.clamp(shift.noise + grade.noiseDelta, tuning)
    next.timeUsed = shift.timeUsed + timeSpent
    return next
  }

  // ── Meters ─────────────────────────────────────────────────────────────────

  /// Worst of the two pressure meters — the headline, and what drives the heartbeat.
  ///
  /// **DV-3.** TypeScript picks the worse of the two through a rank dictionary;
  /// `TraceStatus` is `Comparable` in the CALM < ALERT < HUNT < LOCKDOWN order, so
  /// the comparison is direct. The tie-break is written the TypeScript way round —
  /// on equality it returns the breach side — even though both sides are the same
  /// value, so the port reads against the original without a translation step.
  public func overallShiftStatus(_ shift: ShiftState) -> TraceStatus {
    let a = Trace.status(shift.breachRisk, tuning)
    let b = Trace.status(shift.noise, tuning)
    return a >= b ? a : b
  }
}
