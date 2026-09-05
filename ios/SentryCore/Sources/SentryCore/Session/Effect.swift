import Foundation

/// What a transition asks the app to *do* (§4.1).
///
/// The reducer is pure: it returns the next session and a list of consequences, and
/// `EffectRunner` is the only interpreter of that list. Views never touch storage
/// and never fire a haptic themselves — which is what makes "the debrief buzzed
/// twice" a testable property (`SessionTests/EffectScheduleTests`) instead of a bug
/// report.
public enum Effect: Equatable, Sendable, Hashable {
  /// A cue for a transition the reducer itself made. Cues that belong to a screen's
  /// *entry animation* — the debrief stamp, the payout count-up, each finding as it
  /// lands — are fired by that screen through `GameModel.feel(_:)`, because only the
  /// view knows when the animation reaches them.
  case haptic(SocCue)
  /// Snapshot the in-flight shift. Coalesced by the runner to ≤1 write per 250 ms.
  case persistSession
  /// The shift settled or was abandoned — the snapshot is gone. Carries a
  /// generation bump in the runner, so a write already in the air cannot resurrect
  /// what this deleted.
  case clearSession
  /// Apply `session.settlement`: the career it computed becomes the career, and the
  /// inbox is rebuilt from the `HandlerEvent` it carries. The arithmetic already
  /// happened, in the reducer.
  case settleShift
  case persistCareer
  /// One of the five launch-critical `UserDefaults` flags.
  case setFlag(String, Bool)
  /// The daily board paid out; stamp `career.dailyDoneOn` (Appendix A G7). Emitted
  /// **after** `.settleShift`, because the settled career carries yesterday's stamp.
  case markDailyDone(String)
}
