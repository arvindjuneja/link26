import Foundation

/// A colour run in briefing / ladder prose (D5). Rendered as `AttributedString`.
///
/// Lenient like the other content-shaped raw values: a tone authored after this
/// build ships renders with the app's default run rather than failing the whole
/// content decode. Presentation only — no branch in `SentryCore` reads it.
public struct Tone: LenientRawValue {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let cyan    = Tone(rawValue: "cyan")
  public static let emerald = Tone(rawValue: "emerald")
  public static let rose    = Tone(rawValue: "rose")
  public static let amber   = Tone(rawValue: "amber")
  public static let fuchsia = Tone(rawValue: "fuchsia")
  public static let strong  = Tone(rawValue: "strong")
  public static let em      = Tone(rawValue: "em")
  public static let muted   = Tone(rawValue: "muted")

  public static let known: [Tone] = [
    .cyan, .emerald, .rose, .amber, .fuchsia, .strong, .em, .muted,
  ]
}

/// One run of tone-tagged text. `tone` is absent for body copy.
public struct RichSegment: Codable, Sendable, Hashable {
  public let text: String
  public let tone: Tone?

  public init(text: String, tone: Tone? = nil) {
    self.text = text
    self.tone = tone
  }
}

extension Array where Element == RichSegment {
  /// The paragraph with every run concatenated — the accessibility label, and the
  /// string the S10 bidirectional pins compare against.
  public var plainText: String { map(\.text).joined() }
}
