import SwiftUI
import SentryCore

/// The board — the queue and the pressure (`DESIGN.md` §2.5, `SPEC.md` §5.3).
///
/// Auto-opens exactly once per shift, on the first alert (the reducer's `BEGIN`
/// sets it), and never again unless the player asks for it from the case's `‹ n/m`
/// control.
///
/// Two rules here are pedagogy, not layout:
/// - **Upcoming rows show the alert title and nothing else.** No severity chip: the
///   tool's severity is a guess, and showing it primes the read before the alert is
///   even open (§4.1).
/// - **The two `fear` strings are visible captions**, not `title=` tooltips — a
///   phone can never show a tooltip (R11) — and they are the VoiceOver hint as well,
///   which `MeterView` wires from the same string.
struct BoardSheet: View {
  let model: GameModel

  /// See `SourceSheet`: `PhaseHost` dispatches `CLOSE_VIEW` from its sheet binding,
  /// so this closes the presentation and lets the host send the one action.
  @Environment(\.dismiss) private var dismiss

  private var copy: CopyPack { model.content.copy }
  private var session: SessionState { model.session }
  private var director: Director { model.director }

  var body: some View {
    SheetChrome(
      eyebrow: eyebrow,
      trailing: copy.render(copy.chromeText("boardClock"), ["n": String(clock)])
    ) {
      if let shift = session.shift {
        VStack(alignment: .leading, spacing: 18) {
          queue(shift)
          pressure(shift)
          abandon
        }
      }
    } footer: {
      Dock(
        title: Play.cta(
          copy.render(
            copy.chromeText("boardOpenAlert"),
            ["n": String((session.shift?.index ?? 0) + 1)])),
        tone: Theme.falsePositive,
        action: { dismiss() })
    }
    .accessibilityIdentifier("sheet.board")
  }

  // MARK: - The queue

  private func queue(_ shift: ShiftState) -> some View {
    VStack(spacing: 6) {
      ForEach(Array(shift.caseIds.enumerated()), id: \.offset) { index, caseID in
        let socCase = model.content.case(caseID)
        BoardQueueRow(
          number: index + 1,
          title: socCase?.alertTitle ?? caseID,
          detectionRule: index == shift.index ? socCase?.detectionRule : nil,
          // **The live board** (`FEEL.md` §5). An upcoming row normally shows a title
          // and nothing else, because the tool's severity is a guess and printing it
          // primes the read (§4.1). What §5 adds is *time*: every 25–40 s one alert
          // ahead of the player reveals what the tool made of it, with a ping and an
          // ECG blip. Nothing about the queue's order or content moves — the desk
          // simply stops being a still life while you work.
          severity: revealedSeverity(index, socCase),
          state: state(index, in: shift, caseID: caseID),
          action: shift.result(for: caseID) == nil
            ? nil : { model.send(.viewResult(caseID)) })
      }
    }
  }

  /// What the tool said about an alert the player has not reached — but only once the
  /// live board has revealed it (§5).
  private func revealedSeverity(_ index: Int, _ socCase: SocCase?) -> (String, Color)? {
    guard let socCase, director.revealedAlerts.contains(index) else { return nil }
    let severity = copy.severity(socCase.toolSeverity)
    return (severity.label, Theme.tone(severity.tone))
  }

  /// Done rows carry the verdict they earned; the current row is the only one with a
  /// rule under it; everything ahead is a title.
  private func state(_ index: Int, in shift: ShiftState, caseID: String) -> BoardQueueRow.State {
    if let result = shift.result(for: caseID) {
      return result.verdictCorrect ? .doneRight : .doneWrong
    }
    return index == shift.index ? .current : .ahead
  }

  // MARK: - The pressure

  private func pressure(_ shift: ShiftState) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      PlayEyebrow(text: copy.chromeText("boardPressureEyebrow"))

