import SwiftUI

/// The composition root, per addendum **B6**.
///
/// `SentrySOCApp.init` calls all three installers. Today they resolve to the
/// protocol's no-op defaults, so the app builds and runs with no other ticket
/// present. When C8, C9 and C10 land, each adds a concrete-type extension **from
/// its own directory**:
///
/// ```swift
/// // Screens/Play/PlayComposition.swift          (C8)
/// extension Composition {
///   static func installPlay(into r: ScreenRegistry) { r.play = PlayScreens() }
/// }
/// ```
///
/// A member declared on the concrete type wins over a protocol-extension default at
/// the static call site, so the shell picks the real installer up with **zero edits
/// to this file** — which is what keeps the §10 file ownership genuinely disjoint.
enum Composition {}

protocol ScreenInstaller {
  static func installPlay(into r: ScreenRegistry)
  static func installMeta(into r: ScreenRegistry)
  static func installHaptics(into r: ScreenRegistry)
}

extension ScreenInstaller {
  static func installPlay(into r: ScreenRegistry) {}
  static func installMeta(into r: ScreenRegistry) {}
  static func installHaptics(into r: ScreenRegistry) {}
}

extension Composition: ScreenInstaller {}

extension Composition {

  /// Called once, from `SentrySOCApp.init`.
  static func installAll(into registry: ScreenRegistry = .shared) {
    installPlay(into: registry)
    installMeta(into: registry)
    installHaptics(into: registry)
    #if DEBUG
      // C8/C9/C10 acceptance: "`Composition.installX` resolves to my file, verified
      // by a DEBUG log line on install".
      print(
        """
        [Composition] play=\(registry.play.map { String(describing: type(of: $0)) } ?? "none") \
        meta=\(registry.meta.map { String(describing: type(of: $0)) } ?? "none") \
        haptics=\(String(describing: type(of: registry.haptics)))
        """)
    #endif
  }
}
