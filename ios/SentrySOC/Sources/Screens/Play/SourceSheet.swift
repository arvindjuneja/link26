import SwiftUI
import SentryCore

/// Which half of the case the player is looking at.
///
/// It lives outside `CaseView` because two surfaces decide it: the case's own
/// segmented control, and the source sheet's two exits — "To the board" lands on
/// EVIDENCE (§2.7), "Pull another" goes back to SOURCES. A sheet cannot reach into
/// the phase underneath it, and neither one may edit the other's file, so the
/// decision is one small observed value rather than a callback chain.
@Observable @MainActor final class PlayFocus {
  static let shared = PlayFocus()
  var caseTab: CaseView.Tab = .sources
  init() {}
}

/// The source sheet — the commit (`DESIGN.md` §2.7, `SPEC.md` §5.5).
///
/// One sheet, two states: the cost you are about to spend, and what the log said.
/// It **grows** from 320 pt to `.large` when the pull lands — the native form of the
/// web's "same sheet, the CTA morphs" — so the findings arrive in the room they
/// need instead of in a letterbox.
///
/// Findings enter staggered at 45 ms and each fires `findingLand`, **capped at
/// three**: a six-finding pull would otherwise be a buzz rather than three taps on
/// the shoulder. `evidence.detail` is never truncated — it is the puzzle.
struct SourceSheet: View {
  let model: GameModel
  let sourceID: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// **Not `send(.closeView)`.** `PhaseHost` binds `.sheet(item:)` to `session.view`
  /// and dispatches `CLOSE_VIEW` from the binding's setter when the sheet goes away,
  /// so a button that *also* sends it fires the action twice — and the second one
  /// arrives with nothing open, which is the reducer's coach-advance seam (S4). The
  /// symptom, seen on the simulator: pulling one source and tapping "To the board"
  /// skipped the coach straight from step 1 to step 3. Dismissing the presentation
  /// lets the host send the one action.
  @Environment(\.dismiss) private var dismiss
  @State private var querying = false
  /// How many findings have landed. Drives both the reveal and the cue count.
  @State private var landed = 0
  /// §5.5's growth, expressed the way SPEC §4.2 prescribes: one detent SET and a
  /// selection that moves. See the note on `body`.
  @State private var detent: PresentationDetent = SourceSheet.sheetShortDetent

  /// §5.5: at most three cues per pull.
  private static let findingLandCap = 3
  private static let sheetShortDetent = PresentationDetent.height(320)

  private var copy: CopyPack { model.content.copy }
  private var session: SessionState { model.session }
  private var source: DataSource? { model.content.sourcesByID[sourceID] }
  private var isPulled: Bool { session.queried.contains(sourceID) }
  private var findings: [SocEvidence] {
    session.currentCase(model.content)?.findings(from: sourceID) ?? []
  }

