import SwiftUI
import SentryCore

/// The debrief — the hero screen (`DESIGN.md` §2.10, `SPEC.md` §5.8).
///
/// **There is no back control.** A debrief is completed, not browsed: the only way
/// out is forward, which is what makes the call feel filed. It is re-openable
/// read-only from the board's done rows and the summary's glyph strip
/// (`VIEW_RESULT`, Appendix A G5), and in that mode the ~1.1 s entry sequence and
/// the verdict cue are both skipped — a re-read is a reference, not a verdict.
///
/// `grade.outcome` is `engine.outcomeText(grade.outcomeKey)`: **Swift decides, the
/// bundle speaks** (D2). Nothing here compares prose.
///
/// `why` (≤566 characters) and `learn.concept` (≤435) are never clamped — they are
/// the lesson, and the screen scrolls.
struct DebriefView: View {
  let model: GameModel
  let readOnly: Bool

  /// The entry sequence, as one ordered state (§5.8): stamp lands → outcome fades →
  /// meters sweep. A tap anywhere jumps straight to `.done`.
  private enum Stage: Int, Comparable {
    case stamp, outcome, meters, done
    static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var stage: Stage = .stamp

  private var copy: CopyPack { model.content.copy }
  private var session: SessionState { model.session }
  private var outcome: CallOutcome? { session.last }
  private var socCase: SocCase? { outcome?.socCase(model.content) }
  private var result: CaseResult? {
    outcome.flatMap { session.shift?.result(for: $0.caseId) }
  }

  var body: some View {
    ZStack {
      Theme.ground.ignoresSafeArea()
      // The full-bleed 6 % verdict tint (§2.10) — the one moment the deck floods.
      tone.opacity(0.06).ignoresSafeArea()

      VStack(spacing: 0) {
        PlayBar(model: model, leading: .wordmark, trace: session.status, readout: queuePosition)

        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if let outcome, let socCase {
              headline
              stampCard(outcome, socCase)
              outcomeLine(outcome)
              meters(outcome)
              why(socCase)
              decisiveFindings(socCase)
              coverage(socCase)
              learn(socCase)
              yourCall(outcome)
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 26)
        }
        .scrollBounceBehavior(.basedOnSize)
        .playScrollTopFade()
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { skip() }
    .safeAreaInset(edge: .bottom) {
      PlayDock {
        Dock(title: dockTitle, tone: tone, action: { model.send(.nextCase) })
      }
    }
    .onAppear(perform: playEntry)
    .accessibilityIdentifier("screen.debrief")
  }

  // MARK: - The hero

  private var headline: some View {
    HStack(spacing: 8) {
      Text(Glyph.dot).font(Typography.quietLog).foregroundStyle(tone)
      Text(headlineText).trackedLabel(tone)
      Spacer(minLength: 0)
    }
  }

  private func stampCard(_ outcome: CallOutcome, _ socCase: SocCase) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Spacer(minLength: 0)
        StampView(
          text: copy.dispositionMeta[outcome.chosen]?.label ?? outcome.chosen.rawValue,
          tone: Theme.disposition(outcome.chosen),
          spokenLabel: copy.render(
            copy.chromeText("debriefFiled"),
            ["disposition": copy.dispositionMeta[outcome.chosen]?.label ?? ""]),
          animates: !readOnly)
        Spacer(minLength: 0)
      }
      .padding(.vertical, 6)

      Text(socCase.alertTitle)
        .font(Typography.body)
        .foregroundStyle(Theme.textTertiary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
        Text(copy.chromeText("debriefTruth")).trackedLabel(Theme.textDisabled)
        Chip(
          text: copy.verdictLabels[socCase.truth] ?? socCase.truth.rawValue,
          tone: Theme.verdict(socCase.truth), style: .filled, tracked: false)
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .panelCard()
  }

