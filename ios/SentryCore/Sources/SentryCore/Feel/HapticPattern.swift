import Foundation

/// A Core Haptics pattern, described in Foundation.
///
/// `Feel/` imports Foundation and nothing else (§10 C5 #3), so the whole vocabulary
/// stays inside the macOS `swift test` build. `Haptics/CHPatterns.swift` (C10) is a
/// dumb translator from these values to `CHHapticEvent` / `CHHapticParameterCurve`
/// with no logic of its own — which is the only way the curve timings can be
/// verified before a device, because the Simulator has no haptics at all (X7).
public struct HapticPattern: Sendable, Hashable, Codable {

  /// One event. Transient is a tap; continuous is a hold with a duration and,
  /// usually, a curve shaping it.
  public struct Event: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
      case transient
      case continuous
    }

    public let kind: Kind
    /// Seconds from the top of the pattern.
    public let relativeTime: TimeInterval
    /// Seconds. Zero for a transient.
    public let duration: TimeInterval
    public let intensity: Float
    public let sharpness: Float

    public init(
      kind: Kind, relativeTime: TimeInterval, duration: TimeInterval = 0,
      intensity: Float, sharpness: Float
    ) {
      self.kind = kind
      self.relativeTime = relativeTime
      self.duration = duration
      self.intensity = intensity
      self.sharpness = sharpness
    }

    public static func transient(
      at relativeTime: TimeInterval, intensity: Float, sharpness: Float
    ) -> Event {
      Event(
        kind: .transient, relativeTime: relativeTime, intensity: intensity,
        sharpness: sharpness)
    }

    public static func continuous(
      at relativeTime: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float
    ) -> Event {
      Event(
        kind: .continuous, relativeTime: relativeTime, duration: duration,
        intensity: intensity, sharpness: sharpness)
    }

    /// When this event stops.
    public var endTime: TimeInterval { relativeTime + duration }
  }

  /// The envelope over a continuous event — what turns a 90 ms buzz into a thump.
  public struct ParameterCurve: Sendable, Hashable, Codable {
    public enum ParameterID: String, Sendable, Hashable, Codable {
      case intensityControl
      case sharpnessControl
    }

    public struct ControlPoint: Sendable, Hashable, Codable {
      /// Seconds from the curve's own `relativeTime`.
      public let relativeTime: TimeInterval
      public let value: Float

      public init(relativeTime: TimeInterval, value: Float) {
        self.relativeTime = relativeTime
        self.value = value
      }
    }

    public let parameterID: ParameterID
    /// Seconds from the top of the pattern.
    public let relativeTime: TimeInterval
    public let controlPoints: [ControlPoint]

    public init(
      parameterID: ParameterID, relativeTime: TimeInterval, controlPoints: [ControlPoint]
    ) {
      self.parameterID = parameterID
      self.relativeTime = relativeTime
      self.controlPoints = controlPoints
    }
  }

  public let events: [Event]
  public let curves: [ParameterCurve]

  public init(events: [Event], curves: [ParameterCurve] = []) {
    self.events = events
    self.curves = curves
  }

  /// How long the pattern runs — the last thing to finish, event or curve.
  public var duration: TimeInterval {
    let eventEnd = events.map(\.endTime).max() ?? 0
    let curveEnd =
      curves.map { curve in curve.relativeTime + (curve.controlPoints.map(\.relativeTime).max() ?? 0) }
      .max() ?? 0
    return max(eventEnd, curveEnd)
  }
}
