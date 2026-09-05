import SwiftUI

/// C10's slot in the composition root (addendum **B6**).
///
/// A member declared on the concrete type beats a protocol-extension default at the
/// static call site, so `Composition.installHaptics(into:)` in `SentrySOCApp.init`
/// resolves *here* the moment this file exists — with no edit to `Composition.swift`,
/// which C6 owns. Until this file existed the same call resolved to the no-op default
/// and every cue was swallowed by `NoopHaptics`.
extension Composition {

  /// Install the sink, then **decorate the screens**.
  ///
  /// `installAll` runs `installPlay` → `installMeta` → `installHaptics`, so C8's and
  /// C9's factories are already in the registry when this runs and can be wrapped in
  /// place. The wrapper adds `.sentryHaptics(model)` to every screen and sheet those
  /// factories return, which is what puts a `.sensoryFeedback` host in the view tree
  /// (§4.4's route for twelve of the fifteen cues) and hands the engine the live
  /// `GameModel` the heartbeat driver observes.
  ///
  /// Wrapping rather than one line on `App/RootView.swift` because `Sources/App/` is
  /// C6's and C10 owns `Haptics/` alone (§11). It is behaviourally the same mount —
  /// see the request to the lead in C10's report — and if that line is ever approved,
  /// deleting the two `if let` clauses below is the whole rollback: a second host does
  /// not double a cue, because a ticket names the one host that plays it.
  static func installHaptics(into r: ScreenRegistry) {
    let engine = HapticsEngine.shared
    r.haptics = engine

    // `is` rather than a flag: `installAll` is called once by the app, and twice by a
    // test that builds its own registry — wrapping a wrapper would be harmless but
    // untidy.
    if let play = r.play, !(play is HapticsPlayScreens) {
      r.play = HapticsPlayScreens(base: play, engine: engine)
    }
    if let meta = r.meta, !(meta is HapticsMetaScreens) {
      r.meta = HapticsMetaScreens(base: meta, engine: engine)
    }

    #if DEBUG
      // Acceptance: "`Composition.installHaptics` resolves to my file, verified by a
      // DEBUG log line on install." `Composition.installAll` prints the sink's type
      // right after this; this line adds the facts that decide whether anything will
      // actually be felt.
      print(
        "[Composition] installHaptics → HapticsEngine "
          + "(supportsHaptics=\(HapticsEngine.supportsHaptics), "
          + "trace=\(engine.isTracing), "
          + "hosted play=\(r.play is HapticsPlayScreens) meta=\(r.meta is HapticsMetaScreens))")
    #endif
  }
}
