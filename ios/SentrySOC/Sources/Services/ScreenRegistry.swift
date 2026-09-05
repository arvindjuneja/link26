import SwiftUI
import SentryCore

/// Late binding between the shell (C6) and the screens (C8/C9) and haptics (C10),
/// per addendum **B6**.
///
/// The shell must build and run before any of those tickets exist, and none of them
/// may edit a file another ticket owns — so `PhaseHost` asks this registry for a
/// screen and draws a labelled `PlaceholderScreen` when the factory is `nil`. Each
/// later ticket fills its slot from a `*Composition.swift` inside its **own**
/// directory; nothing in `Sources/App` changes when they land.
@MainActor final class ScreenRegistry {
  static let shared = ScreenRegistry()

  /// Briefing · investigating · debrief, and the board / source / call / abandon
  /// sheets. Installed by C8.
  var play: (any PlayScreenFactory)?
  /// Hub · complete · milestone, and the settings / first-run / kit sheets.
  /// Installed by C9.
  var meta: (any MetaScreenFactory)?
  /// Installed by C10. Until then every cue is dropped, silently and safely —
  /// the Simulator has no haptics hardware anyway.
  var haptics: any HapticsSink = NoopHaptics()

  init() {}
}

/// The play screens (C8).
///
/// **Amendment requested against B6, §11.12.** The addendum's sketch types
/// `view(for:model:)` as `-> AnyView`; it is `-> AnyView?` here, because a
/// non-optional return leaves the play factory no way to say "not mine" and
/// `PhaseHost`'s play → meta → placeholder fall-through cannot be written. C8's and
/// C9's briefs need to quote the optional-returning signature.
protocol PlayScreenFactory {
  /// `nil` for a phase this factory does not own, which is how `PhaseHost` falls
  /// through to the meta factory and then to the placeholder.
  @MainActor func view(for phase: Phase, model: GameModel) -> AnyView?
  @MainActor func sheet(for view: ViewID, model: GameModel) -> AnyView?
}

/// The meta screens (C9) — same shape: hub / complete / milestone, and the
/// settings / first-run / kit overlays.
protocol MetaScreenFactory {
  @MainActor func view(for phase: Phase, model: GameModel) -> AnyView?
  @MainActor func sheet(for view: ViewID, model: GameModel) -> AnyView?
}

/// Where every cue in the app comes out (C10). One sink, so a view can never fire a
/// haptic directly and `EffectRunner` stays the only thing that decides *when*.
protocol HapticsSink {
  @MainActor func play(_ cue: SocCue)
  @MainActor func setHeartbeat(_ plan: HeartbeatPlan?)
}

/// The default sink. Not a stub to be embarrassed about: `CHHapticEngine` is absent
/// on the Simulator and on older hardware, so *something* has to swallow cues
/// without crashing, and this is it.
struct NoopHaptics: HapticsSink {
  func play(_ cue: SocCue) {}
  func setHeartbeat(_ plan: HeartbeatPlan?) {}
}
