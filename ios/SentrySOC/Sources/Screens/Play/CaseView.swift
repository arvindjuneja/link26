import SwiftUI
import SentryCore

/// The case — the read (`DESIGN.md` §2.6, §2.8; `SPEC.md` §5.4, §5.6).
///
/// Three things here are structural rather than decorative:
///
/// 1. **The header collapses through `onScrollGeometryChange`** (iOS 18, D14), not
///    through a `GeometryReader` inside the scroll view feeding a preference key.
///    One closure, one `Bool`, no layout pass fighting a scroll.
/// 2. **Coach and Dock are two stacked `.safeAreaInset(edge: .bottom)`** — the fix
///    for `PLAYTEST-lookandfeel.md` P2, made structural: the coach cannot overlap
///    the alert header because it is not in the same layout as the alert header.
///    Order matters — the Dock modifier is applied *last*, so the Dock is the
///    outermost inset and the coach sits directly above it.
/// 3. **EVIDENCE is a tab, not a phase** (§5.6), so the header, the Dock, the
///    heartbeat context and the scroll position are shared between the two halves
///    of the read.
struct CaseView: View {
  let model: GameModel

  enum Tab: Hashable { case sources, evidence }

  /// Which half is showing. Shared with the source sheet, which owns two of the
  /// three ways it changes — see `PlayFocus`.
  @Bindable private var focus = PlayFocus.shared
  @State private var collapsed = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// How far the alert header scrolls away before it becomes one sticky line
  /// (§2.6, verbatim: "after 80 px of scroll").
  private static let collapseThreshold: CGFloat = 80

  private var copy: CopyPack { model.content.copy }
  private var session: SessionState { model.session }
  private var socCase: SocCase? { session.currentCase(model.content) }
  private var revealed: [SocEvidence] { session.revealedEvidence(model.content) }

  var body: some View {
    VStack(spacing: 0) {
      PlayBar(
        model: model, leading: .queuePosition, trace: session.status,
        readout: copy.render(
          copy.chromeText("minutes"),
          ["n": String(session.timeSpentOnCurrentCase(model.content))]))

      if let socCase {
        scroller(socCase)
      } else {
        Spacer(minLength: 0)
      }
    }
    .background(Theme.ground)
    // Applied first → the coach is the INNER inset and lands above the Dock.
    .safeAreaInset(edge: .bottom, spacing: 0) { coach }
    .safeAreaInset(edge: .bottom, spacing: 0) { dock }
    .overlay { scrim }
    // §2.14: the scrim fades in 200 ms, on its own value so nothing else on the
    // case animates when a sheet opens.
    .animation(Motion.gated(Motion.scrim, reduceMotion: reduceMotion), value: session.view)
    .accessibilityIdentifier("screen.case")
  }

  /// §2.5's wireframe, verbatim: while a sheet is up the case behind it is "dimmed
  /// to 40 % · scrim #020408/85".
  ///
  /// It is painted *here* rather than under the presentation because `PhaseHost`
  /// sets `.presentationBackground(.clear)` so the ground reads through the sheet,
  /// and that leaves nothing dimming what is behind it — the board sheet was landing
  /// on an undimmed case with the orange severity chip still at full strength above
  /// it. Every sheet the play phase presents (board · source · call · abandon) sits
  /// over this screen, so one overlay covers all four.
  @ViewBuilder private var scrim: some View {
    if session.view != nil {
      Theme.scrim.opacity(0.85)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
  }

  // MARK: - The read

  private func scroller(_ socCase: SocCase) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          CaseHeader(socCase: socCase, copy: copy)
            .id(Anchor.top)

          PlayHairline()

          SegmentedTabs(
            items: [
              .init(
                id: Tab.sources, title: copy.chromeText("caseSourcesTab"),
                badge: sourcesBadge(socCase)),
              .init(
                id: Tab.evidence, title: copy.chromeText("caseEvidenceTab"),
                badge: String(revealed.count)),
            ],
            selection: $focus.caseTab)

          switch focus.caseTab {
          case .sources: sources(socCase)
          case .evidence:
            EvidenceBoard(
              model: model, socCase: socCase,
              onJumpToSource: { sourceID in jump(to: sourceID, proxy: proxy) })
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
      }
      .scrollBounceBehavior(.basedOnSize)
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top
      } action: { _, offset in
        let next = offset > Self.collapseThreshold
        guard next != collapsed else { return }
        withAnimation(Motion.gated(.snappy(duration: 0.22), reduceMotion: reduceMotion)) {
          collapsed = next
        }
      }
      .overlay(alignment: .top) {
        if collapsed {
          // A short run-off under the bar so the line the header is cutting through
          // dissolves instead of being guillotined mid-x-height.
          CollapsedCaseHeader(socCase: socCase, copy: copy) {
            withAnimation(Motion.gated(Motion.screenPush, reduceMotion: reduceMotion)) {
              proxy.scrollTo(Anchor.top, anchor: .top)
            }
          }
          .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      // A new alert always opens on SOURCES with the header out. (The other two
      // ways the tab changes are the source sheet's two exits — see `PlayFocus`.)
      //
      // Both hooks are needed: `onAppear` catches the common path, where the phase
      // cycles through the debrief between alerts and this screen is rebuilt — and
      // it is the only one that catches a *new shift*, whose first alert is index 0
      // exactly like the last one's, so `onChange` sees nothing move.
      .onAppear {
        if revealed.isEmpty { focus.caseTab = .sources }
        collapsed = false
      }
      .onChange(of: session.shift?.index) { _, _ in
        focus.caseTab = .sources
        collapsed = false
      }
    }
  }

