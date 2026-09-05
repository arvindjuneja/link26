import SentryCore
import SwiftUI

/// The meta half of the deck, bound to the shell from **this** directory (B6/R10).
///
/// `Composition.installMeta(into:)` is a protocol-extension no-op until a
/// concrete-type extension shadows it; the extension at the bottom of this file is
/// that shadow, so the shell picks the real factory up with zero edits to
/// `Sources/Services/` or `Sources/App/`.
///
/// **What is mine and what is not.** Phases `.hub` and `.milestone`, and the `.kit` /
/// `.settings` / `.firstRun` overlays. `.complete` — the 16:00 shift summary — moved
/// to C8 with `ShiftSummaryView` (addendum B6/§3), so this factory returns `nil` for
/// it and `PhaseHost` falls through to the play factory. Returning `nil` rather than
/// a placeholder is the whole point of R10's optional signature.
struct MetaScreens: MetaScreenFactory {

  func view(for phase: Phase, model: GameModel) -> AnyView? {
    switch phase {
    case .hub: AnyView(HubView(model: model))
    case .milestone: AnyView(RankUpView(model: model))
    // `.complete` is C8's ShiftSummaryView; the play phases were never mine.
    case .briefing, .investigating, .debrief, .complete: nil
    }
  }

  func sheet(for view: ViewID, model: GameModel) -> AnyView? {
    switch view {
    case .kit: AnyView(KitSheet(model: model))
    case .settings: AnyView(SettingsView(model: model))
    case .firstRun: AnyView(FirstRunView(model: model))
    case .board, .source, .call, .abandon: nil
    }
  }
}

extension Composition {

  /// Shadows the protocol default. Concrete beats protocol at the static call site in
  /// `SentrySOCApp.init`, which is what keeps §10's ownership genuinely disjoint.
  static func installMeta(into r: ScreenRegistry) {
    r.meta = MetaScreens()

    #if DEBUG
      // C9 acceptance: "`Composition.installMeta` resolves to my file, verified by a
      // DEBUG log line on install". `Composition.installAll` prints the resolved type
      // as well; this line names the file, which is the half a type name cannot.
      print("[Composition] installMeta ← Screens/Meta/MetaComposition.swift")

      // C9 #5: the first-run block and the About screen's fiction block are "the same
      // block", grep-enforced. Both screens draw their own key — `copy.firstRun.body`
      // and `copy.about.fiction` — so the enforcement that actually holds is this one:
      // if the exporter ever lets the two drift, a Debug launch says so on the spot,
      // rather than the disclaimer quietly saying two different things in two places.
      let copy = ContentPack.bundled.copy
      assert(
        copy.about.fiction == copy.firstRun.body,
        "copy.about.fiction and copy.firstRun.body have drifted — §5.11 requires the "
          + "SAME disclaimer block on the first-run gate and under Settings → About")
    #endif
  }
}
