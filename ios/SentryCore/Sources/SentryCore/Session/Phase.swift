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
  /// A source sheet, and **why it opened** (`FEEL.md` §3, §4).
  ///
  /// §3 says "Tap `Pull` (or long-press the row, 350 ms) = the pull. **No confirm
  /// dialog**", and §4's timeline starts at `QUERYING`. So the touch that opens this
  /// sheet is already the commit, and the sheet has to know that on the frame it
  /// appears — otherwise it draws SPEC §5.5's offer and asks for the same decision a
  /// second time, which is a tap the player spends fifteen times a shift for nothing
  /// they did not already know (the cost is printed on the row).
  ///
  /// `autoPull` is that intent, carried on the action rather than in a flag beside
  /// it: the reducer is the one entry point, and "which view, and why" is one fact.
  /// It is **false** when a *spent* row re-opens — a re-read is a record, not a
  /// commit — and false by default, so nothing that merely names a source sheet
  /// (a QA jump, a restored view, a placeholder) can spend a player's minutes.
  case source(String, autoPull: Bool = false)
  case call, kit, settings, abandon, firstRun

  /// The sheet's identity is the **source**, not the touch that opened it: `id` is
  /// what `.sheet(item:)` binds to, and a pull chip and a re-read of the same row
  /// must not be two presentations.
  public var id: String {
    switch self {
    case .board: "board"
    case .source(let sourceID, _): "source:\(sourceID)"
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

  public var sourceID: String? { if case .source(let id, _) = self { id } else { nil } }

  //  There is deliberately **no** `autoPull` accessor beside `sourceID`: the one
  //  place that needs the flag — `PlayScreens.sheet(for:model:)` — already binds both
  //  halves in its `case`, and a second unused way to ask the same question is what
  //  the F2c review objected to elsewhere (§15.1 #6).
}