  private func outcomeLine(_ outcome: CallOutcome) -> some View {
    Text(model.engine.outcomeText(outcome.grade.outcomeKey))
      .font(Typography.rowTitle)
      .foregroundStyle(Theme.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .opacity(stage >= .outcome ? 1 : 0)
      .gatedAnimation(Motion.screenPush, value: stage >= .outcome)
  }

  // MARK: - The meters

  /// The two pressure meters, swept once the stamp has landed.
  ///
  /// They sweep **from empty**, not from the value before the call: the delta is
  /// stated as a number beside the level, so the bar does not have to encode it —
  /// and no screen in this app ever subtracts one metered value from another (D8).
  private func meters(_ outcome: CallOutcome) -> some View {
    let shift = session.shift
    let tuning = model.content.tuning
    let swept = stage >= .meters

    return VStack(alignment: .leading, spacing: 16) {
      ForEach(copy.intro.meters.filter { $0.key != .time }, id: \.key) { meter in
        let level = meter.key == .breach ? (shift?.breachRisk ?? 0) : (shift?.noise ?? 0)
        let delta = meter.key == .breach ? outcome.grade.breachDelta : outcome.grade.noiseDelta
        let status = Trace.status(level, tuning)
        let value = copy.render(copy.chromeText("boardMeterValue"), ["n": String(level)])

        MeterView(
          label: meter.label,
          valueText: "\(value)  \(deltaText(delta))",
          fraction: swept ? Play.meterFraction(level: level, tuning: tuning) : 0,
          status: status,
          fear: meter.fear,
          spokenValue: "\(value), \(Play.statusLabel(status, copy))",
          numericKey: swept ? Double(level) : 0)
      }
    }
  }

  /// The meter delta, exactly as §2.10's wireframe draws it — **from the bundle**
  /// (P1-6).
  ///
  /// These two forms used to be assembled here. They survived the S1 grep because
  /// they contain no letter, which is a limit of that grep rather than a licence:
  /// `+` and `±` are glyphs the deck spends deliberately, and a re-voiced delta
  /// (`up 30`, `no change`) would have been invisible to the copy pipeline. Now the
  /// format is `chrome.deltaFormat` / `chrome.deltaZero`, so the rule "no screen
  /// authors what the player reads" is true of the numerals too.
  private func deltaText(_ delta: Int) -> String {
    delta > 0
      ? copy.render(copy.chromeText("deltaFormat"), ["n": String(delta)])
      : copy.chromeText("deltaZero")
  }

  // MARK: - The lesson

  private func why(_ socCase: SocCase) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      PlayEyebrow(text: copy.chromeText("debriefWhy"))
      Text(socCase.why).prose()
    }
  }

