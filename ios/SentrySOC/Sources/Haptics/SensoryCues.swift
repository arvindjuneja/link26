import SwiftUI
import UIKit
import SentryCore

/// The twelve cues of the §4.4 table that `.sensoryFeedback` can express.
///
/// Naming them as their own enum rather than as `SensoryFeedback` values directly is
/// what lets the same cue be rendered two ways without the mapping being written
/// twice: SwiftUI's declarative modifier, which is the route §4.4 chose and the one
/// every cue takes in the shipped app, and the UIKit generator that modifier is built
/// on, which is the safety net for the window before any screen is on the glass (see
/// `SensoryRelay`).
enum SensoryCue: Hashable, Sendable {
  case selection
  case impactLight
  /// `flexibility: .solid` at a reduced intensity — the "committed, not loud" beat.
  case impactSolid(intensity: Double)
  case success
  case warning
  case error
}

extension SocCue {

  /// The `.sensoryFeedback` route, or `nil` for the cues that do not take one:
  /// `file`, `breachThud` and `rankup` are bespoke patterns (`CHPatternSpec`),
  /// `heartbeat` is a loop rather than a play, and F2a's three sound-only cues are
  /// heard and never felt (`SocCue.soundOnly`).
  ///
  /// Written as a total switch on purpose — a twenty-third cue added to `SentryCore`
  /// stops the build here instead of silently going quiet.
  var sensory: SensoryCue? {
    switch self {
    case .select, .holdTick: .selection
    case .findingLand: .impactLight
    case .commitSoft: .impactSolid(intensity: 0.7)
    case .verdictGood, .shiftClean: .success
    case .verdictOff, .shiftRough, .denied: .warning
    case .verdictWrong, .shiftBreached, .destructive: .error
    case .file, .breachThud, .rankup, .heartbeat: nil

    // ── F2a · the sequence cues (`FEEL.md` §1/§2/§4/§5/§8) ─────────────────
    // `arrive` and `ping` take `select`, which is what §1 and §2 file them under:
    // an alert landing on the rail is the same nudge as touching a row, and one
    // call site then buys both the sound and the tap the document asks for.
    case .arrive, .ping: .selection
    // The pull opening is a `select` too (§4, t=0).
    case .queryStart: .selection
    // Heard, never felt — §9 gives these a `—` in the haptic column, and the
    // reason is in each cue's own doc comment on `SocCue`.
    case .tick, .stamp, .landCard: nil
    }
  }
}

extension SensoryCue {

  /// §4.4, row for row: selection · `.impact(weight: .light)` ·
  /// `.impact(flexibility: .solid, intensity: 0.7)` · success / warning / error.
  var feedback: SensoryFeedback {
    switch self {
    case .selection: .selection
    case .impactLight: .impact(weight: .light)
    case .impactSolid(let intensity): .impact(flexibility: .solid, intensity: intensity)
    case .success: .success
    case .warning: .warning
    case .error: .error
    }
  }
}

/// The UIKit generators `.sensoryFeedback` is itself built on, kept alive between
/// cues.
///
/// Only the safety net of `SensoryRelay` reaches these — a cue fired while no screen
/// is mounted, which in the shipped app is the launch window before the first phase
/// screen appears. They are **retained** rather than constructed per cue, because a
/// generator that is thrown away cannot be prepared, and `prepare()` is the whole
/// reason the class exists: it warms the Taptic Engine so the next play is immediate
/// instead of arriving a frame or two late.
///
/// `.solid` is UIKit's `.medium`, which is also what `DESIGN.md` §2.15 specifies for
/// the web build — so the two seats agree by construction.
@MainActor private final class FeedbackGenerators {
  private let selection = UISelectionFeedbackGenerator()
  private let light = UIImpactFeedbackGenerator(style: .light)
  private let solid = UIImpactFeedbackGenerator(style: .medium)
  private let notification = UINotificationFeedbackGenerator()

  func play(_ cue: SensoryCue) {
    switch cue {
    case .selection:
      selection.prepare()
      selection.selectionChanged()
    case .impactLight:
      light.prepare()
      light.impactOccurred()
    case .impactSolid(let intensity):
      solid.prepare()
      solid.impactOccurred(intensity: intensity)
    case .success:
      notification.prepare()
      notification.notificationOccurred(.success)
    case .warning:
      notification.prepare()
      notification.notificationOccurred(.warning)
    case .error:
      notification.prepare()
      notification.notificationOccurred(.error)
    }
  }
}

