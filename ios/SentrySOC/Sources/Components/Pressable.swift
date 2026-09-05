import SwiftUI

/// The pressed state, once, for every interactive primitive in the deck (§10 C7 #5).
///
/// The web deck's only tap feedback is a `hover:` class, and Tailwind v4 wraps
/// `hover:` in `@media (hover: hover)` — so on the device it renders *nothing*, and
/// a tap that missed and a tap that landed look identical (risk R11). One
/// `ButtonStyle` reading `Theme.Press` makes that structurally impossible: a row
/// cannot be built without one, because `PrimitiveRow` applies it.
///
/// The press is deliberately **not** animated through `Motion.gated`, and it is the
/// only thing in the deck that is not. A pressed state is direct manipulation — the
/// finger is on the glass and the pixel under it must move now — and Reduce Motion
/// is a vestibular setting about *travel*, not about feedback. The curve lives in
/// `Motion.pressUngated`, which carries that argument and is the single documented
/// allowance `verify.sh`'s gate grep is permitted to see; this is its only call site.
struct PressableStyle: ButtonStyle {

  /// How hard the press reads.
  enum Weight {
    /// A whole row or card: a wash, no travel. Rows are large, and scaling one
    /// makes the list beneath it look like it flinched.
    case row
    /// A control the thumb aims at: the wash plus 2 % of travel.
    case control
  }

  var weight: Weight = .row
  /// Corner radius of the press wash, so it never spills past the row it belongs to.
  var cornerRadius: CGFloat = Theme.Radius.card
  /// `false` leaves the wash off — for a row that paints its own selected fill and
  /// would otherwise wash twice.
  var showsFill: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background {
        if showsFill {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Press.fill)
            .opacity(configuration.isPressed ? 1 : 0)
        }
      }
      .scaleEffect(weight == .control && configuration.isPressed ? Theme.Press.scale : 1)
      .opacity(configuration.isPressed ? Theme.Press.opacity : 1)
      .animation(Motion.pressUngated, value: configuration.isPressed)
      .contentShape(Rectangle())
  }
}

extension View {

  /// A hit target that is never below the §2.2 floor, whatever the content measures.
  /// Applied *inside* the button label so the tappable area grows, not just the ink.
  func minimumHitTarget(height: CGFloat = Theme.Hit.minimum) -> some View {
    frame(minHeight: height)
      .contentShape(Rectangle())
  }

  /// The deck's card: panel fill, hairline, 10 pt radius. Optionally tinted by a
  /// state colour, which is how an open queue row and a selected disposition read
  /// as "this one" without a second border.
  func panelCard(
    cornerRadius: CGFloat = Theme.Radius.card,
    fill: Color = Theme.panel,
    stroke: Color = Theme.hairline,
    lineWidth: CGFloat = 1,
    dashed: Bool = false
  ) -> some View {
    background {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(fill)
    }
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(
          stroke,
          style: StrokeStyle(lineWidth: lineWidth, dash: dashed ? [4, 4] : []))
    }
  }

  /// The 3 pt leading rule that marks a verdict, a selection or an open queue
  /// (§2.3, §2.4, §2.9). Drawn inside the card's radius so the two never fight.
  func leadingRule(_ color: Color?, cornerRadius: CGFloat = Theme.Radius.card) -> some View {
    overlay(alignment: .leading) {
      if let color {
        UnevenRoundedRectangle(
          topLeadingRadius: cornerRadius, bottomLeadingRadius: cornerRadius,
          style: .continuous
        )
        .fill(color)
        .frame(width: Theme.ruleWidth)
      }
    }
  }
}
