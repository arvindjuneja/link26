import SwiftUI

/// The thumb arc's one primary action — `DESIGN.md` §2.2, §2.3, §2.6, §2.8.
///
/// Mounted by every screen with `.safeAreaInset(edge: .bottom)`, which is the
/// idiomatic replacement for the web's fixed dock (§4.2): scrolling content gets the
/// correct inset for free and the home indicator is handled by the system. Nothing
/// else in the deck is allowed to be a primary action, and nothing primary is
/// allowed to live above y≈560.
///
/// The disabled state is 40 % opacity and **still present** (§5.4) — the CTA never
/// disappears, because a control that vanishes teaches the player nothing about why
/// they cannot press it. The hint on the trailing edge carries the reason
/// (`investigate first`), and it is the same slot that later carries the reward
/// (`3 findings · 26m`).
struct Dock: View {
  /// **Without a trailing caret.** The Dock draws `▸` itself, so a chrome key that
  /// already ends in one (`hubStart`, `intro.cta`, `boardOpenAlert`, `summaryBack`)
  /// renders it twice. The keys a Dock takes are the caret-free ones —
  /// `makeTheCall`, `dockClockIn`, `dockResume`, `close`.
  let title: String
  /// The trailing read-out: the blocker before, the state after.
  var hint: String?
  var tone: Color = Theme.benign
  var isEnabled: Bool = true
  /// The 11 pt fiction disclaimer that sits under the briefing's CTA (§2.4) and is
  /// always visible there.
  var disclaimer: String?
  let action: () -> Void

  var body: some View {
    VStack(spacing: 10) {
      Button(action: action) {
        HStack(spacing: 10) {
          Text(title)
            .font(Typography.rowTitle)
            .foregroundStyle(tone)
          Text(Glyph.forward)
            .font(Typography.meta)
            .foregroundStyle(tone)

          Spacer(minLength: 12)

          if let hint {
            Text(hint)
              .font(Typography.meta)
              .tabularNumbers()
              .foregroundStyle(Theme.textQuiet)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: Theme.Hit.primaryCTA)
        .background {
          RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(tone.opacity(0.10))
        }
        .overlay {
          RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(tone.opacity(0.45), lineWidth: 1)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(PressableStyle(weight: .control, showsFill: false))
      .disabled(!isEnabled)
      .opacity(isEnabled ? 1 : 0.40)
      .accessibilityIdentifier("dock.cta")

      if let disclaimer {
        Text(disclaimer)
          .quietLog(Theme.textQuiet)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 10)
    .padding(.bottom, 6)
    .background(dockGround)
  }

  /// The dock floats over the scroll region, so the last row of content has to fade
  /// out under it rather than collide with it.
  private var dockGround: some View {
    LinearGradient(
      colors: [Theme.ground.opacity(0), Theme.ground.opacity(0.92), Theme.ground],
      startPoint: .top, endPoint: .bottom)
      .allowsHitTesting(false)
  }
}

#Preview("Dock · armed, blocked, briefing") {
  VStack(spacing: 26) {
    Dock(title: "Make the call", hint: "3 findings · 26m", action: {})

    Dock(
      title: "Make the call", hint: "investigate first", isEnabled: false, action: {})

    Dock(title: "Open alert 3", tone: Theme.falsePositive, action: {})

    Dock(
      title: "Start the shift",
      disclaimer:
        "Fiction simulator — every log line is fabricated; it teaches the analyst's read, never a working technique.",
      action: {})
  }
  .padding(.vertical, 24)
  .frame(width: 390)
  .background(Theme.ground)
}
