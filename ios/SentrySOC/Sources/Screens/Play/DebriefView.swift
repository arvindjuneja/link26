import SwiftUI
import SentryCore

/// The debrief — the hero screen (`DESIGN.md` §2.10, `SPEC.md` §5.8), rebuilt to
/// `FEEL.md` §8.
///
/// **The call is a cut, not a transition.** The hold completes, the room tone ducks,
/// and the screen goes black with the file thud. Nothing is on it for 450 ms. Then
/// the stamp slams; at 900 the ground comes back with the headline; at 1200 the truth
/// flips; at 1500 the meters sweep and a bad breach thuds with a rose edge; at 2100
/// the reasoning arrives and the Dock rises last.
///
/// That silence between 0 and 450 is the whole design. It is the only place in the
/// app where nothing at all happens, and it is what makes a filed call feel filed.
///
/// **There is no back control.** A debrief is completed, not browsed. It is
/// re-openable read-only from the board's done rows and the summary's glyph strip
/// (`VIEW_RESULT`, Appendix A G5), and in that mode the sequence and the verdict cue
/// are both skipped — a re-read is a reference, not a verdict.
///
/// `grade.outcome` is `engine.outcomeText(grade.outcomeKey)`: **Swift decides, the
/// bundle speaks** (D2). Nothing here compares prose.
struct DebriefView: View {
  let model: GameModel
  let readOnly: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// §8's rose edge, live for one flash. A `Bool` the screen owns rather than a read
  /// of the beat: a beat that has landed stays landed, and an edge drawn from
  /// `shows(.breach)` therefore stayed lit for the whole debrief. Measured in
  /// `docs/screenshots/ios/feel/breach`, where frame 65 — four and a half seconds
  /// after the cut — still had a rose border on both sides.
  @State private var breachFlashing = false

  private var copy: CopyPack { model.content.copy }
  private var session: SessionState { model.session }
  private var director: Director { model.director }
  private var outcome: CallOutcome? { session.last }
  private var socCase: SocCase? { outcome?.socCase(model.content) }
  private var result: CaseResult? {
    outcome.flatMap { session.shift?.result(for: $0.caseId) }
  }

  /// §8's sequence, addressed by the call it is about.
  private var runID: String { Director.callID(case: outcome?.caseId ?? "") }

  /// Whether a beat has landed. A read-only re-read has no sequence at all, so every
  /// part is simply there — which is what "a reference, not a verdict" means in code.
  private func shows(_ kind: BeatKind) -> Bool {
    readOnly || director.shows(kind, of: runID)
  }

  /// True while the screen is still black (§8, rows 2–3).
  private var inCut: Bool { !shows(.verdict) }

