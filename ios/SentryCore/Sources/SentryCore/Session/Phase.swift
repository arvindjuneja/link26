import Foundation

/// Where you are in the shift (`DESIGN.md` §2.1, `SPEC.md` §3.3).
///
/// `readOnly` rides on `.debrief` because a debrief opened from the board's done
/// rows must return whence it came (Appendix A G5) — and because a re-read debrief
/// skips the 1.1 s entry sequence and the verdict cue (§5.8). Carrying it on the
/// phase rather than in a parallel Bool means the two can never disagree.
public enum Phase: Codable, Sendable, Hashable {
  case hub, briefing, investigating
  case debrief(readOnly: Bool)
  case complete, milestone

  /// For the DEBUG jump list, the placeholder labels and log lines. Never shown to
  /// a player.
  public var name: String {
    switch self {
    case .hub: "hub"
    case .briefing: "briefing"
    case .investigating: "investigating"
    case .debrief(let readOnly): readOnly ? "debrief (read-only)" : "debrief"
    case .complete: "complete"
    case .milestone: "milestone"
    }
  }

  public var isDebrief: Bool { if case .debrief = self { true } else { false } }

  /// A debrief being re-read rather than lived through.
  public var isReadOnly: Bool { if case .debrief(let readOnly) = self { readOnly } else { false } }
}

/// What is on top of the phase. `nil` is the web's `"none"` — an `Optional` so
/// `.sheet(item:)` and `.fullScreenCover(item:)` bind to it directly (§4.2).
public enum ViewID: Identifiable, Codable, Sendable, Hashable {
  case board
  case source(String)
  case call, kit, settings, abandon, firstRun

  public var id: String {
    switch self {
    case .board: "board"
    case .source(let sourceID): "source:\(sourceID)"
    case .call: "call"
    case .kit: "kit"
    case .settings: "settings"
    case .abandon: "abandon"
    case .firstRun: "firstRun"
    }
  }

  /// FirstRun is a `.fullScreenCover` with `interactiveDismissDisabled` — the
  /// disclaimer is not dismissible by accident. Everything else is a sheet.
  public var isFullScreen: Bool { self == .firstRun }

  public var sourceID: String? { if case .source(let id) = self { id } else { nil } }
}