  private func sources(_ socCase: SocCase) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      PlayEyebrow(text: copy.chromeText("caseSourcesEyebrow"))
        .padding(.bottom, 2)

      ForEach(socCase.sources) { source in
        SourceRow(
          label: source.label,
          question: source.question,
          cost: copy.render(copy.chromeText("minutes"), ["n": String(source.cost)]),
          isPulled: session.queried.contains(source.id),
          pulledLabel: copy.chromeText("caseSourcePulled"),
          spokenLabel: copy.render(
            copy.chromeText("caseSourceSpoken"),
            ["label": source.label, "question": source.question, "n": String(source.cost)]),
          spokenHint: copy.chromeText("caseSourceHint"),
          action: { model.send(.openView(.source(source.id))) })
        .id(source.id)
      }
    }
  }

  // MARK: - The two bottom insets

  /// Whether the shift lead is in the player's ear right now. Read twice: once to
  /// draw the bubble, once so the Dock below it does not paint a second fade over
  /// ground the bubble has already covered.
  private var coachStep: CopyPack.CoachStep? {
    guard model.coachIsActive else { return nil }
    return session.currentCoachStep(model.content)
  }

  @ViewBuilder private var coach: some View {
    if let step = coachStep {
      PlayDock {
        CoachBubble(
        eyebrow: copy.chromeText("coachEyebrow"),
        counter: copy.render(
          copy.chromeText("coachStepCount"),
          ["n": String(session.coachStep + 1), "m": String(copy.coachSteps.count)]),
        title: step.title,
        body_: step.body,
        buttonTitle: step.button,
        skipTitle: copy.chromeText("coachSkip"),
        // S4: the step says what advances it. A `button` step routes through
        // CLOSE_VIEW with nothing open, which is the reducer's coach-advance seam —
        // so even "Got it" is one of the seventeen actions.
        onButton: step.button == nil ? nil : { model.send(.closeView) },
        onSkip: { model.send(.setSetting(.coaching, false)) })
        .padding(.bottom, 8)
      }
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  private var dock: some View {
    let armed = !revealed.isEmpty
    return PlayDock(fade: coachStep == nil) {
      // BLOCKED ON C1/F1: `dockArmed` is `{n} findings · {t}m` with no singular, so
      // the hint reads `1 findings · 10m` after the first pull. See the note in
      // `EvidenceBoard`; a `dockArmedOne` key turns this into a two-line branch.
      Dock(
        title: copy.chromeText("makeTheCall"),
        hint: armed
          ? copy.render(
            copy.chromeText("dockArmed"),
            [
              "n": String(revealed.count),
              "t": String(session.timeSpentOnCurrentCase(model.content)),
            ])
          : copy.chromeText("investigateFirst"),
        isEnabled: armed,
        action: { model.send(.openView(.call)) })
    }
  }

  // MARK: - Helpers

  private enum Anchor { static let top = "case.header" }

  private func sourcesBadge(_ socCase: SocCase) -> String {
    let pulled = socCase.sources.filter { session.queried.contains($0.id) }.count
    return copy.render(
      copy.chromeText("queueCount"),
      ["n": String(pulled), "m": String(socCase.sources.count)])
  }

  /// §2.8: tapping a `FROM` header jumps back to that row in SOURCES. The tab has to
  /// change before the row exists to scroll to, so the scroll is deferred one turn
  /// rather than fired into a `LazyVStack` that has not built it yet.
  private func jump(to sourceID: String, proxy: ScrollViewProxy) {
    withAnimation(Motion.gated(Motion.screenPush, reduceMotion: reduceMotion)) {
      focus.caseTab = .sources
    }
    Task { @MainActor in
      withAnimation(Motion.gated(Motion.screenPush, reduceMotion: reduceMotion)) {
        proxy.scrollTo(sourceID, anchor: .top)
      }
    }
  }
}

// MARK: - The header

/// The alert as it arrives: the tool's guess, the rule that fired, the title, what
/// tripped it, and the asset.
///
/// The severity chip is `orange` at High (R2) because that is what the exported
/// `severityMeta` says — and it is drawn as an *outline* chip, the deck's shape for
/// "a claim the tool is making", against the filled chips a decided value gets.
private struct CaseHeader: View {
  let socCase: SocCase
  let copy: CopyPack

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        let severity = copy.severity(socCase.toolSeverity)
        Chip(
          text: copy.render(
            copy.chromeText("caseSeverityChip"), ["severity": severity.label]),
          tone: Theme.tone(severity.tone),
          style: .outline)

        if socCase.handoff != nil {
          Chip(
            text: copy.chromeText("caseHandoffChip"), tone: Theme.crossover,
            style: .filled, tracked: false)
        }

        Spacer(minLength: 0)
      }

      Text(socCase.detectionRule)
        .font(Typography.meta)
        .foregroundStyle(Theme.textQuiet)
        .fixedSize(horizontal: false, vertical: true)

      Text(socCase.alertTitle)
        .font(Typography.screenTitle)
        .foregroundStyle(Theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text(socCase.trigger)
        .prose(Theme.textSecondary)

      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(copy.chromeText("caseAsset")).trackedLabel(Theme.textDisabled)
        // §5.4: `soc-phish-harvest`'s sender is a 33-character unbreakable token, so
        // the asset line is never line-limited and is allowed to tighten instead.
        Text(socCase.asset)
          .font(Typography.meta)
          .foregroundStyle(Theme.textTertiary)
          .lineLimit(nil)
          .allowsTightening(true)
          .minimumScaleFactor(0.75)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }
}

