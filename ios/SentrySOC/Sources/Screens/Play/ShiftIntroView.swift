import SwiftUI
import SentryCore

/// Shift intro — the 08:00 handover (`DESIGN.md` §2.4, `SPEC.md` §5.2), rebuilt to
/// `FEEL.md` §1.
///
/// **What this screen was, and why it changed.** It was a briefing: an eyebrow, two
/// paragraphs of taxonomy, three meter rows and a CTA, all present on the first frame.
/// The founder read it as a lecture — *"wygląda jak wykład o SOC"* — and the diagnosis
/// was right: nothing on it *arrived*. §1 replaces the page with a sequence.
///
/// The board fills in front of the player, one alert per 260 ms with a ping stepping
/// up in pitch, and only then does the shift lead say her one line and the dock rise.
/// The order is the meaning: **this is the queue, this is what it is, now clock in.**
///
/// The only screen in the loop with a back control, and legally so: nothing is
/// committed until `BEGIN`, so `‹ Desk` drops a board that has cost the player
/// nothing. It is deliberately **not** a `NavigationStack` back (D16).
///
/// Every string is `CopyPack.intro` or a chrome key. The DEF-A taxonomy renders
/// through `RichTextView` inside the shift-1 message card, so the cyan / emerald /
/// rose verdict runs that carry the teaching survive the port (D5) — and §6 is why it
/// is a *card* now: it is the first thing Vale says, before the first alert exists.
struct ShiftIntroView: View {
  let model: GameModel

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var copy: CopyPack { model.content.copy }
  private var intro: CopyPack.Intro { copy.intro }
  private var shift: ShiftState? { model.session.shift }
  private var director: Director { model.director }

  /// The one sequence this screen plays, addressed by the board it belongs to.
  private var runID: String { Director.handoverID(shift: shift?.shiftId ?? "") }

  var body: some View {
    VStack(spacing: 0) {
      PlayBar(model: model, leading: .backToDesk, readout: shiftMeta)

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          eyebrow
          rail
          if director.shows(.message, of: runID) { handoverMessage }
          if director.shows(.dock, of: runID) { meters }
          if isHandoffBoard, director.shows(.message, of: runID) { handoffPanel }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 28)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .background(Theme.ground)
    .contentShape(Rectangle())
    // §1's last line: tap anywhere skips to the end state.
    .onTapGesture { director.skip() }
    .safeAreaInset(edge: .bottom) { dock }
    .onAppear {
      director.play(
        Sequences.handoverSequence(alertCount: alertCount),
        id: runID, reduceMotion: reduceMotion)
    }
    .accessibilityIdentifier("screen.shiftIntro")
  }

  // MARK: - t = 0 · the eyebrow types in

