import SwiftUI
import SentryCore

/// The source sheet — the commit (`DESIGN.md` §2.7, `SPEC.md` §5.5), rebuilt to
/// `FEEL.md` §4.
///
/// **A pull is a query, and a query is a moment.** What shipped was a 600 ms
/// determinate progress bar — the most honest possible way to say *nothing is
/// happening, please wait*. §4 replaces it with the thing the fiction says is
/// happening: a log pane that streams, addressed to this asset, over this window,
/// while the shift clock in the strip above counts the cost out one minute at a time.
/// Then `RESULTS`, the sheet grows, and the findings land one at a time.
///
/// Three properties make the pane trustworthy rather than decorative:
///
/// 1. **Seeded.** The lines, their jitter and their numbers come from
///    `Director.pullSeed(caseID:sourceID:)`, so re-reading a pull reads the same and
///    two sources never stream in step.
/// 2. **Costed.** The stream's length is `Sequences.pullDurationMs(cost:isRepeat:)` —
///    a 12-minute pull takes longer than a 6-minute one, and a second pull in the
///    same case is 25 % faster, because the player has the shape of it now.
/// 3. **Truthful.** `PULL_SOURCE` is dispatched before the first log line, so the
///    session already holds the finding while the pane is still writing. A player who
///    swipes the sheet away mid-query has paid and has the evidence.
///
/// `evidence.detail` is never truncated — it is the puzzle. The weight badge is never
/// drawn: during play `decisive`, `supporting`, `neutral` and `noise` look identical
/// (§5.6), which is what makes a remembered verdict still have to be proved.
struct SourceSheet: View {
  let model: GameModel
  let sourceID: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// **Not `send(.closeView)`.** `PhaseHost` binds `.sheet(item:)` to `session.view`
  /// and dispatches `CLOSE_VIEW` from the binding's setter when the sheet goes away,
  /// so a button that *also* sends it fires the action twice (P1-1).
  @Environment(\.dismiss) private var dismiss
  /// §5.5's growth, expressed the way SPEC §4.2 prescribes: one detent SET and a
  /// selection that moves.
  @State private var detent: PresentationDetent = SourceSheet.sheetShortDetent
  /// The pane this pull is writing, resolved once when the pull starts so the copy is
  /// rendered rather than re-rendered on every beat.
  @State private var lines: [String] = []

  private static let sheetShortDetent = PresentationDetent.height(320)

  private var copy: CopyPack { model.content.copy }
  private var session: SessionState { model.session }
  private var director: Director { model.director }
  private var source: DataSource? { model.content.sourcesByID[sourceID] }
  private var socCase: SocCase? { session.currentCase(model.content) }
  private var isPulled: Bool { session.queried.contains(sourceID) }
  private var findings: [SocEvidence] {
    socCase?.findings(from: sourceID) ?? []
  }

  /// §4's sequence, addressed by the pull it performs.
  private var runID: String { Director.pullID(case: socCase?.id ?? "", source: sourceID) }
  /// Whether this pull has started at all — the sheet is showing a query rather than
  /// an offer. `shows(_:of:)` and not `runID ==`, so it stays true after another
  /// sequence takes the clock.
  private var hasRun: Bool { director.shows(.queryOpen, of: runID) }
  /// True from the sheet opening until the `RESULTS` header lands.
  private var querying: Bool { hasRun && !director.shows(.results, of: runID) }

  var body: some View {
    SheetChrome(eyebrow: eyebrow, tone: querying ? Theme.falsePositive : Theme.benign) {
      VStack(alignment: .leading, spacing: 18) {
        if let source, !isPulled {
          question(source)
        }
        // The cost block stays up **through** the query (§4): the count-up is the
        // point, and hiding it the moment `PULL_SOURCE` lands took the shift clock off
        // the sheet exactly when it started moving. It goes when the results arrive,
        // because by then the minutes are spent and the findings are what matters.
        if let source, !isPulled || querying {
          cost(source)
        }
        if hasRun { logPane }
        if landed > 0 { surfaced }
      }
    } footer: {
      footer
    }
    // §5.5 / SPEC §4.2: the sheet **grows to `.large` when the pull lands** —
    // `presentationDetents(_:selection:)`, a fixed set with a moving selection. The
    // OUTER set wins (`PhaseHost` applies §4.2's `[.height(320), .large]` to this same
    // hierarchy) and a selection is honoured only for detents inside it; both of ours
    // are. Measured on the simulator — see the P1 note in git history.
    .presentationDetents([Self.sheetShortDetent, .large], selection: $detent)
    .onAppear(perform: start)
    .onDisappear { director.settleClock() }
    .accessibilityIdentifier("sheet.source")
  }