  var body: some View {
    ZStack {
      Theme.ground.ignoresSafeArea()
      // The full-bleed 6 % verdict tint (§2.10) — the one moment the deck floods. It
      // arrives with the ground at 900 ms, not before: during the cut there is no
      // verdict on screen to tint.
      tone.opacity(shows(.verdict) ? 0.06 : 0).ignoresSafeArea()

      VStack(spacing: 0) {
        PlayBar(model: model, leading: .wordmark, trace: session.status, readout: queuePosition)
          // §8 row 2: the SystemBar hides for the cut. Held in the layout rather than
          // removed, so the stamp does not jump 44 pt when the strip comes back.
          .opacity(shows(.verdict) ? 1 : 0)

        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if let outcome, let socCase {
              headline
              stampCard(outcome, socCase)
              outcomeLine(outcome)
              if shows(.meters) { meters(outcome) }
              if shows(.why) {
                why(socCase)
                decisiveFindings(socCase)
                coverage(socCase)
                learn(socCase)
                yourCall(outcome)
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 26)
        }
        .scrollBounceBehavior(.basedOnSize)
        .playScrollTopFade()
      }

      // **The cut.** `Theme.scrim` is the deck's black and is spelled in `Design/`
      // and nowhere else. It covers everything except the stamp, which is drawn over
      // it — so from 450 ms there is a stamp on black and nothing else at all.
      if inCut {
        Theme.scrim
          .ignoresSafeArea()
          .transition(.opacity)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      if inCut, shows(.stamp), let outcome {
        cutStamp(outcome)
      }
      breachEdge
    }
    .contentShape(Rectangle())
    // §8: "tap anywhere from 450 ms onward → end state". Before the stamp there is
    // nothing to skip to — a tap in the first 450 ms is a tap on a black screen, and
    // letting it through would make the cut skippable before it has said anything.
    .onTapGesture { if shows(.stamp) { director.skip() } }
    .safeAreaInset(edge: .bottom) { dock }
    .onChange(of: shows(.breach)) { _, landed in
      if landed { flashBreachEdge() }
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
    .opacity(shows(.verdict) ? 1 : 0)
  }

  /// The stamp as it lands during the cut: centred, on black, with nothing to read
  /// but the disposition.
  private func cutStamp(_ outcome: CallOutcome) -> some View {
    StampView(
      text: copy.dispositionMeta[outcome.chosen]?.label ?? outcome.chosen.rawValue,
      tone: Theme.disposition(outcome.chosen),
      spokenLabel: copy.render(
        copy.chromeText("debriefFiled"),
        ["disposition": copy.dispositionMeta[outcome.chosen]?.label ?? ""]),
      animates: true)
    .transition(.opacity)
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
          // The card's copy never re-runs the slam: the stamp the player watched land
          // was `cutStamp`, and this one is where it comes to rest.
          animates: false)
        Spacer(minLength: 0)
      }
      .padding(.vertical, 6)

      Text(socCase.alertTitle)
        .font(Typography.body)
        .foregroundStyle(Theme.textTertiary)
        .fixedSize(horizontal: false, vertical: true)

      // §8 row 5: the truth flips in at 1200 ms, 200 ms of rotation — the one card in
      // the app that turns over.
      HStack(spacing: 10) {
        Text(copy.chromeText("debriefTruth")).trackedLabel(Theme.textDisabled)
        Chip(
          text: copy.verdictLabels[socCase.truth] ?? socCase.truth.rawValue,
          tone: Theme.verdict(socCase.truth), style: .filled, tracked: false)
          .rotation3DEffect(
            .degrees(shows(.truth) ? 0 : 90), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
          .opacity(shows(.truth) ? 1 : 0)
          .gatedAnimation(Motion.truthFlip, value: shows(.truth))
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .panelCard()
    .opacity(inCut ? 0 : 1)
  }

  private func outcomeLine(_ outcome: CallOutcome) -> some View {
    Text(model.engine.outcomeText(outcome.grade.outcomeKey))
      .font(Typography.rowTitle)
      .foregroundStyle(Theme.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .opacity(shows(.verdict) ? 1 : 0)
      .gatedAnimation(Motion.screenPush, value: shows(.verdict))
  }

  // MARK: - The meters

  /// The two pressure meters, swept at 1500 ms.
  ///
  /// They sweep **from empty**, not from the value before the call: the delta is
  /// stated as a number beside the level, so the bar does not have to encode it — and
  /// no screen in this app ever subtracts one metered value from another (D8).
  ///
  /// The `fear` caption is §5's: it arrives the first time this meter moves, typed in,
  /// and stays for the rest of the career. Before that the meter is a label and a bar,
  /// because a consequence stated before anything has happened is a lecture (§10).
  private func meters(_ outcome: CallOutcome) -> some View {
    let shift = session.shift
    let tuning = model.content.tuning

    return VStack(alignment: .leading, spacing: 16) {
      ForEach(copy.intro.meters.filter { $0.key != .time }, id: \.key) { meter in
        let level = meter.key == .breach ? (shift?.breachRisk ?? 0) : (shift?.noise ?? 0)
        let delta = meter.key == .breach ? outcome.grade.breachDelta : outcome.grade.noiseDelta
        let status = Trace.status(level, tuning)
        let value = copy.render(copy.chromeText("boardMeterValue"), ["n": String(level)])
        let revealed = director.fearRevealed.contains(meter.key.rawValue)

        MeterView(
          label: meter.label,
          valueText: "\(value)  \(deltaText(delta))",
          fraction: Play.meterFraction(level: level, tuning: tuning),
          status: status,
          fear: revealed ? meter.fear : nil,
          fearArriving: revealed && !readOnly,
          spokenValue: "\(value), \(Play.statusLabel(status, copy))",
          numericKey: Double(level))
      }
    }
    .transition(.opacity)
  }

  /// The meter delta, exactly as §2.10's wireframe draws it — **from the bundle**
  /// (P1-6): `+` and `±` are glyphs the deck spends deliberately, and a re-voiced
  /// delta would have been invisible to the copy pipeline.
  private func deltaText(_ delta: Int) -> String {
    delta > 0
      ? copy.render(copy.chromeText("deltaFormat"), ["n": String(delta)])
      : copy.chromeText("deltaZero")
  }

  /// §8 row 6: the screen edge flashes rose **once** behind the breach thud. One
  /// pulse, out slower than in — a wince, not a strobe.
  ///
  /// **Reduce Motion draws no flash at all.** A full-bleed rose border appearing and
  /// vanishing is exactly the class of thing the setting exists to remove, and it is
  /// the one beat of §8 whose information is already carried on two other channels:
  /// the sub thud, the heavy haptic, and — permanently — `BREACH RISK +30` on the
  /// meter under it. Nothing is lost by not flashing it.
  @ViewBuilder private var breachEdge: some View {
    if breachFlashing {
      RoundedRectangle(cornerRadius: 0)
        .strokeBorder(Theme.truePositive.opacity(0.55), lineWidth: 6)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
  }

  /// One flash, then gone.
  private func flashBreachEdge() {
    guard !readOnly, !reduceMotion, !breachFlashing else { return }
    withAnimation(Motion.gated(Motion.breachFlash, reduceMotion: reduceMotion)) {
      breachFlashing = true
    }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(320), tolerance: .zero)
      withAnimation(Motion.gated(Motion.breachFlash, reduceMotion: reduceMotion)) {
        breachFlashing = false
      }
    }
  }

  // MARK: - The lesson

  private func why(_ socCase: SocCase) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      PlayEyebrow(text: copy.chromeText("debriefWhy"))
      Text(socCase.why).prose()
    }
    .transition(.opacity)
  }