  private var eyebrow: some View {
    HStack(spacing: 8) {
      Text(Glyph.dot)
        .font(Typography.quietLog)
        .foregroundStyle(accent)
      TypedText(
        text: intro.eyebrow.uppercased(),
        isActive: director.shows(.eyebrow, of: runID),
        font: Typography.label,
        color: accent,
        tracking: Typography.labelTracking)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - 600 ms · the rail, then one alert per 260 ms

  /// The board, as a rail of slots that fill.
  ///
  /// Each slot is a **single line** — `High · Encoded PowerShell on a finance
  /// workstation` — because §1 is a headcount, not a briefing: the player learns how
  /// much work there is and what shape it is, and reads none of it yet.
  @ViewBuilder private var rail: some View {
    if director.shows(.boardRise, of: runID) {
      // No header over the rail. `intro.title` — "7 alerts on the board." — is the
      // ONE line Vale says at the bottom of the sequence (§1 row 4), and printing it
      // here as well made the screen say the same sentence twice, 1.4 s apart.
      VStack(alignment: .leading, spacing: 10) {
        PlayHairline()

        VStack(spacing: 4) {
          ForEach(Array(queue.enumerated()), id: \.offset) { index, entry in
            HandoverSlot(
              number: index + 1,
              line: entry,
              filled: director.shows(.alertLand(index), of: runID))
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  // MARK: - + 400 ms · the shift lead's one line

  /// §1's message card, and — on shift 1 — §6's first card.
  ///
  /// The line is `intro.title`: *"7 alerts on the board."* One sentence, from
  /// `copy.intro`, which is what §1 asks for. Under it, on the first board only, the
  /// DEF-A taxonomy with its colour runs: the paragraph that used to be the third
  /// coach step's body, moved to where it is read **before** the first alert instead
  /// of over the top of it (§6, §10). Later boards get the line alone — the rules do
  /// not need re-teaching every shift, and Settings keeps them one tap away.
  ///
  /// **`intro.severity` is not printed here any more.** It was the second of the two
  /// paragraphs that made this screen a lecture, it says nothing the first debrief
  /// does not demonstrate, and it is one tap away in Settings → *Read the rules
  /// again* beside the taxonomy it belongs with. Nothing was deleted from the
  /// bundle — the copy is exported, drawn, and reachable.
  private var handoverMessage: some View {
    // The card owns its own 500 ms of dots from the moment this beat puts it on
    // screen, which is exactly §1 row 4's "typing dots 500 ms → text".
    MessageCard(
      sender: copy.chromeText("coachEyebrow"),
      line: copy.render(intro.title, ["n": String(alertCount)]),
      richBody: model.isFirstShift ? intro.taxonomy : [],
      tone: accent)
      .transition(.move(edge: .leading).combined(with: .opacity))
  }

  // MARK: - + 300 ms · the dock, and the meters with their labels only

  /// The two meters the shift is scored on, plus the soft time budget.
  ///
  /// **Labels only** (§1's last row, §10's last bullet): the `fear` line that says
  /// what a meter *costs* you arrives the first time that meter moves (§5), typed in,
  /// and then stays. Stating the consequence before anything has happened is how the
  /// screen read as a lecture.
  private var meters: some View {
    VStack(alignment: .leading, spacing: 10) {
      PlayHairline()
      ForEach(intro.meters, id: \.key) { meter in
        HStack(alignment: .firstTextBaseline, spacing: 14) {
          Text(meter.label)
            .font(Typography.label)
            .tracking(Typography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(tone(for: meter.key))
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(width: 108, alignment: .leading)

          Capsule(style: .continuous)
            .fill(tone(for: meter.key).opacity(0.16))
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
      }
    }
    .transition(.opacity)
  }

  private var dock: some View {
    PlayDock {
      if director.shows(.dock, of: runID) {
        Dock(
          title: Play.cta(intro.cta),
          disclaimer: intro.disclaimer,
          action: { model.send(.begin) })
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
    .transition(.opacity)
    .accessibilityElement(children: .contain)
  }

  // MARK: - Derived

  private var alertCount: Int { shift?.caseIds.count ?? 0 }

  /// One line per alert: what the tool made of it, and what it is called.
  private var queue: [String] {
    guard let shift else { return [] }
    return shift.caseIds.map { caseID in
      guard let socCase = model.content.case(caseID) else { return caseID }
      let severity = copy.severity(socCase.toolSeverity).label
      return "\(severity)  \(socCase.alertTitle)"
    }
  }

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

// MARK: - One slot on the rail

/// An empty slot, and the alert that lands in it (§1).
///
/// The empty state is drawn rather than omitted so the rail has its full height from
/// 600 ms — the board does not grow under the player as it fills, it *fills*, which
/// is the difference between a list appearing and a queue arriving.
private struct HandoverSlot: View {
  let number: Int
  let line: String
  let filled: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(String(number))
        .font(Typography.meta)
        .tabularNumbers()
        .foregroundStyle(filled ? Theme.textDisabled : Theme.textDisabled.opacity(0.4))
        .frame(width: 14, alignment: .trailing)

      Text(line)
        .font(Typography.meta)
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(1)
        .truncationMode(.tail)
        .opacity(filled ? 1 : 0)
        .offset(y: filled ? 0 : Motion.beatRise)

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        .fill(filled ? Theme.panel : Theme.panel.opacity(0.35))
    }
    .overlay {
      RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        .strokeBorder(filled ? Theme.hairline : Theme.hairline.opacity(0.4), lineWidth: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(line)
    .accessibilityHidden(!filled)
  }
}
