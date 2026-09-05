import SwiftUI
import SentryCore

/// The shift summary — 16:00 handover (`DESIGN.md` §2.11, `SPEC.md` §5.9).
///
/// **The career is already persisted when this draws.** `scoreShift →
/// awardForShift → unlock diff` all happened inside the reducer and arrived as
/// `session.settlement`; `.settleShift`, `.persistCareer` and `.clearSession` ran
/// before the first frame of this screen. A force-quit here loses nothing, and this
/// view awards nothing — it reads a value.
///
/// The ladder disclosure carries the Appendix-A G21 framing **verbatim from the
/// bundle**: BTL1 / NICE "Cyber Defense Analyst", and *"not a certification, not a
/// training platform, and it makes no claims about hiring or pay"*. That sentence is
/// a credibility guardrail asserted by the drift guard, so it is rendered, never
/// re-typed.
struct ShiftSummaryView: View {
  let model: GameModel

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var countedCash = 0
  @State private var countedStanding = 0
  @State private var sweptStanding = false

  private var copy: CopyPack { model.content.copy }
  private var session: SessionState { model.session }
  private var settlement: ShiftSettlement? { session.settlement }

  var body: some View {
    ZStack {
      Theme.ground.ignoresSafeArea()

      VStack(spacing: 0) {
        PlayBar(
          model: model, leading: .wordmark, trace: .calm, tracePaused: true, readout: queuePosition)

        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            if let settlement {
              grade(settlement)
              tiles(settlement)
              investigation(settlement)
              payout(settlement)
              unlocks(settlement)
              board(settlement)
              ladder
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
    .safeAreaInset(edge: .bottom) {
      PlayDock {
        Dock(
          title: Play.cta(copy.chromeText("summaryBack")),
          action: { model.send(.nextCase) })
      }
    }
    .onAppear(perform: playEntry)
    .accessibilityIdentifier("screen.shiftSummary")
  }

  // MARK: - The grade

  private func grade(_ settlement: ShiftSettlement) -> some View {
    let meta = copy.gradeMeta[settlement.score.grade]

    return VStack(spacing: 12) {
      Text(copy.summary.eyebrow).trackedLabel()

      Text(meta?.label ?? settlement.score.grade.rawValue)
        .font(Typography.grade)
        .foregroundStyle(Theme.tone(meta?.tone ?? .cyan))
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.7)
        .fixedSize(horizontal: false, vertical: true)

      Text(meta?.line ?? "")
        .prose(Theme.textTertiary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  // MARK: - The scoreline

  /// The four tiles' identity, and nothing else's.
  ///
  /// `StatTileGrid.Item.id` is a `String`, and S1 forbids a string literal in
  /// `Screens/`, so the id has to come from something the compiler writes. A
  /// `String`-raw-valued enum with implicit raw values gives one that *means* what it
  /// says (`accuracy`, `calls`, …) — the earlier version borrowed
  /// `CopyPack.MeterKey` and `SocVerdict` raw values, which passed the same grep but
  /// read as a mis-wiring and would have been a real bug the day `StatTileGrid` keyed
  /// any behaviour off the id.
  private enum StatID: String {
    case accuracy, calls, missed, falseEscalations
  }

  private func tiles(_ settlement: ShiftSettlement) -> some View {
    let score = settlement.score
    let clean = score.accuracy >= model.content.tuning.shift.cleanAccuracy

    return StatTileGrid(items: [
      .init(
        id: StatID.accuracy.rawValue,
        value: copy.render(
          copy.chromeText("boardMeterValue"), ["n": Play.percent(score.accuracy)]),
        label: copy.chromeText("statAccuracy"),
        tone: clean ? Theme.benign : Theme.pressure,
        numericKey: score.accuracy),
      .init(
        id: StatID.calls.rawValue,
        value: copy.render(
          copy.chromeText("queueCount"),
          ["n": String(score.total), "m": String(session.shift?.caseIds.count ?? score.total)]),
        label: copy.chromeText("statCalls"),
        numericKey: Double(score.total)),
      .init(
        id: StatID.missed.rawValue,
        value: String(score.missedDetections),
        label: copy.chromeText("statMissed"),
        tone: score.missedDetections == 0 ? Theme.benign : Theme.truePositive,
        numericKey: Double(score.missedDetections)),
      .init(
        id: StatID.falseEscalations.rawValue,
        value: String(score.falseEscalations),
        label: copy.chromeText("statFalseEscalations"),
        tone: score.falseEscalations == 0 ? Theme.benign : Theme.truePositive,
        numericKey: Double(score.falseEscalations)),
    ])
  }

  /// How much of the case was actually read — the line that makes a remembered
  /// verdict insufficient. A blind call is called out in rose: right by luck is not
  /// right (§4.1).
  private func investigation(_ settlement: ShiftSettlement) -> some View {
    let score = settlement.score

    return VStack(alignment: .leading, spacing: 5) {
      Text(
        copy.render(
          copy.summary.investigationLine,
          ["pct": Play.percent(score.investigationRate)])
      )
      .font(Typography.meta)
      .foregroundStyle(Theme.textQuiet)
      .fixedSize(horizontal: false, vertical: true)

      if score.blindCalls > 0 {
        Text(copy.render(copy.summary.blindLine, ["blind": blindClause(score.blindCalls)]))
          .font(Typography.meta)
          .foregroundStyle(Theme.truePositive)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func blindClause(_ count: Int) -> String {
    count == 1
      ? copy.chromeText("summaryBlindOne")
      : copy.render(copy.chromeText("summaryBlindMany"), ["n": String(count)])
  }

  // MARK: - The payout

  private func payout(_ settlement: ShiftSettlement) -> some View {
    let reward = settlement.reward
    let before = settlement.careerBefore.standing
    let after = reward.state.standing
    let next = model.rules.nextRank(after)

    return VStack(alignment: .leading, spacing: 12) {
      PlayEyebrow(text: copy.chromeText("summaryPayout"), tone: Theme.benign)

      HStack(alignment: .firstTextBaseline, spacing: 18) {
        Text(copy.render(copy.chromeText("summaryCash"), ["n": String(countedCash)]))
          .font(Typography.hero)
          .tabularNumbers()
          .foregroundStyle(Theme.benign)
          .contentTransition(.numericText(value: Double(countedCash)))

        Text(copy.render(copy.chromeText("summaryStanding"), ["n": String(countedStanding)]))
          .font(Typography.rowTitle)
          .tabularNumbers()
          .foregroundStyle(Theme.textSecondary)
          .contentTransition(.numericText(value: Double(countedStanding)))

        Spacer(minLength: 0)
      }

      standingBar(before: before, after: after, threshold: next?.min)

      if let rankUp = reward.rankUp {
        Text(copy.render(copy.chromeText("summaryPromoted"), ["rank": rankUp.label]))
          .font(Typography.meta)
          .foregroundStyle(Theme.crossover)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The standing bar sweeps old → new. `Play.standingFraction` is the only place a
  /// career number becomes a width; the numbers themselves came off
  /// `CareerRules.awardForShift` inside the reducer.
  ///
  /// **Known gap, left as-is for v1 (C1/C11):** the `before → after` caption below
  /// the bar is assembled in Swift. It is §2.11's wireframe verbatim and carries no
  /// word, so the S1 grep passes it — see the same note on `DebriefView.deltaText`.
  /// A `standingSweep` chrome key with `{before}`/`{after}` would close it.
  private func standingBar(before: Int, after: Int, threshold: Int?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule(style: .continuous).fill(Theme.Zinc.z800.opacity(0.55))
          Capsule(style: .continuous)
            .fill(Theme.benign.opacity(0.85))
            .frame(
              width: Play.standingFraction(
                value: sweptStanding ? after : before, threshold: threshold)
                * geometry.size.width)
        }
      }
      .frame(height: 4)
      .gatedAnimation(Motion.payout, value: sweptStanding)

      Text("\(before) → \(after)")
        .font(Typography.meta)
        .tabularNumbers()
        .foregroundStyle(Theme.textDisabled)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(copy.chromeText("standingHint"))
    .accessibilityValue(String(after))
  }

  // MARK: - What opened

  @ViewBuilder private func unlocks(_ settlement: ShiftSettlement) -> some View {
    if !settlement.unlocked.isEmpty {
      VStack(spacing: 8) {
        ForEach(settlement.unlocked, id: \.id) { unlocked in
          HStack(alignment: .top, spacing: 12) {
            Text(copy.chromeText("summaryUnlocked")).trackedLabel(Theme.crossover)
            Text(
              copy.render(
                copy.chromeText("summaryUnlockedLine"), ["queue": unlocked.label])
            )
            .font(Typography.metaProse)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .panelCard(fill: Theme.crossover.opacity(0.07), stroke: Theme.crossover.opacity(0.35))
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  // MARK: - The board

  /// Every call of the shift as one glyph, each a way back into its own debrief
  /// (`VIEW_RESULT`, read-only).
  private func board(_ settlement: ShiftSettlement) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      PlayEyebrow(text: copy.chromeText("summaryBoard"))

      HStack(spacing: 6) {
        ForEach(session.shift?.results ?? [], id: \.caseId) { result in
          Button {
            model.send(.viewResult(result.caseId))
          } label: {
            Text(result.verdictCorrect ? Glyph.correct : Glyph.wrong)
              .font(Typography.metaStrong)
              .foregroundStyle(result.verdictCorrect ? Theme.benign : Theme.truePositive)
              .frame(width: Theme.Hit.minimum, height: Theme.Hit.minimum)
              .panelCard(cornerRadius: Theme.Radius.chip, fill: Theme.panel)
              .contentShape(Rectangle())
          }
          .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
          .accessibilityLabel(
            model.content.case(result.caseId)?.alertTitle ?? result.caseId)
          .accessibilityIdentifier("summary.boardGlyph")
        }
        Spacer(minLength: 0)
      }
    }
  }

  // MARK: - The ladder

  private var ladder: some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 10) {
        RichTextView(segments: copy.ladder.body)
        Text(copy.ladder.note).quietLog(Theme.textQuiet)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 10)
    } label: {
      Text(copy.ladder.eyebrow)
        .trackedLabel(Theme.textTertiary)
        .frame(minHeight: Theme.Hit.minimum)
    }
    .tint(Theme.textTertiary)
    .padding(.horizontal, 14)
    .padding(.vertical, 4)
    .panelCard()
    .accessibilityIdentifier("summary.ladder")
  }

  // MARK: - Entry

  /// The 800 ms count-up, and the one cue the shift ends on.
  private func playEntry() {
    guard let settlement else { return }
    model.feel(SocCue.shift(settlement.score.grade))

    guard !reduceMotion else {
      countedCash = settlement.reward.cashGain
      countedStanding = settlement.reward.standingGain
      sweptStanding = true
      model.feel(.commitSoft)
      return
    }

    withAnimation(Motion.payout) {
      countedCash = settlement.reward.cashGain
      countedStanding = settlement.reward.standingGain
      sweptStanding = true
    }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(0.80))
      model.feel(.commitSoft)
    }
  }

  private var queuePosition: String? {
    guard let shift = session.shift else { return nil }
    return copy.render(
      copy.chromeText("queueCount"),
      ["n": String(shift.results.count), "m": String(shift.caseIds.count)])
  }
}
