import Foundation

/// Everything a player can ask for (`DESIGN.md` §2.1 + Appendix A §C).
///
/// **Seventeen**: the fifteen of §2.1, minus `CONTINUE` (G6), plus `VIEW_RESULT`
/// (G5) and `ACK_FIRSTRUN` (G19). A view expresses one of these and nothing else —
/// it never writes storage, never fires a haptic and never touches a meter.
public enum SocAction: Sendable, Hashable {
  /// Boot. The session the app hands the reducer already carries the first-run gate
  /// (the reducer cannot read `UserDefaults`), so this is the seam for anything the
  /// launch has to settle, not a mutation.
  case hydrate
  /// Open a board by id — campaign or today's daily. Guarded by `isUnlocked`.
  case startShift(String)
  case begin
  /// **Documented deviation from `SPEC.md` §3.3, ratified by SPEC-ADDENDUM R9.**
  /// The spec types this `case resume` with no payload, which forces whoever holds
  /// the snapshot to assign `session` behind the reducer's back — the one thing
  /// `send(_:)` being the single entry point exists to prevent. The restored state
  /// travels as the payload instead, so a restore is a transition like any other.
  case resume(SessionState)
  case openView(ViewID)
  case closeView
  case pullSource(String)
  case pickDisposition(Disposition)
  case makeCall(Disposition)
  case nextCase
  /// G5 — re-read a filed call from the board's done rows or the summary's glyphs.
  case viewResult(String)
  case ackMilestone
  /// G19 — the disclaimer was acknowledged. Components never write storage.
  case ackFirstRun
  case toHub
  case abandon
  case buy(String)
  case setSetting(SettingKey, Bool)

  /// The seventeen, for the acceptance test that counts them. Payload cases carry a
  /// representative value; only the *shape* is being enumerated. Deliberately
  /// **internal** — it is a checklist for `SessionTests`, not API for a screen.
  static func allCaseShapes(sample session: SessionState = .atHub) -> [SocAction] {
    [
      .hydrate, .startShift(""), .begin, .resume(session), .openView(.board), .closeView,
      .pullSource(""), .pickDisposition(.closeFalsePositive), .makeCall(.closeFalsePositive),
      .nextCase, .viewResult(""), .ackMilestone, .ackFirstRun, .toHub, .abandon, .buy(""),
      .setSetting(.haptics, true),
    ]
  }
}

/// The three player-controlled switches, as a key the reducer can carry without
/// knowing what storage is. The raw values are the `UserDefaults` keys (§4.3).
public enum SettingKey: String, Codable, Sendable, Hashable, CaseIterable {
  case haptics = "sentry.haptics"
  case holdToFile = "sentry.holdToFile"
  case coaching = "sentry.coaching"
}

/// The two one-shot gates the reducer names. The other three launch-critical flags
/// are `SettingKey` raw values; together they are the five of §4.3 and no more.
public enum SentryFlagKey {
  /// The disclaimer has been acknowledged (G19).
  public static let firstRun = "sentry.firstRun.v1"
  /// The Shift-1 coach has been through once.
  public static let onboarding = "sentry.onboarding.v1"
}