  /// The findings that decide this case, marked ✓ pulled / ○ missed (§2.10).
  ///
  /// This is the one place weight is ever revealed: during play `decisive`,
  /// `supporting`, `neutral` and `noise` are indistinguishable (§5.6), which is why a
  /// remembered verdict still has to be proved.
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
      .transition(.opacity)
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

  /// R22: the pointer stays **plain text**. An affiliate link inside the game loop is
  /// an App Store risk and a design-doc violation; the only outbound link in the app
  /// is the privacy policy.
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

  /// §8's last row: the Dock rises last, after the reasoning.
  @ViewBuilder private var dock: some View {
    if shows(.why) {
      PlayDock {
        Dock(title: dockTitle, tone: tone, action: { model.send(.nextCase) })
      }
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  // MARK: - The entry sequence

  /// §8, played by the Director.
  ///
  /// Two cues do **not** come from here. The `file` thud is the reducer's — it fired
  /// on `MAKE_CALL`, which is when the call was actually filed — so the `.cut` beat's
  /// copy of it is silenced. And the verdict chord and the breach thud are the
  /// sequence's, at 900 and 1500, which is why this method no longer fires either of
  /// them itself: a screen that plays its own cues and a sequence that carries them is
  /// how a debrief buzzes twice.
  private func playEntry() {
    guard !readOnly, let outcome else { return }
    director.play(
      Sequences.callSequence(
        breachDelta: outcome.grade.breachDelta,
        verdict: SocCue.verdict(outcome.grade)),
      id: runID, reduceMotion: reduceMotion,
      silencing: [.file])
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
