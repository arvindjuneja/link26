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

// MARK: - The ladder

/// `●────●────○────○` — the rank ladder of `DESIGN.md` §2.12, built from the
/// exported ranks so it can never disagree with `CareerRules.rankFor`.
///
/// **Why this is not `Components/LadderTrack`, and the defect that is filed against
/// it.** C7's `LadderTrack` lays four rungs in an `HStack(spacing: 0)` and puts the
/// `.frame(maxWidth: .infinity)` on the *labels* rather than on the columns, so each
/// column sizes to its own text and two full-width neighbours touch: on the shipped
/// ladder it renders `Tier-1 · SeniorTier-2 · candidate` as one run of words, which
/// is what the rank-up screenshot caught. Neither a trailing space nor a NO-BREAK
/// SPACE fixes it (CoreText trims both at a line end) and no outer width makes all
/// four columns clear at once. The fix belongs in the component — a gutter on the
/// `HStack` and the flexible frame moved to the column — and until it lands this is
/// the same track with those two lines right. Delete it when `LadderTrack` gains a
/// gutter; the call site is one initialiser away.
struct RankLadder: View {
  struct Rung: Identifiable {
    let id: String
    let label: String
    /// `0`, `40`, `150`, `210` — formatted by the screen.
    let threshold: String
    let held: Bool
  }

  let rungs: [Rung]
  var tone: Color = Theme.benign

  private let gutter: CGFloat = 10

  var body: some View {
    HStack(alignment: .top, spacing: gutter) {
      ForEach(Array(rungs.enumerated()), id: \.element.id) { index, rung in
        VStack(alignment: .leading, spacing: 6) {
          ZStack(alignment: .leading) {
            if index < rungs.count - 1 {
              Rectangle()
                .fill(rungs[index + 1].held ? tone.opacity(0.6) : Theme.Zinc.z700)
                .frame(height: 1)
                .padding(.leading, 9)
                // Into the gutter, so the track reads as one line rather than as
                // four dashes.
                .padding(.trailing, -gutter)
            }
            Text(rung.held ? Glyph.standingFilled : Glyph.standingEmpty)
              .font(Typography.meta)
              .foregroundStyle(rung.held ? tone : Theme.textDisabled)
          }
          .frame(height: 16)

          // Two lines reserved whether or not the rung needs them, so every
          // threshold sits on one baseline instead of stepping with the labels.
          Text(rung.label)
            .font(Typography.quietLog)
            .foregroundStyle(rung.held ? Theme.textSecondary : Theme.textDisabled)
            .lineLimit(2, reservesSpace: true)
            .minimumScaleFactor(0.85)

          Text(rung.threshold)
            .font(Typography.quietLog)
            .tabularNumbers()
            .foregroundStyle(Theme.textDisabled)
        }
        // The flexible frame belongs HERE — on the column — which is the whole
        // difference between four equal rungs and four rungs that touch.
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .accessibilityElement(children: .combine)
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
