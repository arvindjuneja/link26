import Foundation

/// The pressure bands both meters share (`game/trace.ts`). Closed (D10).
///
/// **DV-3:** `Comparable` in the CALM < ALERT < HUNT < LOCKDOWN order, so
/// `overallShiftStatus` is `max(a, b)` instead of the TypeScript rank dictionary.
/// Pinned by `trace.json` and by every `shift-runs.json` step's `overallStatus`.
public enum TraceStatus: String, Codable, Sendable, Hashable, CaseIterable, Comparable {
  case calm     = "CALM"
  case alert    = "ALERT"
  case hunt     = "HUNT"
  case lockdown = "LOCKDOWN"

  /// Ascending pressure. Not exported — an implementation detail of `Comparable`.
  private var severityOrder: Int {
    switch self {
    case .calm: 0
    case .alert: 1
    case .hunt: 2
    case .lockdown: 3
    }
  }

  public static func < (lhs: TraceStatus, rhs: TraceStatus) -> Bool {
    lhs.severityOrder < rhs.severityOrder
  }
}
