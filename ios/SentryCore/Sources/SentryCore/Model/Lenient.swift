import Foundation

/// The lenient half of the openness policy (D10).
///
/// A `String`-backed value that **decodes anything** and round-trips an unknown raw
/// value byte-for-byte. Authoring a 25th case with a new archetype therefore costs
/// zero Swift, while the closed enums (`SocVerdict`, `Disposition`, `ShiftGrade`,
/// `TraceStatus`, `OutcomeKey`, `InvestigationQuality`) still fail loudly when a new
/// *branch* appears, because that is where logic lives.
public protocol LenientRawValue: RawRepresentable, Codable, Sendable, Hashable,
                                 CustomStringConvertible where RawValue == String {
  init(rawValue: String)
  /// The values authored today. Never used to reject a decode — only to answer
  /// `isKnown`, which the UI uses to pick a fallback presentation.
  static var known: [Self] { get }
}

extension LenientRawValue {
  public init(from decoder: any Decoder) throws {
    self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var description: String { rawValue }

  /// `false` for a raw value authored after this build shipped.
  public var isKnown: Bool { Self.known.contains(self) }
}

/// The case family. Lenient: content grows here (D10).
public struct SocArchetype: LenientRawValue {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let encodedPowerShell = SocArchetype(rawValue: "encoded-powershell")
  public static let authBruteforce    = SocArchetype(rawValue: "auth-bruteforce")
  public static let dnsC2             = SocArchetype(rawValue: "dns-c2")
  public static let phishing          = SocArchetype(rawValue: "phishing")
  public static let impossibleTravel  = SocArchetype(rawValue: "impossible-travel")
  public static let mfaFatigue        = SocArchetype(rawValue: "mfa-fatigue")
  public static let edrMalware        = SocArchetype(rawValue: "edr-malware")
  public static let dataExfil         = SocArchetype(rawValue: "data-exfil")
  public static let accountLockout    = SocArchetype(rawValue: "account-lockout")
  public static let insiderThreat     = SocArchetype(rawValue: "insider-threat")

  public static let known: [SocArchetype] = [
    .encodedPowerShell, .authBruteforce, .dnsC2, .phishing, .impossibleTravel,
    .mfaFatigue, .edrMalware, .dataExfil, .accountLockout, .insiderThreat,
  ]
}

/// What the detection tool *thinks* the alert is worth — often wrong, and the
/// reason the player pulls logs at all. Lenient; `CopyPack.severityMeta` carries a
/// fallback tone for a severity authored later (S5).
public struct ToolSeverity: LenientRawValue {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let low      = ToolSeverity(rawValue: "Low")
  public static let medium   = ToolSeverity(rawValue: "Medium")
  public static let high     = ToolSeverity(rawValue: "High")
  public static let critical = ToolSeverity(rawValue: "Critical")

  public static let known: [ToolSeverity] = [.low, .medium, .high, .critical]
}

/// How much a finding moves the read. Lenient (D10).
public struct EvidenceWeight: LenientRawValue {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let decisive   = EvidenceWeight(rawValue: "decisive")
  public static let supporting = EvidenceWeight(rawValue: "supporting")
  public static let neutral    = EvidenceWeight(rawValue: "neutral")
  public static let noise      = EvidenceWeight(rawValue: "noise")

  public static let known: [EvidenceWeight] = [.decisive, .supporting, .neutral, .noise]
}