  var body: some View {
    SheetChrome(eyebrow: copy.chromeText("sourceSheetEyebrow")) {
      VStack(alignment: .leading, spacing: 18) {
        if let source {
          question(source)
          cost(source)
        }
        if querying { progress }
        if landed > 0 { surfaced }
      }
    } footer: {
      footer
    }
    // §5.5 / SPEC §4.2: the sheet **grows to `.large` when the pull lands** —
    // `presentationDetents(_:selection:)`, a fixed set with a moving selection.
    //
    // The first cut changed the SET instead (`isPulled ? [.large] : [.height(320)]`)
    // on the theory that a single-element set cannot fall out of sync with the
    // presentation controller. It cannot, but it also never took effect, and the
    // finding card — which §5.5 calls the puzzle — sat entirely behind the footer at
    // 320 pt. Measured on the simulator, the rule is: the OUTER
    // `presentationDetents` set wins (`PhaseHost` applies `[.height(320), .large]`
    // to this same hierarchy), and a `selection` binding is honoured only for
    // detents that are in the winning set. Both of ours are, because §4.2 hands
    // `.source` exactly that pair — so this line moves the sheet, and it stays
    // correct as long as `PhaseHost` keeps §4.2's set. If that set ever changes, the
    // selection silently falls back to the smallest detent; the check is one pull on
    // the simulator.
    .presentationDetents([Self.sheetShortDetent, .large], selection: $detent)
    .onAppear {
      // Re-opening a source that was already pulled shows its findings at rest: the
      // ceremony belongs to the commit, and this is not one.
      if isPulled, landed == 0 { landed = findings.count }
      if isPulled { detent = .large }
    }
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

  /// What it costs, and what it will have cost. The preview segment is the same
  /// cyan at 40 % — the deck's shape for "not yet spent".
  private func cost(_ source: DataSource) -> some View {
    let budget = session.shift?.timeBudget ?? 0
    let used = (session.shift?.timeUsed ?? 0) + session.timeSpentOnCurrentCase(model.content)
    let after = isPulled ? used : used + source.cost

    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(copy.render(copy.chromeText("sourceCost"), ["n": String(source.cost)]))
          .trackedLabel(Theme.falsePositive)
        Spacer(minLength: 8)
        Text(
          copy.render(
            copy.chromeText("sourceUsed"), ["n": String(used), "m": String(budget)])
        )
        .trackedLabel(Theme.textDisabled)
      }

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule(style: .continuous).fill(Theme.Zinc.z800.opacity(0.55))
          Capsule(style: .continuous)
            .fill(Theme.falsePositive.opacity(0.40))
            .frame(width: Play.timeFraction(used: after, budget: budget) * geometry.size.width)
          Capsule(style: .continuous)
            .fill(Theme.falsePositive.opacity(0.85))
            .frame(width: Play.timeFraction(used: used, budget: budget) * geometry.size.width)
        }
      }
      .frame(height: 4)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: - The pull

  private var progress: some View {
    VStack(alignment: .leading, spacing: 8) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule(style: .continuous).fill(Theme.Zinc.z800.opacity(0.55))
          Capsule(style: .continuous)
            .fill(Theme.falsePositive)
            .frame(width: querying ? geometry.size.width : 0)
        }
      }
      .frame(height: 4)

      Text(
        copy.render(copy.chromeText("sourceQuerying"), ["source": source?.label ?? ""])
      )
      .quietLog(Theme.textQuiet)
    }
    .transition(.opacity)
    .accessibilityIdentifier("source.querying")
  }

  private var surfaced: some View {
    VStack(alignment: .leading, spacing: 10) {
      PlayEyebrow(text: surfacedLabel, tone: Theme.benign)

      ForEach(Array(findings.prefix(landed))) { finding in
        EvidenceCard(label: finding.label, detail: finding.detail)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var surfacedLabel: String {
    let count = findings.count
    return count == 1
      ? copy.chromeText("sourceFindingOne")
      : copy.render(copy.chromeText("sourceFindingMany"), ["n": String(count)])
  }

  // MARK: - The footer

  @ViewBuilder private var footer: some View {
    if isPulled {
      VStack(spacing: 0) {
        Dock(
          title: Play.cta(copy.chromeText("sourceToBoard")),
          tone: Theme.falsePositive,
          action: {
            PlayFocus.shared.caseTab = .evidence
            dismiss()
          })

        Button {
          PlayFocus.shared.caseTab = .sources
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
    } else {
      Dock(
        title: Play.cta(copy.chromeText("sourcePull")),
        tone: Theme.falsePositive,
        action: pull)
    }
  }

  // MARK: - The commit

  /// The pull itself is one action; everything after it is presentation.
  ///
  /// The 600 ms query and the 45 ms stagger are the *only* place in the deck where a
  /// screen holds a timer, and they hold nothing the machine needs: the session
  /// already contains the finding the moment `PULL_SOURCE` returns, so a player who
  /// dismisses the sheet mid-query loses no state at all.
  private func pull() {
    guard !isPulled else { return }
    model.send(.pullSource(sourceID))
    PlayFocus.shared.caseTab = .evidence
    // The room arrives with the findings, not after them.
    withAnimation(Motion.gated(Motion.sheet, reduceMotion: reduceMotion)) {
      detent = .large
    }

    guard !reduceMotion else {
      landed = findings.count
      fireLandingCues(upTo: findings.count)
      return
    }

    withAnimation(Motion.queryProgress) { querying = true }

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(0.60))
      withAnimation(Motion.gated(Motion.findingLand, reduceMotion: reduceMotion)) {
        querying = false
      }
      for index in findings.indices {
        if index > 0 {
          try? await Task.sleep(for: .seconds(Motion.findingStagger))
        }
        withAnimation(Motion.gated(Motion.findingLand, reduceMotion: reduceMotion)) {
          landed = index + 1
        }
        if index < Self.findingLandCap { model.feel(.findingLand) }
      }
    }
  }

  private func fireLandingCues(upTo count: Int) {
    for _ in 0..<min(count, Self.findingLandCap) { model.feel(.findingLand) }
  }
}
