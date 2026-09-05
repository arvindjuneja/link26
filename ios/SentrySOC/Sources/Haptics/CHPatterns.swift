import CoreHaptics
import SentryCore

/// The translator, and **nothing else** (§10 C10 #5, X7).
///
/// Every waveform in this game is authored as a `SentryCore.HapticPattern` value —
/// a Foundation-only description that `SessionTests/HapticPatternTests` reads back
/// on macOS, which is the only verification that exists before a physical device.
/// This file turns one of those values into the Core Haptics objects and takes no
/// position on any of it: no defaults, no clamping, no "helpful" reordering, no
/// numbers of its own. If a control point is wrong it is wrong in `CHPatternSpec`,
/// where a test can see it.
///
/// The one place a `switch` appears is mapping two closed enums onto their Core
/// Haptics counterparts, which is translation rather than a decision.
enum CHPatterns {

  /// A transient is a tap and takes the three-argument initialiser; a continuous
  /// event carries the duration it was authored with. Passing a duration to a
  /// transient is not an error Core Haptics reports — it is simply ignored — so the
  /// two shapes are kept apart here rather than papered over.
  static func event(_ event: HapticPattern.Event) -> CHHapticEvent {
    let parameters = [
      CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
      CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness),
    ]
    switch event.kind {
    case .transient:
      return CHHapticEvent(
        eventType: .hapticTransient, parameters: parameters,
        relativeTime: event.relativeTime)
    case .continuous:
      return CHHapticEvent(
        eventType: .hapticContinuous, parameters: parameters,
        relativeTime: event.relativeTime, duration: event.duration)
    }
  }

  /// The envelope over a continuous event. `relativeTime` on the curve is the top of
  /// the curve inside the pattern; the control points are relative to *that*, which
  /// is Core Haptics' own convention and `HapticPattern.ParameterCurve`'s too — so
  /// this is a field-for-field copy.
  static func curve(_ curve: HapticPattern.ParameterCurve) -> CHHapticParameterCurve {
    CHHapticParameterCurve(
      parameterID: parameterID(curve.parameterID),
      controlPoints: curve.controlPoints.map {
        CHHapticParameterCurve.ControlPoint(relativeTime: $0.relativeTime, value: $0.value)
      },
      relativeTime: curve.relativeTime)
  }

  static func parameterID(
    _ id: HapticPattern.ParameterCurve.ParameterID
  ) -> CHHapticDynamicParameter.ID {
    switch id {
    case .intensityControl: .hapticIntensityControl
    case .sharpnessControl: .hapticSharpnessControl
    }
  }

  /// Throws exactly what `CHHapticPattern` throws — an empty event list, a control
  /// point out of range. The caller logs it; nothing here tries to repair it.
  static func pattern(_ pattern: HapticPattern) throws -> CHHapticPattern {
    try CHHapticPattern(
      events: pattern.events.map(event), parameterCurves: pattern.curves.map(curve))
  }
}
