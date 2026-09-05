import Foundation

/// The three-way classification every Tier-1 alert resolves to. Closed (D10):
/// the engine branches on it, so a fourth verdict must fail to decode and name
/// itself rather than slip through as content.
///
/// Raw values are the TypeScript literals verbatim.
public enum SocVerdict: String, Codable, Sendable, Hashable, CaseIterable, CodingKeyRepresentable {
  case truePositive       = "true-positive"
  case falsePositive      = "false-positive"
  case benignTruePositive = "benign-true-positive"
}

/// The player's call: classification + response in one move. Closed (D10).
///
/// `allCases` is the **exported order** — which is `DISPOSITIONS` in `types.ts`,
/// which is the button order on the call sheet. `ContentTests` pins it against
/// `content.dispositions`.
public enum Disposition: String, Codable, Sendable, Hashable, CaseIterable, CodingKeyRepresentable {
  case closeFalsePositive = "close-false-positive"
  case closeBenign        = "close-benign"
  case escalateTier2      = "escalate-tier2"
  case escalateIRIsolate  = "escalate-ir-isolate"

  /// Which verdict a disposition encodes (`verdictOf` in `types.ts`).
  public var verdict: SocVerdict {
    switch self {
    case .closeFalsePositive: .falsePositive
    case .closeBenign: .benignTruePositive
    case .escalateTier2, .escalateIRIsolate: .truePositive
    }
  }
}

/// Per-case investigation quality, derived from the recorded result. Closed (D10):
/// `scoreShift` counts blind and thorough calls off it.
public enum InvestigationQuality: String, Codable, Sendable, Hashable, CaseIterable {
  case blind
  case partial
  case thorough
}