/// One sticky line after 80 pt of scroll (§2.6): the tool's guess and the title,
/// with a tap that takes the header back.
private struct CollapsedCaseHeader: View {
  let socCase: SocCase
  let copy: CopyPack
  let onTap: () -> Void

  var body: some View {
    let severity = copy.severity(socCase.toolSeverity)

    Button(action: onTap) {
      HStack(spacing: 10) {
        Text(severity.label)
          .trackedLabel(Theme.tone(severity.tone), scale: 0.8)
          .layoutPriority(1)

        Text(socCase.alertTitle)
          .font(Typography.metaProse)
          .foregroundStyle(Theme.textSecondary)
          .lineLimit(1)
          .truncationMode(.tail)

        Spacer(minLength: 4)

        Text(Glyph.back)
          .font(Typography.meta)
          .foregroundStyle(Theme.textDisabled)
          .rotationEffect(.degrees(90))
      }
      .padding(.horizontal, 20)
      .frame(maxWidth: .infinity, minHeight: Theme.Hit.minimum)
      .background {
        Theme.ground.opacity(0.96)
          .background(.ultraThinMaterial)
      }
      .overlay(alignment: .bottom) {
        VStack(spacing: 0) {
          Rectangle().fill(Theme.hairline).frame(height: 1)
          LinearGradient(
            colors: [Theme.ground, Theme.ground.opacity(0)],
            startPoint: .top, endPoint: .bottom)
            .frame(height: 14)
        }
        .offset(y: 15)
        .allowsHitTesting(false)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle(weight: .control, cornerRadius: 0, showsFill: false))
    .accessibilityLabel("\(severity.label). \(socCase.alertTitle)")
    .accessibilityIdentifier("case.collapsedHeader")
  }
}
