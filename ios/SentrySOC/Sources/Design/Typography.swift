import SwiftUI
import UIKit

/// The type system — `DESIGN.md` §2.16, `SPEC.md` §4.5.
///
/// **Two voices.** IBM Plex Mono is the machine: labels, numbers, detection rules,
/// asset strings, chips, ECG readouts, log-like evidence details, the stamp. Space
/// Grotesk is the human: alert titles, trigger prose, `why`, `learn`, Vale's
/// messages, headlines.
///
/// Every face goes through `Font.custom(_:size:relativeTo:)`, so the custom faces
/// scale with Dynamic Type instead of pinning the deck at one size. This file and
/// `Theme.swift` are the only places a font name may appear (§4.6).
///
/// The six registered faces and their provenance are in
/// `ios/SentrySOC/Resources/FONTS.md`; `FontRegistrationTests` asserts every name
/// below resolves, because the failure mode is a *silent* fallback to system-ui (R8).
nonisolated enum Typography {

  // ── the registered faces ───────────────────────────────────────────────────

  /// PostScript names, exactly as the TTFs register them.
  ///
  /// **Six faces, and every one of them is used by a step below.** A face that no
  /// step calls is dead weight registered at launch and shipped in the bundle, so
  /// the roster and the scale are kept in lockstep deliberately: three machine
  /// weights (regular · medium · semibold) and three human ones (regular · medium ·
  /// bold). `SPEC.md` §6 names `SpaceGrotesk-SemiBold`, which **does not exist**
  /// upstream — `.../space-grotesk/2.0.0/fonts/ttf/static/SpaceGrotesk-SemiBold.ttf`
  /// is a 404 while `-Medium` and `-Bold` are 200 — so Bold stands in for it as the
  /// heavy human cut. Reported to the lead as an amendment to the §6 roster.
  enum Mono: String {
    case regular = "IBMPlexMono-Regular"
    case medium = "IBMPlexMono-Medium"
    case semibold = "IBMPlexMono-SemiBold"
  }

  enum Grotesk: String {
    case regular = "SpaceGrotesk-Regular"
    case medium = "SpaceGrotesk-Medium"
    case bold = "SpaceGrotesk-Bold"
  }

  /// Every face the bundle registers — the `FontRegistrationTests` roster and the
  /// DEBUG launch assertion's roster, so the two can never drift.
  ///
  /// `FontRegistrationTests` asserts this set equals `UIAppFonts`, so a face added
  /// to `project.yml` and to `Resources/` without a case above fails the suite. The
  /// other half of the bargain — at least one step of the scale per case — is held
  /// by the cases themselves: there are six faces, and the ten-step scale below
  /// calls every one of them (`Resources/FONTS.md` carries the face → step table;
  /// C6/C11 refresh it in the pass that closes R11).
  static let registeredFaceNames: [String] =
    [Mono.regular, .medium, .semibold].map(\.rawValue)
    + [Grotesk.regular, .medium, .bold].map(\.rawValue)

  // ── the two builders ───────────────────────────────────────────────────────

  static func mono(
    _ size: CGFloat, _ face: Mono = .regular, relativeTo style: Font.TextStyle = .body
  ) -> Font {
    .custom(face.rawValue, size: size, relativeTo: style)
  }

  static func grotesk(
    _ size: CGFloat, _ face: Grotesk = .regular, relativeTo style: Font.TextStyle = .body
  ) -> Font {
    .custom(face.rawValue, size: size, relativeTo: style)
  }

  // ── the seven-step scale ───────────────────────────────────────────────────

  /// 11 pt — **the hard floor**. Tracked uppercase eyebrow. Bound to `.caption2` so
  /// it still grows with Dynamic Type, and paired with `.minimumScaleFactor(0.9)` at
  /// the call site via `trackedLabel()`.
  ///
  /// The ~42 nodes the web draws at 8.8–9.9 px are **not** ported: they were the
  /// desktop grid's compromise and they are unreadable in the hand.
  static let label = mono(11, .medium, relativeTo: .caption2)
  /// `.18em` at 11 pt.
  static let labelTracking: CGFloat = 11 * 0.18

  /// 13 pt — meta, log lines, costs, chips.
  static let meta = mono(13, .regular, relativeTo: .footnote)
  /// 13 pt, heavier — a chip that has to hold its own against a rule name.
  static let metaStrong = mono(13, .medium, relativeTo: .footnote)

  /// **R11's quiet log / meta step.** The machine voice turned all the way down:
  /// the meter fear captions (§2.5), the coverage line, a pulled source's spent
  /// cost — text that must be legible without ever competing with the alert.
  ///
  /// **Divergence, reported to the lead.** R11 binds this step to **IBM Plex Mono
  /// Light**, which is *not* in the bundle: C6 shipped Regular / Medium / SemiBold
  /// (see `Resources/FONTS.md`, `project.yml` `UIAppFonts`), and both files are
  /// outside C7's ownership — `Resources/` is C6's and `project.yml` is frozen
  /// (§11 rule 6). Declaring a `Mono.light` case here without the TTF would resolve
  /// through `Font.custom` to a **silent** system-ui fallback, which is exactly the
  /// failure mode `FontRegistrationTests` exists to catch (R8/X10). So the step is
  /// real and named, and it earns its quiet from size and colour (`quietLog()`
  /// below) rather than from weight, until the Light face is added.
  static let quietLog = mono(11, .regular, relativeTo: .caption2)

  /// 13 pt in the **human** voice — the missing half of the meta step. Two
  /// wireframes need it and neither can use `meta`: a source's question (§2.6,
  /// "13 pt Grotesk italic") and a disposition's subtitle (§2.9, "13 pt zinc-500").
  /// A question set in the machine voice reads as another log label, which is
  /// exactly the confusion the source rows exist to remove.
  static let metaProse = grotesk(13, .regular, relativeTo: .footnote)

  /// **R11's grade numeral.** The heaviest machine cut at the hero step: the four
  /// `StatTile` figures and the payout at 16:00 (§2.11 — "28 pt mono tabular").
  /// Pairs with `stamp`, so Plex SemiBold carries two steps rather than one and no
  /// registered face is dead weight.
  static let gradeNumeral = mono(28, .semibold, relativeTo: .title2)

  /// The verdict stamp (§2.16 puts the stamp in the machine voice, C7 draws it).
  /// The heaviest mono cut, because it lands once per call and has to read as
  /// pressed into the page rather than typed onto it.
  static let stamp = mono(15, .semibold, relativeTo: .body)

  /// 15 pt / 1.55 — prose. The human voice.
  static let body = grotesk(15, .regular, relativeTo: .body)
  /// 15 pt — the same step in the machine voice, for evidence detail and raw log.
  static let bodyMono = mono(15, .regular, relativeTo: .body)

  /// The 1.55 line height of the body step, as the extra leading SwiftUI wants.
  ///
  /// **Corrected against the rendered screenshots (C7).** `.lineSpacing(_:)` is
  /// *additive* — it is the gap **between** line boxes, not the line height — so
  /// `15 × 0.55 = 8.25` stacked on top of the face's own leading and shipped a
  /// ~1.8 line height, not the 1.55 §2.16 asks for. Visible in every prose block:
  /// a three-line coach bubble read as six lines of air.
  ///
  /// 1.55 × 15 = 23.25 pt total, against a rendered Grotesk line box of ≈19.1 pt,
  /// leaves ≈4.1 pt of added leading. The arithmetic is the same at any step:
  /// `lineSpacing(forSize:ratio:)`.
  static let bodyLineSpacing: CGFloat = lineSpacing(forSize: 15, ratio: 1.55)

  /// Extra leading that lands a **total** line height of `ratio × size` for the
  /// Grotesk cuts. Never negative: a ratio tighter than the face's own line box
  /// cannot be expressed through `lineSpacing`, and clamping is better than a
  /// silent overlap.
  static func lineSpacing(forSize size: CGFloat, ratio: CGFloat) -> CGFloat {
    max(0, size * ratio - groteskLineHeight(atSize: size))
  }

  /// The Grotesk body face's **rendered** line box at `size`, asked of the font
  /// itself rather than transcribed from its `hhea` table.
  ///
  /// A hand-typed em constant is the one thing this file is not allowed to be: the
  /// value that shipped before (1.257, read off `984/−273` per 1000 upem) is 1.5 %
  /// under what CoreText actually lays out (`UIFont(name:size:).lineHeight` is
  /// 19.14 pt at 15 pt → 1.276 em), which quietly put the body at 1.569 × instead of
  /// §2.16's 1.55 ×. `groteskFallbackRatio` is only reached if the face is not
  /// registered in the process — in which case the deck has a much louder problem,
  /// which `FontRegistrationTests` fails on.
  private static func groteskLineHeight(atSize size: CGFloat) -> CGFloat {
    UIFont(name: Grotesk.regular.rawValue, size: size)?.lineHeight
      ?? size * groteskFallbackRatio
  }

  /// The measured ratio, used only when the face has not registered.
  private static let groteskFallbackRatio: CGFloat = 1.276

  /// 17 pt — a list-row title.
  static let rowTitle = grotesk(17, .medium, relativeTo: .headline)

  /// 22 pt — a screen title.
  static let screenTitle = grotesk(22, .medium, relativeTo: .title3)

  /// 28 pt — a hero number, a rank.
  static let hero = grotesk(28, .medium, relativeTo: .title2)

  /// 34 pt — the grade headline, once per shift. The one place the heavy human cut
  /// is warranted: it is the single largest thing the deck ever draws.
  static let grade = grotesk(34, .bold, relativeTo: .largeTitle)

  /// The sane clamp the root applies (§4.5): scale, but do not detonate the deck.
  static let dynamicTypeRange: ClosedRange<DynamicTypeSize> = .xSmall ... .accessibility1
}

