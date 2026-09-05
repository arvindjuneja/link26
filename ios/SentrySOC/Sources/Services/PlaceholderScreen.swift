import SwiftUI

/// What `PhaseHost` draws when no factory has claimed a phase or a sheet (B6).
///
/// It is developer chrome, not player-facing copy, and it is labelled on purpose:
/// an unlabelled blank screen in a screenshot is indistinguishable from a crash, a
/// black launch image, or a layout that collapsed. This one says which slot is
/// empty and which ticket fills it.
struct PlaceholderScreen: View {
  let name: String
  var owner: String?
  /// Set when the placeholder stands in for a screen the player could not otherwise
  /// leave — `FirstRun` is a `.fullScreenCover` with `interactiveDismissDisabled`,
  /// so without this the shell traps itself on a fresh install until C9 lands.
  var dismiss: (() -> Void)?

  init(name: String, owner: String? = nil, dismiss: (() -> Void)? = nil) {
    self.name = name
    self.owner = owner
    self.dismiss = dismiss
  }

  var body: some View {
    ZStack {
      Theme.ground.ignoresSafeArea()

      VStack(spacing: 18) {
        Text(Glyph.standingEmpty)
          .font(Typography.grade)
          .foregroundStyle(Theme.falsePositive.opacity(0.55))

        Text("Screen pending")
          .trackedLabel(Theme.textQuiet)

        Text(name)
          .font(Typography.screenTitle)
          .foregroundStyle(Theme.textPrimary)
          .multilineTextAlignment(.center)

        if let owner {
          Text(owner)
            .font(Typography.meta)
            .foregroundStyle(Theme.textTertiary)
        }

        if let dismiss {
          Button("Continue \(Glyph.forward)", action: dismiss)
            .font(Typography.meta)
            .foregroundStyle(Theme.falsePositive)
            .frame(minHeight: Theme.Hit.minimum)
            .accessibilityIdentifier("placeholder.dismiss")
        }
      }
      .padding(.horizontal, 28)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 34)
      .background(
        RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
          .fill(Theme.panel)
          .stroke(Theme.hairline, lineWidth: 1))
      .padding(.horizontal, 24)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Placeholder for \(name)")
  }
}

#Preview("Placeholder") {
  PlaceholderScreen(name: "Case — the read", owner: "Screens/Play · C8")
}
