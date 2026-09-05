import Foundation

/// The pure SOC engine of `app/lib/soc/engine.ts` — no I/O, no side effects.
/// The console drives effects; this type only computes next-state from a call.
///
/// It is a **literal** port: branch for branch, test for test, in the source
/// order of the TypeScript. Where the two differ the divergence is numbered and
/// documented (DV-1 · DV-2 · DV-3) rather than smoothed over.
///
/// **D7 — no tuning literal.** Every number the engine branches on is read from
/// `content.tuning`, so a designer retune is a re-export and zero Swift. The only
/// numeric literals in `Engine/` are `0` (an empty accumulator, an empty count, or
/// the accuracy of a shift with nothing on the board) and `1` (a single-step
/// increment, and the investigation rate of a shift with no key sources to pull).
/// `EngineTests/TuningLiteralGuardTests` enforces that on the sources themselves;
/// `EngineTests/TuningExpectationTests` pins the twenty-nine tuning numbers so a
/// silent retune is loud in review.
public struct SOCEngine: Sendable {

  /// The decoded bundle this engine grades against. `scoreShift` resolves a
  /// result's case through `content.casesByID`; everything else is handed the case.
  ///
  /// **Internal on purpose.** SPEC §3.3's `SOCEngine` block is a frozen signature
  /// list and does not carry a `content` property, so exposing one here would widen
  /// the public API past the contract C5/C8 build against. Callers outside the
  /// package already hold the `ContentPack` they constructed the engine from; the
  /// parity suites read it under `@testable`.
  let content: ContentPack

  public init(content: ContentPack) {
    self.content = content
  }

  /// Shorthand for the numbers. Not public: callers read `content.tuning`.
  var tuning: Tuning { content.tuning }

  // ── Grading one call ───────────────────────────────────────────────────────

  /// The module-private `isEscalate` of `engine.ts`. Both escalations count as
  /// "sent it up"; the difference between them is containment, which the branches
  /// below weigh separately.
  static func isEscalate(_ d: Disposition) -> Bool {
    d == .escalateTier2 || d == .escalateIRIsolate
  }

  /// Grade a disposition against a case's ground truth, and compute the consequence
  /// to the two pressure meters. Pure.
  ///
  /// The consequence model is deliberately asymmetric — a missed live threat is the
  /// cardinal sin of a SOC; crying wolf is the chronic one:
  ///  - Miss a TP (close it)          → `breachRisk` spikes hard (it is dwelling).
  ///  - Under-contain a TP (T2 vs IR) → verdict right, small breach (partial dwell).
  ///  - Over-contain a TP (isolate what should be handed up, e.g. insider → HR/legal)
  ///                                  → verdict right, NOISE (tipped off, case burned).
  ///  - Escalate an FP                → noise (wasted Tier-2 cycles).
  ///  - Escalate authorised (Benign-TP) → noise; isolating it also hits ops (worse).
  ///
  /// The headline prose is deliberately absent from the return: `outcomeKey` is the
  /// copy key and `outcomeText(_:)` resolves it, so a wording change in the web tree
  /// can never desync the two engines.
  public func gradeCall(_ c: SocCase, _ chosen: Disposition) -> CallGrade {
    let chosenVerdict = chosen.verdict
    let verdictCorrect = chosenVerdict == c.truth
    let exact = chosen == c.correctDisposition
    // TypeScript reads `c.acceptableDispositions?.includes(chosen) ?? false`; the
    // export makes the field `[]` rather than absent, so the optional chain is gone
    // and the behaviour is identical.
    let dispositionCorrect = exact || c.acceptableDispositions.contains(chosen)

    var breachDelta = 0
    var noiseDelta = 0
    let outcomeKey: OutcomeKey

    // A `switch` over the closed verdict enum, in the order of the TypeScript
    // if/else-if/else — `benign-true-positive` is its trailing `else`.
    switch c.truth {
    case .truePositive:
      if !Self.isEscalate(chosen) {
        // Closed a real threat. The worst call a Tier-1 can make.
        breachDelta = tuning.grade.tpMissedBreach
        outcomeKey = .tpMissed
      } else if dispositionCorrect {
        outcomeKey = .tpEscalatedCorrect
      } else if chosen == .escalateIRIsolate {
        // Over-contained: isolated what should have been handed up. Nothing dwells
        // — the exfil is contained — so the harm is operational, which hits NOISE.
        noiseDelta = tuning.grade.tpOverContainNoise
        outcomeKey = .tpOverContained
      } else {
        // Under-contained: escalated, but did not contain when the threat needed
        // contain-now, so it had room to move — a partial dwell.
        //
        // D11: this arm is DEAD over the shipped corpus. `grades-synthetic.json`
        // is the only fixture that reaches it, which is why it is mandatory.
        breachDelta = tuning.grade.tpUnderContainBreach
        outcomeKey = .tpUnderContained
      }

    case .falsePositive:
      if !Self.isEscalate(chosen) {
        // Closed correctly. Closing as "benign" instead of "FP" is a near-miss on
        // reasoning but not operationally harmful — still counts, verdict differs.
        outcomeKey = verdictCorrect ? .fpClosedFP : .fpClosedAsBenign
      } else {
        noiseDelta = chosen == .escalateIRIsolate
          ? tuning.grade.fpEscalateIsolateNoise
          : tuning.grade.fpEscalateT2Noise
        // One key, two arms: both escalations share a single headline, so the
        // deltas come from tuning and never from the key.
        outcomeKey = .fpEscalated
      }

    case .benignTruePositive:
      // The behaviour really happened, and it was sanctioned.
      if chosen == .closeBenign {
        outcomeKey = .btpClosedBenign
      } else if chosen == .closeFalsePositive {
        // Closed it (no breach), but mislabelled WHY.
        noiseDelta = tuning.grade.btpClosedAsFpNoise
        outcomeKey = .btpClosedAsFP
      } else if chosen == .escalateIRIsolate {
        noiseDelta = tuning.grade.btpIsolateNoise
        outcomeKey = .btpIsolated
      } else {
        noiseDelta = tuning.grade.btpEscalateT2Noise
        outcomeKey = .btpEscalatedT2
      }
    }

    return CallGrade(
      verdictCorrect: verdictCorrect,
      dispositionCorrect: dispositionCorrect,
      exact: exact,
      breachDelta: breachDelta,
      noiseDelta: noiseDelta,
      outcomeKey: outcomeKey)
  }

  /// The copy key alone, for callers that want the headline without the deltas.
  /// Delegates to `gradeCall` so there is exactly one branch tree to keep honest.
  public func outcomeKey(_ c: SocCase, _ chosen: Disposition) -> OutcomeKey {
    gradeCall(c, chosen).outcomeKey
  }

  /// The debrief headline for a graded call, resolved through the copy pack.
  public func outcomeText(_ key: OutcomeKey) -> String {
    content.copy.outcomeText(key)
  }
}
