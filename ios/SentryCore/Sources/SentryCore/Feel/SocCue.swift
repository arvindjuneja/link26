import Foundation

/// The cue vocabulary of `DESIGN.md` §2.15 / `SPEC.md` §4.4 — **the 15 rows of the
/// cue table**, as Swift cases.
///
/// The mapping is not 1:1 with the table and is deliberate:
///
/// - the table's single `shift-*` row is three cases (`shiftClean`, `shiftRough`,
///   `shiftBreached`), because the caller has a `ShiftGrade`, not a string;
/// - the table's two beat rows (`beat-lub`, `beat-dub`) are one case,
///   `heartbeat(TraceStatus)`, because natively they are one `CHHapticPattern` with
///   the dub at +120 ms rather than two calls the app has to time itself (§4.4).
///
/// 15 rows − 2 beat rows − 1 shift row + 1 heartbeat case + 3 shift cases = **16
/// cases**. `HapticPatternTests` pins that arithmetic against the table so the two
/// cannot drift.
///
/// Twelve of them route to SwiftUI `.sensoryFeedback`; `file`, `breachThud` and
/// `rankup` get bespoke patterns from `CHPatternSpec`, and `heartbeat` is the
/// looping player (C10).
///
/// **F2a adds six** — `arrive`, `queryStart`, `tick`, `stamp`, `ping`, `landCard` —
/// for the sequences of `FEEL.md` §1/§2/§4/§8. The original sixteen are untouched.
/// Three of the six are **sound only** (`soundOnly`): `FEEL.md` gives them an audio
/// row and a `—` in the haptic column, because they are moments the ear should
/// notice and the hand should not — a log line ticking past, the fourth card
/// landing, the ink hitting the paper 450 ms after the file thud already answered
/// the thumb. A cue that is heard and not felt is still one cue and one call site;
/// what changes is which channel answers.
public enum SocCue: Sendable, Hashable, Codable {
  /// Source row · disposition pick · queue row · settings toggle.
  case select
  /// Hold-to-file progress at 0 / 180 / 360 ms.
  case holdTick
  /// A finding lands on the board. Fired by the source sheet, max 3 per pull.
  case findingLand
  /// Start the shift · buy kit · pull a source · payout count-up ends.
  case commitSoft
  /// Hold-to-file completes — the stamp. Bespoke: *tick-tick-CLUNK*.
  case file
  /// Debrief mount — right call.
  case verdictGood
  /// Debrief mount — right verdict, off response.
  case verdictOff
  /// Debrief mount — wrong call.
  case verdictWrong
  /// `grade.breachDelta ≥ 30` as the meter sweeps. Bespoke: low, sickening, double.
  case breachThud
  case shiftClean
  case shiftRough
  case shiftBreached
  /// The rank-up beat. Bespoke: four events over 700 ms.
  case rankup
  /// Locked queue row tap · a refused purchase · a call with nothing revealed.
  case denied
  /// Abandon confirmed · reset career confirmed.
  case destructive
  /// The looping lub-dub. Only HUNT and LOCKDOWN have one — silence at CALM and
  /// ALERT is the reward (§2.15).
  case heartbeat(TraceStatus)

  // ── F2a · the sequence cues (FEEL.md §1/§2/§4/§8) ─────────────────────────

  /// An alert arrives (§2, t=120): a low pad and a click under the ECG spike.
  case arrive
  /// A source pull opens (§4, t=0): a filtered noise burst under the log pane.
  case queryStart
  /// One log line streams in (§4), and the severity chip stamping in (§2, t=1500,
  /// pitched by severity). A 20 ms click — heard, never felt.
  case tick
  /// The ink stamp landing on the debrief (§8, t=450). The hand was already
  /// answered by `file` at t=0, so this one is only heard.
  case stamp
  /// An alert landing on the handover rail (§1) and a live-board reveal (§5): a
  /// sonar ping, stepping up in pitch per alert.
  case ping
  /// A finding card landing **past** the third (§4 caps the haptic at three, not
  /// the sound). Sound only, by design: the fourth card is information, not
  /// ceremony.
  case landCard

  /// Every cue, with `heartbeat` at each status. For the C10 sink's exhaustiveness
  /// test and for the QA cue list.
  public static let allCases: [SocCue] =
    [
      .select, .holdTick, .findingLand, .commitSoft, .file, .verdictGood, .verdictOff,
      .verdictWrong, .breachThud, .shiftClean, .shiftRough, .shiftBreached, .rankup,
      .denied, .destructive,
      .arrive, .queryStart, .tick, .stamp, .ping, .landCard,
    ] + TraceStatus.allCases.map { .heartbeat($0) }

  /// The six cues F2a added, in the order `FEEL.md` §9's table introduces them.
  public static let sequenceCues: [SocCue] = [
    .arrive, .queryStart, .tick, .stamp, .ping, .landCard,
  ]

  /// **Heard, never felt.** `FEEL.md` gives these an audio row and a `—` in the
  /// haptic column; the sink reads this list rather than guessing from a `nil`
  /// route, so "this cue has no haptic" stays a decision the document made and not
  /// an accident of a switch.
  public static let soundOnly: [SocCue] = [.tick, .stamp, .landCard]

  /// Whether this cue is one of the three the hand never answers.
  public var isSoundOnly: Bool { Self.soundOnly.contains(self) }

  /// The three that cannot be expressed with `.sensoryFeedback` and are built from
  /// `CHPatternSpec` instead (§4.4). `heartbeat` is a fourth, but it loops rather
  /// than plays, so it is the pattern player's business and not this list's.
  public static let bespoke: [SocCue] = [.file, .breachThud, .rankup]

  /// The shift-summary cue for a grade, so no caller spells the mapping twice.
  public static func shift(_ grade: ShiftGrade) -> SocCue {
    switch grade {
    case .clean: .shiftClean
    case .rough: .shiftRough
    case .breached: .shiftBreached
    }
  }

  /// The debrief-mount cue for a graded call (§4.4): right call · right verdict but
  /// the wrong response · wrong.
  public static func verdict(_ grade: CallGrade) -> SocCue {
    if grade.dispositionCorrect { return .verdictGood }
    return grade.verdictCorrect ? .verdictOff : .verdictWrong
  }

  /// Greppable in a log line and stable enough to key a QA overlay.
  public var name: String {
    switch self {
    case .select: "select"
    case .holdTick: "holdTick"
    case .findingLand: "findingLand"
    case .commitSoft: "commitSoft"
    case .file: "file"
    case .verdictGood: "verdictGood"
    case .verdictOff: "verdictOff"
    case .verdictWrong: "verdictWrong"
    case .breachThud: "breachThud"
    case .shiftClean: "shiftClean"
    case .shiftRough: "shiftRough"
    case .shiftBreached: "shiftBreached"
    case .rankup: "rankup"
    case .denied: "denied"
    case .destructive: "destructive"
    case .heartbeat(let status): "heartbeat(\(status.rawValue))"
    case .arrive: "arrive"
    case .queryStart: "queryStart"
    case .tick: "tick"
    case .stamp: "stamp"
    case .ping: "ping"
    case .landCard: "landCard"
    }
  }
}
