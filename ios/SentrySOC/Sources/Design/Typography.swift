import SwiftUI

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
  /// other half of the bargain — one step of the scale per case — is held by the
  /// cases themselves: there are six, and the seven-step scale below calls all six.
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

  /// The verdict stamp (§2.16 puts the stamp in the machine voice, C7 draws it).
  /// The heaviest mono cut, because it lands once per call and has to read as
  /// pressed into the page rather than typed onto it.
  static let stamp = mono(15, .semibold, relativeTo: .body)

  /// 15 pt / 1.55 — prose. The human voice.
  static let body = grotesk(15, .regular, relativeTo: .body)
  /// 15 pt — the same step in the machine voice, for evidence detail and raw log.
  static let bodyMono = mono(15, .regular, relativeTo: .body)
  /// The 1.55 line height of the body step, as the extra leading SwiftUI wants.
  static let bodyLineSpacing: CGFloat = 15 * 0.55

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
  func trackedLabel(_ color: Color = Theme.textQuiet) -> some View {
    self
      .font(Typography.label)
      .tracking(Typography.labelTracking)
      .textCase(.uppercase)
      .foregroundStyle(color)
      .minimumScaleFactor(0.9)
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

  /// Every number in the deck is tabular, so a count-up does not jitter its column.
  func tabularNumbers() -> some View {
    monospacedDigit()
  }
}