extension View {

  /// The tracked uppercase eyebrow: 11 pt mono, `.18em`, allowed to shrink one notch
  /// rather than truncate. Never applied to a sentence — only to a label.
  ///
  /// `scale` is the shrink floor. The default 0.9 is the right answer in a column
  /// that can reflow; a label pinned inside a fixed-height strip that cannot grow —
  /// the `SystemBar` — passes a deeper floor, because there the alternative to
  /// shrinking is `QUE…` rather than a taller row.
  func trackedLabel(_ color: Color = Theme.textQuiet, scale: CGFloat = 0.9) -> some View {
    self
      .font(Typography.label)
      .tracking(Typography.labelTracking)
      .textCase(.uppercase)
      .foregroundStyle(color)
      .minimumScaleFactor(scale)
      .lineLimit(1)
  }

  /// Prose at the body step with its authored leading. Long prose is **never**
  /// clamped (§4.5): `why` runs to 566 characters and `learn.concept` to 435, and
  /// both must scroll rather than truncate.
  func prose(_ color: Color = Theme.textSecondary) -> some View {
    self
      .font(Typography.body)
      .lineSpacing(Typography.bodyLineSpacing)
      .foregroundStyle(color)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// The quiet log line (R11): the machine voice at the 11 pt floor, in the colour
  /// that says "read this only if you want to". Wraps rather than truncates — the
  /// fear captions and the coverage line are sentences, not labels.
  func quietLog(_ color: Color = Theme.textDisabled) -> some View {
    self
      .font(Typography.quietLog)
      .foregroundStyle(color)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// Every number in the deck is tabular, so a count-up does not jitter its column.
  func tabularNumbers() -> some View {
    monospacedDigit()
  }
}
