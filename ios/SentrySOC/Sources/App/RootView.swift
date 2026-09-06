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
    .overlay(alignment: .topTrailing) { sequenceClock }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(Typography.dynamicTypeRange)
    .tint(Theme.falsePositive)
    .onChange(of: scenePhase) { _, phase in
      model.scenePhaseChanged(to: phase)
    }
  }

  /// **The stopwatch a frame strip is read against** (`FEEL.md` §11, F2b).
  ///
  /// `record.sh` cuts a 100 ms grid, and §11 asks for ±60 ms — which a grid alone
  /// cannot settle, because frame 12 is "somewhere in the 100 ms after the eleventh".
  /// So under `SENTRY_QA` (Debug only, and the release guard proves its absence) the
  /// running sequence prints its own elapsed milliseconds in the corner. A reviewer
  /// reads the beat and the clock off the same pixel row and the tolerance becomes a
  /// measurement.
  ///
  /// It is `TimelineView(.periodic)` rather than a `Task`: this is the one thing in
  /// the app that legitimately wants a frame clock, it exists only in QA builds, and
  /// it must not touch the Director's own scheduling to read it.
  @ViewBuilder private var sequenceClock: some View {
    #if SENTRY_QA
      if model.director.isPlaying {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
          Text(model.director.elapsedMs.map { "\($0)" } ?? "")
            .font(Typography.gradeNumeral)
            .foregroundStyle(Theme.crossover)
            .padding(.horizontal, 8)
            .background(Theme.scrim.opacity(0.85))
            .padding(.top, 52)
            .padding(.trailing, 6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
    #endif
  }
}
