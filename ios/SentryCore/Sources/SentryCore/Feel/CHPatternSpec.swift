import Foundation

/// The four patterns `.sensoryFeedback` cannot express (§4.4, D17), as pure values.
///
/// Every number here is a *waveform*, and the only verification that exists before a
/// device is `SessionTests/HapticPatternTests` reading these back (X7). So they are
/// written once, here, and C10's translator is not allowed an opinion.
public enum CHPatternSpec {

  /// The loop, for a status — `nil` at CALM and ALERT.
  ///
  /// A 90 ms **continuous** lub with a 0 → 1.0 @18 ms → 0 @90 ms intensity curve
  /// (the fast attack is what makes it a THUMP; the fall is what stops it being a
  /// buzz), then a transient dub at `tuning.heartbeat.dubOffsetMs`. The player loops
  /// it with `loopEnd = periodMs`, so this describes one beat, not the loop.
  public static func heartbeat(_ status: TraceStatus, _ tuning: Tuning) -> HapticPattern? {
    guard let plan = heartbeatPlan(status: status, tuning: tuning),
          let lub = plan.lub, let dub = plan.dub
    else { return nil }

    let duration = HeartbeatFeel.lubDurationSeconds
    return HapticPattern(
      events: [
        .continuous(
          at: 0, duration: duration, intensity: lub.intensity, sharpness: lub.sharpness),
        .transient(
          at: TimeInterval(dub.atMs) / 1000, intensity: dub.intensity, sharpness: dub.sharpness),
      ],
      curves: [
        HapticPattern.ParameterCurve(
          parameterID: .intensityControl,
          relativeTime: 0,
          controlPoints: [
            .init(relativeTime: 0, value: 0),
            .init(relativeTime: HeartbeatFeel.lubAttackSeconds, value: 1.0),
            .init(relativeTime: duration, value: 0),
          ]),
      ])
  }

  /// The stamp landing: *tick-tick-CLUNK*.
  ///
  /// Two sharp transients 45 ms apart — the ceremony of the hold resolving — then a
  /// dull 140 ms continuous body that decays to nothing, which is the weight of a
  /// call you cannot take back.
  public static let file = HapticPattern(
    events: [
      .transient(at: 0, intensity: 0.35, sharpness: 0.90),
      .transient(at: 0.045, intensity: 0.45, sharpness: 0.90),
      .continuous(at: 0.09, duration: 0.14, intensity: 1.0, sharpness: 0.25),
    ],
    curves: [
      HapticPattern.ParameterCurve(
        parameterID: .intensityControl,
        relativeTime: 0.09,
        controlPoints: [
          .init(relativeTime: 0, value: 1.0),
          .init(relativeTime: 0.04, value: 0.65),
          .init(relativeTime: 0.14, value: 0),
        ]),
    ])

  /// `grade.breachDelta ≥ 30` as the meter sweeps: low, sickening, double.
  ///
  /// A 180 ms continuous at full intensity and almost no sharpness — felt in the
  /// hand rather than heard — with a second, sharper hit at the 90 ms mark so it
  /// lands as two blows and not one long buzz.
  public static let breachThud = HapticPattern(
    events: [
      .continuous(at: 0, duration: 0.18, intensity: 1.0, sharpness: 0.15),
      .transient(at: 0.09, intensity: 0.8, sharpness: 0.40),
    ])

  /// The rank-up beat: four events over 700 ms, rising in intensity **and**
  /// sharpness (0 / 180 / 420 / 700 ms). It is the only cue in the game that
  /// crescendos, which is why it is the one that reads as an award.
  public static let rankup = HapticPattern(
    events: [
      .transient(at: 0, intensity: 0.45, sharpness: 0.35),
      .transient(at: 0.18, intensity: 0.55, sharpness: 0.45),
      .transient(at: 0.42, intensity: 0.80, sharpness: 0.60),
      .transient(at: 0.70, intensity: 1.00, sharpness: 0.75),
    ])

  /// The bespoke pattern for a cue, if it has one. `heartbeat` is deliberately
  /// absent: it needs the tuning and it loops, so it goes through
  /// `CHPatternSpec.heartbeat(_:_:)`.
  public static func pattern(for cue: SocCue) -> HapticPattern? {
    switch cue {
    case .file: file
    case .breachThud: breachThud
    case .rankup: rankup
    default: nil
    }
  }
}
