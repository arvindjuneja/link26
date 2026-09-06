import SwiftUI
import SentryCore

/// C8's slot in the composition root (SPEC-ADDENDUM **B6**, ratified by **R10**).
///
/// `Composition.installPlay(into:)` is declared on the `ScreenInstaller` protocol
/// with a no-op default; a member on the **concrete type** wins over a protocol
/// default at the static call site, so this file — inside C8's own directory —
/// replaces the no-op with zero edits to `Services/Composition.swift`.
extension Composition {

  static func installPlay(into r: ScreenRegistry) {
    r.play = PlayScreens()
    #if DEBUG
      // C8 acceptance (B6): "`Composition.installPlay` resolves to my file, verified
      // by a DEBUG log line on install". `installAll` prints the registry afterwards;
      // this line proves *which* file did the installing.
      print("[Composition] installPlay ← Screens/Play/PlayComposition.swift (C8)")
    #endif
  }
}

/// The play half of the deck: the briefing, the case, the debrief and the 16:00
/// summary, plus the board / source / call / abandon sheets.
///
/// `nil` means "not mine" (**R10**), which is how `PhaseHost` falls through to the
/// meta factory (C9) and then to a labelled placeholder. Every screen is handed the
/// model rather than reading `@Environment`, so a preview or a test can mount one
/// against its own `GameModel` without a host.
struct PlayScreens: PlayScreenFactory {

  func view(for phase: Phase, model: GameModel) -> AnyView? {
    switch phase {
    case .briefing: AnyView(ShiftIntroView(model: model))
    case .investigating: AnyView(CaseView(model: model))
    case .debrief(let readOnly): AnyView(DebriefView(model: model, readOnly: readOnly))
    case .complete: AnyView(ShiftSummaryView(model: model))
    // The desk and the rank-up beat are C9's.
    case .hub, .milestone: nil
    }
  }

  func sheet(for view: ViewID, model: GameModel) -> AnyView? {
    switch view {
    case .board: AnyView(BoardSheet(model: model))
    case .source(let sourceID, let autoPull):
      AnyView(SourceSheet(model: model, sourceID: sourceID, autoPull: autoPull).id(sourceID))
    case .call: AnyView(CallSheet(model: model))
    case .abandon: AnyView(AbandonSheet(model: model))
    case .kit, .settings, .firstRun: nil
    }
  }
}
