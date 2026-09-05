import SentryCore
import SwiftUI

/// **The fiction gate** — `DESIGN.md` §2.13; `SPEC.md` §5.11. View `.firstRun`.
///
/// A blocking `.fullScreenCover` with `interactiveDismissDisabled(true)` — both
/// applied by `PhaseHost`, which is where the cover lives. One control, and it
/// dispatches `ACK_FIRSTRUN`: the flag is written by the **reducer** through
/// `Effect.setFlag`, never by this view (Appendix A G19), which is why there is no
/// storage call anywhere in this file.
///
/// The block it prints is `copy.firstRun.body`, and the **same** block is reprinted
/// under Settings → About (§5.11). `MetaComposition` asserts in DEBUG that the two
/// exported keys have not drifted.
struct FirstRunView: View {
  let model: GameModel

  private var copy: CopyPack { model.content.copy }

  var body: some View {
    ZStack {
      Theme.ground.ignoresSafeArea()

      GeometryReader { geometry in
        ScrollView {
          // Centred while it fits, scrolling the moment it does not — which is what
          // happens at the accessibility Dynamic Type sizes, where a disclaimer that
          // clipped instead would be no disclaimer at all.
          VStack(alignment: .leading, spacing: 22) {
            Text(copy.chromeText("wordmark"))
              .trackedLabel(Theme.textTertiary)

            panel
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 22)
          .padding(.vertical, 24)
          .frame(minHeight: geometry.size.height, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
    }
    .safeAreaInset(edge: .bottom) {
      Dock(title: copy.firstRun.cta) {
        model.send(.ackFirstRun)
      }
    }
    .accessibilityIdentifier("firstRun.root")
  }

  /// The block itself, as a card with an amber rule.
  ///
  /// Amber, not rose: §2.16 spends rose on a true positive — a real threat — and a
  /// disclaimer that borrows the breach hue is claiming an authority it does not
  /// have. Amber is the deck's pressure/caution run, which is exactly what this is.
  private var panel: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(copy.firstRun.title)
        .font(Typography.screenTitle)
        .foregroundStyle(Theme.pressure)
        .fixedSize(horizontal: false, vertical: true)

      // Never clamped: a truncated disclaimer is not one.
      Text(copy.firstRun.body)
        .prose(Theme.textSecondary)
        .accessibilityIdentifier("firstRun.body")

      Rectangle()
        .fill(Theme.hairline)
        .frame(height: 1)

      Text(copy.about.privacy).quietLog()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .panelCard()
    .leadingRule(Theme.pressure)
  }
}

#Preview("FirstRun") {
  FirstRunView(model: GameModel())
}