  // MARK: - Before the pull

  private func question(_ source: DataSource) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(source.label)
        .font(Typography.rowTitle)
        .foregroundStyle(Theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text(source.question)
        .font(Typography.body)
        .italic()
        .lineSpacing(Typography.bodyLineSpacing)
        .foregroundStyle(Theme.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  /// What it cost, counted out. The `USED` figure runs behind the session by
  /// `director.clockHeld` while the pane streams, so the number here and the number in
  /// the strip above the sheet are the same number moving together (§4).
  private func cost(_ source: DataSource) -> some View {
    let budget = session.shift?.timeBudget ?? 0
    let spent = shiftMinutes
    let after = spent + director.clockHeld

    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(copy.render(copy.chromeText("sourceCost"), ["n": String(source.cost)]))
          .trackedLabel(Theme.falsePositive)
        Spacer(minLength: 8)
        Text(
          copy.render(
            copy.chromeText("sourceUsed"), ["n": String(spent), "m": String(budget)])
        )
        .trackedLabel(Theme.textDisabled)
        .contentTransition(.numericText(value: Double(spent)))
      }

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule(style: .continuous).fill(Theme.Zinc.z800.opacity(0.55))
          Capsule(style: .continuous)
            .fill(Theme.falsePositive.opacity(0.40))
            .frame(width: Play.timeFraction(used: after, budget: budget) * geometry.size.width)
          Capsule(style: .continuous)
            .fill(Theme.falsePositive.opacity(0.85))
            .frame(width: Play.timeFraction(used: spent, budget: budget) * geometry.size.width)
        }
      }
      .frame(height: 4)
      .gatedAnimation(Motion.beatArrive, value: spent)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: - §4 · the log pane

  /// Four to six lines, streaming. Mono, dim, and addressed to the case in hand — the
  /// point is not that the player reads them but that the desk is visibly *doing the
  /// thing the cost is for*.
  private var logPane: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
        if director.shows(.logLine(index), of: runID) {
          Text(line)
            .font(Typography.quietLog)
            .foregroundStyle(Theme.textQuiet)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .panelCard(fill: Theme.panel.opacity(0.7), stroke: Theme.hairline.opacity(0.7))
    // §4's last line: tap the log pane to skip to the results.
    .contentShape(Rectangle())
    .onTapGesture {
      director.skip()
      director.settleClock()
      detent = .large
    }
    .accessibilityIdentifier("source.querying")
    .accessibilityHidden(true)
  }

  // MARK: - The findings

  /// How many cards have landed — read off the Director rather than counted here, so
  /// the ≤3 solo cap and the "then the rest together" of §4 are the sequence's rule
  /// and not a second copy of it.
  private var landed: Int {
    guard hasRun else { return isPulled ? findings.count : 0 }
    return findings.indices.filter { director.shows(.card($0), of: runID) }.count
  }