/// Carries a cue from `HapticsEngine` to a `.sensoryFeedback` modifier.
///
/// `.sensoryFeedback(trigger:)` is a **view** modifier and the sink that fires cues is
/// a service with no view of its own — so the two are joined by an observable token:
/// the engine bumps it, the host observes it, SwiftUI plays it. Hosts are mounted by
/// `HapticsComposition`, which wraps every screen the app draws in
/// `.sentryHaptics(_:)`.
///
/// **A ticket names the host that must play it.** More than one host is mounted
/// whenever a sheet is up over a phase screen, or for the frame in which one phase
/// screen is replacing another — and without a target every one of them would play
/// the same cue, so the player would feel a double tap at exactly the moments the
/// game is most ceremonious. The ticket is addressed to the topmost host (the last
/// one mounted) and every other host returns `nil` from its feedback closure.
///
/// **The generator net.** When no host is mounted at all the relay plays the cue
/// itself, through `FeedbackGenerators`. That is not a second channel — exactly one
/// of the two runs for any cue — and it is deliberate rather than a workaround: the
/// window it covers is the launch frames before the first screen appears and any
/// phase for which no screen factory is installed (a bare C6 shell, a preview), and
/// dropping cues on the floor there would be a silence no trace line could explain.
/// The route is traced either way, so `-hapticTrace` always says which one ran.
@MainActor @Observable final class SensoryRelay {

  /// A cue to play, distinguished only by its serial number so that two identical
  /// cues in a row are still two events.
  struct Ticket: Equatable {
    let id: Int
    /// The host that should play it — see the class comment.
    let host: Int
    let cue: SensoryCue

    static func == (lhs: Ticket, rhs: Ticket) -> Bool { lhs.id == rhs.id }
  }

  private(set) var ticket: Ticket?
  private var serial = 0
  /// Mounted hosts in mount order; the last one is the topmost on the glass.
  private var hosts: [Int] = []
  private var nextHostID = 0
  @ObservationIgnored private let trace: HapticTrace
  @ObservationIgnored private lazy var generators = FeedbackGenerators()

  init(trace: HapticTrace) {
    self.trace = trace
  }

  /// Whether a `.sentryHaptics()` host is currently in the view tree.
  var isHosted: Bool { !hosts.isEmpty }

  /// Fire a cue. Returns `false` when the cue is not one of the twelve — the caller
  /// then knows it has a Core Haptics pattern to play instead.
  @discardableResult func fire(_ cue: SocCue) -> Bool {
    guard let sensory = cue.sensory else { return false }
    guard let host = hosts.last else {
      generators.play(sensory)
      return true
    }
    serial &+= 1
    ticket = Ticket(id: serial, host: host, cue: sensory)
    return true
  }

  /// What this host should play, or `nil` because the ticket belongs to another host.
  ///
  /// **Re-targeting** (P1-8). A ticket names the host that was topmost when the cue
  /// was fired, and between firing and playing that host can be gone — which is not a
  /// rare case but the *common* one for the cues that matter most: a sheet fires a
  /// cue on the way out (the source sheet's "To the board", the call sheet filing),
  /// and the modifier that would have played it unmounts in the same frame. The
  /// ticket was then addressed to nobody and the cue was silently lost.
  ///
  /// So a host may also claim a ticket whose named host is no longer mounted, and
  /// only if it is the topmost one — still exactly one host per ticket, so nothing
  /// doubles. When no host is mounted at all the ticket is simply not claimed: the
  /// cue is dropped, quietly, because a cue is a courtesy and a log line about a
  /// missing one is not.
  func feedback(for ticket: Ticket?, host: Int) -> SensoryFeedback? {
    guard let ticket else { return nil }
    if ticket.host == host { return ticket.cue.feedback }
    guard !hosts.contains(ticket.host), hosts.last == host else { return nil }
    return ticket.cue.feedback
  }

  /// Returns the new host's id, which it hands back on unmount.
  func hostDidMount() -> Int {
    nextHostID &+= 1
    hosts.append(nextHostID)
    trace.note("sensory host mounted #\(nextHostID) (\(hosts.count))")
    return nextHostID
  }

  func hostDidUnmount(_ id: Int) {
    hosts.removeAll { $0 == id }
    trace.note("sensory host unmounted #\(id) (\(hosts.count))")
  }
}