      ForEach(copy.intro.meters, id: \.key) { meter in
        let reading = reading(meter.key, shift)
        // §5 / §10: the `fear` caption is a **consequence**, so it arrives the first
        // time its meter moves and then stays. TIME never moves a meter — it is the
        // soft budget — so its caption rides on the two that do.
        let revealed = director.fearRevealed.contains(meter.key.rawValue)
        MeterView(
          label: meter.label,
          valueText: reading.text,
          fraction: reading.fraction,
          status: reading.status,
          fear: revealed ? meter.fear : nil,
          spokenValue: "\(reading.text), \(Play.statusLabel(reading.status, copy))",
          numericKey: reading.fraction)
      }
    }
  }

  /// One meter's three presentation values. **Nothing is computed here** — the
  /// levels come off the `ShiftState` the engine wrote and the band comes from
  /// `Trace.status`; only the bar's width is derived, in the one audited place
  /// (`Play.meterFraction`).
  private func reading(
    _ key: CopyPack.MeterKey, _ shift: ShiftState
  ) -> (text: String, fraction: Double, status: TraceStatus) {
    let tuning = model.content.tuning
    switch key {
    case .breach:
      return (
        copy.render(copy.chromeText("boardMeterValue"), ["n": String(shift.breachRisk)]),
        Play.meterFraction(level: shift.breachRisk, tuning: tuning),
        Trace.status(shift.breachRisk, tuning))
    case .noise:
      return (
        copy.render(copy.chromeText("boardMeterValue"), ["n": String(shift.noise)]),
        Play.meterFraction(level: shift.noise, tuning: tuning),
        Trace.status(shift.noise, tuning))
    case .time:
      return (
        copy.render(
          copy.chromeText("boardTimeValue"),
          ["n": String(clock), "m": String(shift.timeBudget)]),
        Play.timeFraction(used: clock, budget: shift.timeBudget),
        .calm)
    }
  }

  // MARK: - Leaving

  /// §2.2: destructive actions are text buttons **outside** the thumb arc, always
  /// behind a confirm. This one is the last thing in the scroll region, above the
  /// footer, which is exactly where a thumb does not land.
  private var abandon: some View {
    HStack {
      Spacer(minLength: 0)
      Button {
        model.send(.openView(.abandon))
      } label: {
        Text("\(copy.chromeText("boardAbandon")) \(Glyph.forward)")
          .font(Typography.meta)
          .foregroundStyle(Theme.textDisabled)
          .padding(.horizontal, 8)
          .minimumHitTarget()
      }
      .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
      .accessibilityIdentifier("board.abandon")
    }
  }

  // MARK: - Derived

  private var eyebrow: String {
    guard let shift = session.shift,
          let def = shiftDefinition(shift.shiftId, in: model.content)
    else { return copy.chromeText("boardEyebrow") }
    return "\(copy.chromeText("boardEyebrow")) · \(def.label)"
  }

  /// Shift-minutes spent: everything banked by filed calls, plus what the alert in
  /// front of the player has cost so far.
  private var clock: Int {
    (session.shift?.timeUsed ?? 0) + session.timeSpentOnCurrentCase(model.content)
  }
}

// MARK: - A row on the board

/// One alert in the queue (§2.5). Four states, one shape.
///
/// A done row is a `Button` into its own debrief, read-only (Appendix A G5); a row
/// that has not been called yet is inert, because the queue is worked in order.
struct BoardQueueRow: View {

  enum State {
    case doneRight
    case doneWrong
    case current
    case ahead
  }

  let number: Int
  let title: String
  /// Only the current alert shows the rule that fired it.
  var detectionRule: String?
  /// The tool's guess and its hue, once the live board has revealed it (`FEEL.md`
  /// §5). `nil` on every row that has not been revealed — which is every row, until
  /// the desk has been worked for half a minute.
  var severity: (String, Color)?
  let state: State
  /// `nil` on a row that cannot be opened.
  var action: (() -> Void)?

  var body: some View {
    Group {
      if let action {
        Button(action: action) { content }
          .buttonStyle(PressableStyle())
          .accessibilityIdentifier("board.queueRow")
      } else {
        content
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var content: some View {
    HStack(alignment: .top, spacing: 10) {
      Text(glyph)
        .font(Typography.metaStrong)
        .foregroundStyle(glyphTone)
        .frame(width: 14, alignment: .center)

      Text(String(number))
        .font(Typography.meta)
        .tabularNumbers()
        .foregroundStyle(Theme.textDisabled)
        .frame(width: 12, alignment: .trailing)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(Typography.metaProse)
          .foregroundStyle(titleTone)
          .lineLimit(state == .current ? nil : 1)
          .truncationMode(.tail)
          .fixedSize(horizontal: false, vertical: state == .current)

        if let severity, state == .ahead {
          Text(severity.0)
            .trackedLabel(severity.1, scale: 0.8)
            .transition(.opacity)
        }

        if let detectionRule {
          Text(detectionRule)
            .font(Typography.quietLog)
            .foregroundStyle(Theme.textQuiet)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.leading, state == .current ? 10 + Theme.ruleWidth : 10)
    .padding(.trailing, 12)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, minHeight: Theme.Hit.minimum, alignment: .leading)
    .panelCard(
      fill: state == .current ? Theme.falsePositive.opacity(0.06) : Theme.panel.opacity(0.5),
      stroke: state == .current ? Theme.falsePositive.opacity(0.30) : Theme.hairline)
    .leadingRule(state == .current ? Theme.falsePositive : nil)
    .contentShape(Rectangle())
  }

  private var glyph: String {
    switch state {
    case .doneRight: Glyph.correct
    case .doneWrong: Glyph.wrong
    case .current: Glyph.forward
    case .ahead: ""
    }
  }

  private var glyphTone: Color {
    switch state {
    case .doneRight: Theme.benign
    case .doneWrong: Theme.truePositive
    case .current: Theme.falsePositive
    case .ahead: Theme.textDisabled
    }
  }

  private var titleTone: Color {
    switch state {
    case .current: Theme.textPrimary
    case .doneRight, .doneWrong: Theme.textTertiary
    case .ahead: Theme.textQuiet
    }
  }
}
