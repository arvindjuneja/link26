import SwiftUI
import SentryCore

extension View {

  /// Everything the haptics service needs from the view tree, in one modifier.
  ///
  /// It does the two things a service cannot do for itself:
  ///
  /// 1. hosts `.sensoryFeedback`, which is a view modifier, for the twelve cues of
  ///    §4.4 that route through it;
  /// 2. hands the engine the live `GameModel`, which is what the heartbeat driver
  ///    observes (`HeartbeatDriver`, in `HeartbeatPlayer.swift`).
  ///
  /// **Who mounts it.** `HapticsComposition` wraps the screen factories C8 and C9
  /// installed, so every screen the app draws carries it and no file outside
  /// `Haptics/` had to change (§11: C10 owns `Haptics/` and nothing else). It is
  /// idempotent and safe to apply anywhere — a second host does not double a cue,
  /// because a ticket names the one host that plays it (`SensoryRelay`) — so if the
  /// lead ever puts `.sentryHaptics(model)` on `RootView` instead, the wrapping can
  /// simply be dropped.
  ///
  /// The heartbeat is deliberately **not** driven from here. A view modifier lives
  /// and dies with the screen it is on, and the loop must survive a phase change and
  /// a sheet; the driver is an observer on the model with no view lifetime at all.
  func sentryHaptics(_ model: GameModel, engine: HapticsEngine = .shared) -> some View {
    engine.attach(model)
    return modifier(SentryHapticsHost(relay: engine.sensory))
  }
}

/// The `.sensoryFeedback` half. A serial-numbered ticket on an observable relay is
/// what lets a service fire a modifier: SwiftUI needs an `Equatable` trigger, and
/// two identical cues in a row still have to be two events.
///
/// The host registers on appear and takes an id back; the relay addresses each ticket
/// to exactly one id, so a sheet over a screen — two live hosts — still plays one tap.
struct SentryHapticsHost: ViewModifier {
  let relay: SensoryRelay

  @State private var hostID: Int?

  func body(content: Content) -> some View {
    content
      .sensoryFeedback(trigger: relay.ticket) { _, ticket in
        guard let hostID else { return nil }
        return relay.feedback(for: ticket, host: hostID)
      }
      .onAppear {
        guard hostID == nil else { return }
        hostID = relay.hostDidMount()
      }
      .onDisappear {
        guard let hostID else { return }
        relay.hostDidUnmount(hostID)
        self.hostID = nil
      }
  }
}

/// The C8 factory, with a haptics host on every screen it returns.
///
/// `Composition.installAll` runs `installPlay` → `installMeta` → `installHaptics`, so
/// by the time C10 installs, whatever C8 and C9 registered is sitting in the registry
/// waiting to be decorated. Wrapping is the only way to reach the view tree from
/// inside `Haptics/`: the alternative is one line in `App/RootView.swift`, which is
/// C6's file (see the request to the lead in C10's report).
///
/// `nil` in, `nil` out — the fall-through play → meta → placeholder that `PhaseHost`
/// depends on (R10) must survive the wrapping untouched.
///
/// **The wrapping stays, on purpose** (P1-8). The obvious tidy is one
/// `.sentryHaptics(model)` on `RootView` instead of a decorator around two factories,
/// and it is the wrong trade: `RootView` hosts the phase, and a **sheet** presented
/// over it is a separate presentation with its own view tree, so a single host on the
/// root would leave every sheet — the source pull, the call, the kit — unhosted, and
/// their cues would fall through to `SensoryRelay`'s generator net rather than to the
/// thing under the player's thumb. Decorating both factories is what puts a host on
/// each presentation, and `SensoryRelay` addresses a ticket to exactly one of them, so
/// two live hosts still play one tap. The cost is a `AnyView` per screen build, which
/// is what `AnyView` costs; the benefit is that the cue comes from the surface the
/// player is touching.
struct HapticsPlayScreens: PlayScreenFactory {
  let base: any PlayScreenFactory
  let engine: HapticsEngine

  func view(for phase: Phase, model: GameModel) -> AnyView? {
    guard let view = base.view(for: phase, model: model) else { return nil }
    return AnyView(view.sentryHaptics(model, engine: engine))
  }

  /// Sheets get a host too, and it is the one that plays: a presented sheet is the
  /// topmost host, so the tap comes from the thing under the player's thumb.
  func sheet(for view: ViewID, model: GameModel) -> AnyView? {
    guard let sheet = base.sheet(for: view, model: model) else { return nil }
    return AnyView(sheet.sentryHaptics(model, engine: engine))
  }
}

/// The C9 factory, decorated exactly as `HapticsPlayScreens` decorates C8's.
struct HapticsMetaScreens: MetaScreenFactory {
  let base: any MetaScreenFactory
  let engine: HapticsEngine

  func view(for phase: Phase, model: GameModel) -> AnyView? {
    guard let view = base.view(for: phase, model: model) else { return nil }
    return AnyView(view.sentryHaptics(model, engine: engine))
  }

  func sheet(for view: ViewID, model: GameModel) -> AnyView? {
    guard let sheet = base.sheet(for: view, model: model) else { return nil }
    return AnyView(sheet.sentryHaptics(model, engine: engine))
  }
}
