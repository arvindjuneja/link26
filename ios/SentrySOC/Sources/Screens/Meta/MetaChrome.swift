import SentryCore
import SwiftUI

/// The four pieces of chrome the meta screens share, and nothing else.
///
/// `Sources/Components/` is C7's, so a primitive that only the desk needs lives here
/// rather than in the kit: a labelled block, a settings row, the cold-glass ground and
/// two copy helpers. None of them authors a string.

// MARK: - Ground

/// The hub's cold glass — a **static** `MeshGradient` (iOS 18, D14), not a stack of
/// blurs (§5.1).
///
/// Static is deliberate: §2.14's budget rule bans idle decorative motion, so this is a
/// gradient that happens to be a mesh, spending its four extra control points on a
/// faint cyan bloom under the system bar and an emerald one behind the queue rules —
/// the two hues the desk is denominated in. Everything is drawn from `Theme`, at
/// opacities low enough that the ground still reads as `#010409`.
struct DeskGround: View {
  var body: some View {
    MeshGradient(
      width: 3, height: 3,
      points: [
        .init(0, 0), .init(0.5, 0), .init(1, 0),
        .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
        .init(0, 1), .init(0.5, 1), .init(1, 1),
      ],
      colors: [
        Theme.falsePositive.opacity(0.10), Theme.falsePositive.opacity(0.05), Theme.ground,
        Theme.ground, Theme.ground, Theme.ground,
        Theme.ground, Theme.benign.opacity(0.02), Theme.benign.opacity(0.04),
      ])
      .background(Theme.ground)
      .ignoresSafeArea()
      .accessibilityHidden(true)
  }
}

// MARK: - Blocks and rows

/// A labelled block: the 11 pt tracked eyebrow of every hub and settings section,
/// with its content under it. The eyebrow's text always comes from `copy.chrome`.
struct MetaSection<Content: View>: View {
  let eyebrow: String
  var tone: Color = Theme.textQuiet
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(eyebrow).trackedLabel(tone)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// One row of a settings panel: a title and whatever control sits on the trailing
/// edge. 44 pt floor (§2.2), hairline-separated by the panel.
struct MetaRow<Trailing: View>: View {
  let title: String
  var titleColor: Color = Theme.textSecondary
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(title)
        .font(Typography.meta)
        .foregroundStyle(titleColor)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 10)
      trailing
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(minHeight: Theme.Hit.minimum)
  }
}

extension MetaRow where Trailing == EmptyView {
  init(title: String, titleColor: Color = Theme.textSecondary) {
    self.init(title: title, titleColor: titleColor) { EmptyView() }
  }
}

/// The panel a group of `MetaRow`s sits in — one card, hairlines between the rows, so
/// a section reads as one object rather than as a stack of chips (§2.13).
struct MetaPanel<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .panelCard()
  }
}

/// The hairline between two rows inside a `MetaPanel`.
struct MetaDivider: View {
  var body: some View {
    Rectangle()
      .fill(Theme.hairline)
      .frame(height: 1)
      .padding(.leading, 14)
      .accessibilityHidden(true)
  }
}

// MARK: - Copy helpers

extension CopyPack {

  /// A `Dock` title from a chrome key that already ends in `▸`.
  ///
  /// The exported CTAs were lifted from the web, where the caret is part of the
  /// string (`rankUpContinue` = `Continue ▸`, `summaryBack`, `debriefNext`). `Dock`
  /// draws its own caret, so handing it one of those renders `Continue ▸ ▸`. This
  /// trims exactly the deck's own forward glyph and nothing else — no words are
  /// touched, and a key that never carried a caret passes through unchanged.
  func dockTitle(_ key: String) -> String {
    var text = chromeText(key)
    while text.hasSuffix(Glyph.forward) || text.hasSuffix(" ") {
      text.removeLast()
    }
    return text
  }

  /// A board's name without its subtitle — `Shift 2 · phishing · identity · EDR ·
  /// exfil` → `Shift 2`.
  ///
  /// §2.3's Dock reads `Clock in · Shift 2 ▸`, and the exported labels carry the
  /// whole billing after a middot. The queue rows show the full label, because that
  /// is where a player chooses; the 56 pt CTA shows the name, because that is where
  /// they commit and a five-clause title wraps the thumb arc onto two lines.
  static func shortLabel(_ label: String) -> String {
    guard let head = label.split(separator: "·").first else { return label }
    return head.trimmingCharacters(in: .whitespaces)
  }
}