  private var surfaced: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(findings.prefix(landed))) { finding in
        EvidenceCard(label: finding.label, detail: finding.detail)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - The footer

  @ViewBuilder private var footer: some View {
    if isPulled, !querying {
      VStack(spacing: 0) {
        Dock(
          title: Play.cta(copy.chromeText("sourceToBoard")),
          tone: Theme.falsePositive,
          action: {
            model.play.caseTab = .evidence
            dismiss()
          })

        Button {
          model.play.caseTab = .sources
          dismiss()
        } label: {
          Text(copy.chromeText("sourcePullAnother"))
            .font(Typography.meta)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 12)
            .minimumHitTarget()
        }
        .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
        .padding(.bottom, 6)
        .accessibilityIdentifier("source.pullAnother")
      }
      .transition(.opacity)
    } else if !isPulled {
      Dock(
        title: Play.cta(copy.chromeText("sourcePull")),
        tone: Theme.falsePositive,
        action: pull)
    }
  }

  // MARK: - The commit

  /// The sheet opened. A source that has already been pulled shows its findings at
  /// rest — the ceremony belongs to the commit, and a re-read is not one.
  private func start() {
    guard isPulled else { return }
    detent = .large
  }

  /// One action, then the performance.
  ///
  /// `PULL_SOURCE` first — the session is truthful from this line on. Then the pane,
  /// the clock and the cards, which are all presentation and hold nothing the machine
  /// needs.
  private func pull() {
    guard !isPulled, let socCase, let source else { return }

    // "Second and later pulls in the same case are 25 % faster" (§4). Counted BEFORE
    // the action, because after it this one is in the set.
    let already = socCase.sources.filter { session.queried.contains($0.id) }.count
    let seed = Director.pullSeed(caseID: socCase.id, sourceID: sourceID)
    let duration = Sequences.pullDurationMs(cost: source.cost, isRepeat: already > 0)

    model.send(.pullSource(sourceID))
    model.play.caseTab = .evidence

    let beats = Sequences.pullSequence(
      cost: source.cost, isRepeat: already > 0, seed: seed,
      findingCount: findings.count,
      hasDecisive: Director.hasDecisive(socCase, from: sourceID))

    lines = queryLines(socCase, source, count: logLineCount(beats))
    director.countUpClock(cost: source.cost, overMs: duration, reduceMotion: reduceMotion)
    director.play(beats, id: runID, reduceMotion: reduceMotion)

    // The room arrives with the results, not before them: the sheet is 320 pt while
    // the pane streams and `.large` when there is something to read in it.
    Task { @MainActor in
      if !reduceMotion {
        try? await Task.sleep(for: .milliseconds(duration), tolerance: .zero)
      }
      withAnimation(Motion.gated(Motion.sheet, reduceMotion: reduceMotion)) {
        detent = .large
      }
    }
  }

  // MARK: - Derived

  private var eyebrow: String {
    guard hasRun, querying else {
      return isPulled
        ? copy.plural(FeelCopyKey.queryResults, findings.count)
        : copy.chromeText("sourceSheetEyebrow")
    }
    return copy.render(
      copy.chromeText(FeelCopyKey.queryHeader), ["source": source?.label ?? ""])
  }

  /// The shift clock, as the strip above the sheet draws it: what the session has
  /// spent, minus what the count-up has not reached yet.
  private var shiftMinutes: Int {
    director.clockReading(
      (session.shift?.timeUsed ?? 0) + session.timeSpentOnCurrentCase(model.content))
  }

  private func logLineCount(_ beats: [Beat]) -> Int {
    beats.reduce(0) { count, beat in
      if case .logLine = beat.kind { return count + 1 }
      return count
    }
  }

  /// The pane, rendered.
  ///
  /// The templates and their order are `FeelCopyKey.queryLines` — the roster lives in
  /// `SentryCore/Feel/` next to the sequence that reads it, so no screen ever builds
  /// `"queryLine\(i)"` and S1 stays true of the pull as well as of everything else.
  /// The four placeholders are the four §4 names and no others.
  private func queryLines(_ socCase: SocCase, _ source: DataSource, count: Int) -> [String] {
    let window = copy.chromeText(FeelCopyKey.queryWindow)
    let host = Director.host(of: socCase.asset)
    return (0..<min(count, FeelCopyKey.queryLines.count)).map { index in
      copy.render(
        copy.chromeText(FeelCopyKey.queryLines[index]),
        [
          "asset": host,
          "source": source.id,
          "window": window,
          "n": String(
            Director.logNumber(caseID: socCase.id, sourceID: source.id, line: index)),
        ])
    }
  }
}
