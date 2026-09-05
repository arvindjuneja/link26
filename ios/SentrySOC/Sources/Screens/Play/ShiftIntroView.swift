import SwiftUI
import SentryCore

/// Shift intro — the 08:00 handover (`DESIGN.md` §2.4, `SPEC.md` §5.2).
///
/// The only screen in the loop with a back control, and legally so: nothing is
/// committed until `BEGIN`, so `‹ Desk` drops a board that has cost the player
/// nothing. It is deliberately **not** a `NavigationStack` back (D16), which is what
/// stops the same gesture appearing on the debrief by accident.
///
/// Every string is `CopyPack.intro`, including the taxonomy paragraph, which renders
/// through `RichTextView` so the cyan / emerald / rose verdict runs that carry the
/// DEF-A teaching survive the port (D5).
struct ShiftIntroView: View {
  let model: GameModel

  private var copy: CopyPack { model.content.copy }
  private var intro: CopyPack.Intro { copy.intro }
  private var shift: ShiftState? { model.session.shift }

  var body: some View {
    VStack(spacing: 0) {
      PlayBar(model: model, leading: .backToDesk, readout: shiftMeta)

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          header
          RichTextView(segments: intro.taxonomy)
          RichTextView(segments: intro.severity)
          meters
          if isHandoffBoard { handoffPanel }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 28)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .background(Theme.ground)
    .safeAreaInset(edge: .bottom) {
      PlayDock {
        Dock(
          title: Play.cta(intro.cta),
          disclaimer: intro.disclaimer,
          action: { model.send(.begin) })
      }
    }
    .accessibilityIdentifier("screen.shiftIntro")
  }

  // MARK: - Parts

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Text(Glyph.dot)
          .font(Typography.quietLog)
          .foregroundStyle(accent)
        Text(intro.eyebrow).trackedLabel(accent)
        Spacer(minLength: 0)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(copy.chromeText("introWelcome"))
        Text(copy.render(intro.title, ["n": String(alertCount)]))
      }
      .font(Typography.screenTitle)
      .foregroundStyle(Theme.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The two meters the shift is scored on, plus the soft time budget — introduced
  /// by what they *cost you*, which is the same `fear` string the Board sheet shows
  /// as a caption (§2.5) rather than a tooltip nobody on a phone can see (R11).
  private var meters: some View {
    VStack(alignment: .leading, spacing: 12) {
      PlayHairline()
      ForEach(intro.meters, id: \.key) { meter in
        HStack(alignment: .top, spacing: 14) {
          // Not `trackedLabel()`: it clamps to one line, and `NOISE / FATIGUE` does
          // not fit one at this width — it shipped as `NOISE / FATI…` in the first
          // render. Same 11 pt tracked step, allowed a second line.
          Text(meter.label)
            .font(Typography.label)
            .tracking(Typography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(tone(for: meter.key))
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(width: 108, alignment: .leading)
          Text(meter.fear)
            .quietLog(Theme.textQuiet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
      }
    }
  }

  /// Shift 4's fuchsia panel (§2.4). The iOS build always speaks the seat-neutral
  /// `blueOnly` voice — `features.redSeat` is `false` here and the exporter's B1
  /// override is what makes that a copy choice rather than a branch.
  private var handoffPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let note = boardNote {
        Text(note).trackedLabel(Theme.crossover)
      }
      RichTextView(segments: intro.handoff.blueOnly, baseColor: Theme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .panelCard()
    .leadingRule(Theme.crossover.opacity(0.55))
    .accessibilityElement(children: .contain)
  }

  // MARK: - Derived

  private var alertCount: Int { shift?.caseIds.count ?? 0 }

  /// `Shift 1 · 7 alerts`.
  private var shiftMeta: String? {
    guard let shift, let def = shiftDefinition(shift.shiftId, in: model.content) else {
      return nil
    }
    return copy.render(
      copy.chromeText("introShiftMeta"),
      ["shift": def.label, "n": String(alertCount)])
  }

  private var boardNote: String? {
    shift.flatMap { shiftDefinition($0.shiftId, in: model.content) }?.note
  }

  /// The crossover board announces itself in the content, not in a hardcoded id: a
  /// case carrying a `handoff` reference *is* a red-team run seen from this chair.
  private var isHandoffBoard: Bool {
    guard let shift else { return false }
    return shift.caseIds.contains { model.content.case($0)?.handoff != nil }
  }

  private var accent: Color { isHandoffBoard ? Theme.crossover : Theme.benign }

  private func tone(for key: CopyPack.MeterKey) -> Color {
    switch key {
    case .breach: Theme.truePositive
    case .noise: Theme.pressure
    case .time: Theme.textQuiet
    }
  }
}
