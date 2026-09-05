import Foundation

/// A message's voice. Lenient (D10, S5): `CopyPack.handlerToneMeta` carries the
/// fallback for a tone authored later, and the exported schema types this field as
/// a plain string.
public struct HandlerTone: LenientRawValue {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let warm      = HandlerTone(rawValue: "warm")
  public static let warn      = HandlerTone(rawValue: "warn")
  public static let tip       = HandlerTone(rawValue: "tip")
  public static let milestone = HandlerTone(rawValue: "milestone")

  public static let known: [HandlerTone] = [.warm, .warn, .tip, .milestone]
}

/// What just happened, as the inbox sees it. Closed: `inboxFor` branches on it.
public enum HandlerEventType: String, Codable, Sendable, Hashable, CaseIterable {
  case shiftClean    = "shift-clean"
  case shiftRough    = "shift-rough"
  case shiftBreached = "shift-breached"
}

/// A shift that just opened — id and label only, as the event carries it.
public struct UnlockedShift: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let label: String

  public init(id: String, label: String) {
    self.id = id
    self.label = label
  }
}

/// The thing the inbox reacts to. Decodes 1:1 from `HandlerEventJSON`, where
/// `type` and `rankUp` are `null` rather than absent.
public struct HandlerEvent: Codable, Sendable, Hashable {
  public var type: HandlerEventType?
  public var rankUp: Rank?
  public var unlocked: [UnlockedShift]

  public init(
    type: HandlerEventType? = nil, rankUp: Rank? = nil, unlocked: [UnlockedShift] = []
  ) {
    self.type = type
    self.rankUp = rankUp
    self.unlocked = unlocked
  }
}

/// One rendered message on the hub. Decodes 1:1 from `HandlerMessageJSON` — the
/// body arrives already interpolated in the fixtures, and `HandlerVoice` renders it
/// from `CopyPack.handler.templates` at runtime.
public struct HandlerMessage: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let from: String
  public let role: String
  public let subject: String
  public let body: String
  public let tone: HandlerTone

  public init(id: String, from: String, role: String, subject: String, body: String, tone: HandlerTone) {
    self.id = id
    self.from = from
    self.role = role
    self.subject = subject
    self.body = body
    self.tone = tone
  }
}