  /// The findings that decide this case, marked ✓ pulled / ○ missed (§2.10).
  ///
  /// This is the one place weight is ever revealed: during play `decisive`,
  /// `supporting`, `neutral` and `noise` are indistinguishable (§5.6), which is why
  /// a remembered verdict still has to be proved.
  @ViewBuilder private func decisiveFindings(_ socCase: SocCase) -> some View {
    let decisive = socCase.evidence.filter { $0.weight == .decisive }
    if !decisive.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        PlayEyebrow(text: copy.chromeText("debriefDecisive"))
        ForEach(decisive) { finding in
          let pulled = result?.queriedSourceIds.contains(finding.sourceId) ?? false
          EvidenceCard(
            label: finding.label, detail: finding.detail,
            marker: pulled
              ? (Glyph.correct, Theme.benign) : (Glyph.missed, Theme.textDisabled))
        }
      }
    }
  }

  @ViewBuilder private func coverage(_ socCase: SocCase) -> some View {
    if let result {
      VStack(alignment: .leading, spacing: 4) {
        Text(
          copy.render(
            copy.chromeText("debriefCoverage"),
            [
              "n": String(result.keySourcesPulled),
              "m": String(socCase.keySourceIds.count),
            ])
        )
        .font(Typography.meta)
        .foregroundStyle(Theme.textQuiet)
        .fixedSize(horizontal: false, vertical: true)

        switch model.engine.investigationOf(result, socCase) {
        case .thorough:
          Text(copy.chromeText("debriefThorough"))
            .font(Typography.meta)
            .foregroundStyle(Theme.benign)
            .fixedSize(horizontal: false, vertical: true)
        case .blind:
          Text(copy.chromeText("debriefBlind"))
            .font(Typography.meta)
            .foregroundStyle(Theme.truePositive)
            .fixedSize(horizontal: false, vertical: true)
        case .partial:
          EmptyView()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
    }
  }

  /// R22: the pointer stays **plain text**. An affiliate link inside the game loop
  /// is an App Store risk and a design-doc violation; the only outbound link in the
  /// app is the privacy policy.
  private func learn(_ socCase: SocCase) -> some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 10) {
        Text(socCase.learn.concept).prose()
        if let pointer = socCase.learn.pointer {
          Text(pointer)
            .quietLog(Theme.textQuiet)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 10)
    } label: {
      HStack(spacing: 10) {
        Text(copy.chromeText("debriefLearn")).trackedLabel(Theme.textTertiary)
        Spacer(minLength: 8)
        if let mitre = socCase.learn.mitreId {
          Chip(text: mitre, tone: Theme.textTertiary, style: .filled, tracked: false)
        }
      }
      .frame(minHeight: Theme.Hit.minimum)
    }
    .tint(Theme.textTertiary)
    .padding(.horizontal, 14)
    .padding(.vertical, 4)
    .panelCard()
    .accessibilityIdentifier("debrief.learn")
  }

  private func yourCall(_ outcome: CallOutcome) -> some View {
    HStack(spacing: 8) {
      Text(copy.chromeText("debriefYourCall")).trackedLabel(Theme.textDisabled)
      Text(copy.dispositionMeta[outcome.chosen]?.label ?? outcome.chosen.rawValue)
        .font(Typography.meta)
        .foregroundStyle(Theme.textQuiet)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: - The entry sequence

  /// ~1.1 s, and every step of it is skippable by tapping anywhere.
  ///
  /// The cues are fired here rather than by the reducer because only the view knows
  /// when its animation reaches them (§4.4): the verdict lands with the stamp, and
  /// `breachThud` lands with the sweep that shows the damage.
  private func playEntry() {
    guard !readOnly, let outcome else {
      stage = .done
      return
    }
    model.feel(SocCue.verdict(outcome.grade))

    guard !reduceMotion else {
      stage = .done
      fireBreachThud(outcome)
      return
    }

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(0.35))
      advance(to: .outcome)
      try? await Task.sleep(for: .seconds(0.25))
      if stage < .meters { fireBreachThud(outcome) }
      advance(to: .meters)
      try? await Task.sleep(for: .seconds(0.50))
      advance(to: .done)
    }
  }

  /// §5.8: a `breachDelta` at the missed-TP tier is the one call that gets its own
  /// bespoke pattern. The threshold is the tuning number, not a literal — a designer
  /// retune moves the thud with it.
  private func fireBreachThud(_ outcome: CallOutcome) {
    guard outcome.grade.breachDelta >= model.content.tuning.grade.tpMissedBreach else {
      return
    }
    model.feel(.breachThud)
  }

  private func advance(to next: Stage) {
    guard stage < next else { return }
    withAnimation(Motion.gated(Motion.meterSweep, reduceMotion: reduceMotion)) {
      stage = next
    }
  }

  private func skip() {
    guard stage != .done else { return }
    withAnimation(Motion.gated(Motion.meterSweep, reduceMotion: reduceMotion)) {
      stage = .done
    }
  }

  // MARK: - Derived

  private var headlineText: String {
    guard let grade = outcome?.grade else { return "" }
    if grade.dispositionCorrect { return copy.debriefHeadlines.good }
    return grade.verdictCorrect
      ? copy.debriefHeadlines.verdictOnly : copy.debriefHeadlines.wrong
  }

  private var tone: Color {
    guard let grade = outcome?.grade else { return Theme.falsePositive }
    if grade.dispositionCorrect { return Theme.benign }
    return grade.verdictCorrect ? Theme.pressure : Theme.truePositive
  }

  private var queuePosition: String? {
    guard let shift = session.shift else { return nil }
    return copy.render(
      copy.chromeText("queueCount"),
      ["n": String(min(shift.index, shift.caseIds.count)), "m": String(shift.caseIds.count)])
  }

  private var dockTitle: String {
    if readOnly { return copy.chromeText("close") }
    let complete = session.shift.map { model.engine.shiftComplete($0) } ?? false
    return Play.cta(
      complete ? copy.chromeText("debriefEnd") : copy.chromeText("debriefNext"))
  }
}
