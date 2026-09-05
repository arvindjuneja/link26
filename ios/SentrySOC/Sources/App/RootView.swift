import SwiftUI

/// The single window. Paints the ground, clamps Dynamic Type, and hands off to
/// `PhaseHost`.
///
/// There is **no `NavigationStack` around the shift loop** (D16): a stack hands the
/// player an interactive swipe-back out of a completed debrief into the call sheet,
/// which breaks both the ceremony and the one-call-per-case guarantee.
/// `NavigationStack` appears in exactly one place in this app — inside Settings,
/// where swipe-back is the right answer.
struct RootView: View {
  @Environment(GameModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ZStack {
      // The same colour as the `LaunchGround` asset, so the native splash and the
      // first frame are indistinguishable and the launch has no seam.
      Theme.ground.ignoresSafeArea()

      PhaseHost()
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(Typography.dynamicTypeRange)
    .tint(Theme.falsePositive)
    .onChange(of: scenePhase) { _, phase in
      model.scenePhaseChanged(to: phase)
    }
  }
}
