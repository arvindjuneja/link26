import SwiftUI
import SentryCore

/// The case — the read (`DESIGN.md` §2.6, §2.8; `SPEC.md` §5.4, §5.6), rebuilt to
/// `FEEL.md` §2, §3, §6 and §7.
///
/// **Every case now starts as an event, not a page** (§2). The screen cuts to the
/// ground colour, the ECG spikes, and the alert assembles itself in reading order:
/// the raw trigger types in first, in the log's own voice; then what it is called and
/// what it happened to; then — last — what the tool made of it, stamped in. The
/// SOURCES list rises collapsed under it, and on shift 1 the lead's line arrives after
/// everything else.
///
/// **That order is an inversion, and it is deliberate.** The old header led with the
/// severity chip, which is the deck teaching the exact habit it exists to break: the
/// tool's severity is a *guess* (`intro.severity`), and a screen that prints the guess
/// first has already framed the read. §2's timeline puts the evidence at 260 ms and
/// the guess at 1500, so the player meets the event before the opinion.
///
/// Four things are structural rather than decorative:
///
/// 1. **The header collapses through `onScrollGeometryChange`** (iOS 18, D14).
/// 2. **Coach and Dock are two stacked `.safeAreaInset(edge: .bottom)`** — the fix
///    for `PLAYTEST-lookandfeel.md` P2, made structural.
/// 3. **EVIDENCE is a tab, not a phase** (§5.6).
/// 4. **The sequence is the Director's, not this view's.** Nothing here holds a
///    timer; the screen asks `director.shows(_:of:)` and draws. A sheet opening over
///    the case cannot interrupt an arrival, and an arrival cannot replay because the
///    view rebuilt.
struct CaseView: View {
  let model: GameModel

  enum Tab: Hashable { case sources, evidence }

  @State private var collapsed = false
  /// §3: which row is showing its question. **One at a time** — peeking is free, and
  /// six open rows would be the wall of text §3 exists to remove.
  @State private var peeked: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// How far the alert header scrolls away before it becomes one sticky line
  /// (§2.6, verbatim: "after 80 px of scroll").
  private static let collapseThreshold: CGFloat = 80

  private var copy: CopyPack { model.content.copy }
  private var session: SessionState { model.session }
  private var socCase: SocCase? { session.currentCase(model.content) }
  private var revealed: [SocEvidence] { session.revealedEvidence(model.content) }
  private var director: Director { model.director }

  /// §2's sequence, addressed by the alert it delivers.
  private var runID: String { Director.arrivalID(case: socCase?.id ?? "") }

  var body: some View {
    VStack(spacing: 0) {
      PlayBar(
        model: model,
        leading: .queuePosition,
        // §5: the ECG and the band word follow `max(engine, time)` — the desk gets
        // louder as the shift burns, with no number of the score moving.
        trace: model.feltStatus,
        // §4: the clock counts the cost up while the log pane streams. `PULL_SOURCE`
        // spends the minutes at once — the session has to be truthful — so the strip
        // draws the session's figure minus what the count-up has not said out loud.
        readout: copy.render(
          copy.chromeText("minutes"),
          [
            "n": String(
              director.clockReading(session.timeSpentOnCurrentCase(model.content)))
          ]))

      Group {
        if let socCase {
          scroller(socCase)
        } else {
          Spacer(minLength: 0)
        }
      }
      // **The scrim dims the read, not the strip** (`FEEL.md` §4). It used to cover
      // the whole screen, SystemBar included — and §4 asks the player to watch the
      // shift clock count the cost out while the log pane streams under it, which a
      // bar at 15 % opacity cannot do. Measured on the simulator: with the full-screen
      // scrim the clock was unreadable in every frame of `docs/screenshots/ios/feel/pull`.
      .overlay { scrim }
    }
    .background(Theme.ground)
    // Applied first → the coach is the INNER inset and lands above the Dock.
    .safeAreaInset(edge: .bottom, spacing: 0) { voice }
    .safeAreaInset(edge: .bottom, spacing: 0) { dock }
    .animation(Motion.gated(Motion.scrim, reduceMotion: reduceMotion), value: session.view)
    .accessibilityIdentifier("screen.case")
  }

  /// §2.5's wireframe: while a sheet is up the case behind it is dimmed behind the
  /// scrim. The scrim's own colour is `Theme.scrim` and is spelled there and nowhere
  /// else (P1-6).
  @ViewBuilder private var scrim: some View {
    if session.view != nil {
      Theme.scrim.opacity(0.85)
        .ignoresSafeArea(edges: [.bottom, .horizontal])
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
          CaseHeader(socCase: socCase, copy: copy, director: director, runID: runID)
            .id(Anchor.top)

          if director.shows(.sources, of: runID) {
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
              selection: Bindable(model.play).caseTab)

            switch model.play.caseTab {
            case .sources: sources(socCase, proxy: proxy)
            case .evidence:
              EvidenceBoard(
                model: model, socCase: socCase,
                onJumpToSource: { sourceID in jump(to: sourceID, proxy: proxy) })
            }
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
        if collapsed, director.shows(.severity, of: runID) {
          CollapsedCaseHeader(socCase: socCase, copy: copy) {
            withAnimation(Motion.gated(Motion.screenPush, reduceMotion: reduceMotion)) {
              proxy.scrollTo(Anchor.top, anchor: .top)
            }
          }
          .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      // **Tap anywhere skips** (§2). It is an overlay rather than a gesture on the
      // scroll view because a `ScrollView` swallows taps, and it is removed the
      // instant the sequence ends so it never eats a tap meant for a source row.
      .overlay {
        if director.isRunning(runID) {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { director.skip() }
            .accessibilityHidden(true)
        }
      }
      // A new alert always opens on SOURCES with the header out.
      //
      // Both hooks are needed: `onAppear` catches the common path, where the phase
      // cycles through the debrief between alerts and this screen is rebuilt — and it
      // is the only one that catches a *new shift*, whose first alert is index 0
      // exactly like the last one's, so `onChange` sees nothing move.
      .onAppear {
        if revealed.isEmpty { model.play.caseTab = .sources }
        collapsed = false
        peeked = nil
        arm()
      }
      .onChange(of: session.shift?.index) { _, _ in
        model.play.caseTab = .sources
        collapsed = false
        peeked = nil
        arm()
      }
      // The board sheet auto-opens once per shift on `BEGIN` (§2.5), so on the first
      // alert of a board the screen underneath is covered at the moment it appears.
      // An alert that arrives behind a sheet is an alert nobody saw: the sequence
      // waits for the desk to be clear.
      .onChange(of: session.view) { _, _ in arm() }
    }
  }

  /// Start §2's arrival, if this is the right moment for it.
  ///
  /// `Director.play(_:id:reduceMotion:)` is idempotent per id within a shift, so this
  /// can be called from all three lifecycle hooks without a flag of its own.
  private func arm() {
    guard session.phase == .investigating, session.view == nil, socCase != nil else {
      return
    }
    director.play(
      Sequences.arrivalSequence(withCoach: model.coachIsActive),
      id: runID, reduceMotion: reduceMotion)
  }

  // MARK: - §3 · sources, collapsed

  private func sources(_ socCase: SocCase, proxy: ScrollViewProxy) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      PlayEyebrow(text: copy.chromeText("caseSourcesEyebrow"))
        .padding(.bottom, 2)

      ForEach(socCase.sources) { source in
        let pulled = session.queried.contains(source.id)
        SourceRow(
          label: source.label,
          question: source.question,
          cost: minutes(source.cost),
          pullTitle: "\(Play.cta(copy.chromeText("sourcePull")))  \(minutes(source.cost))",
          isPulled: pulled,
          pulledLabel: pulled
            ? copy.plural("caseFindingsCount", socCase.findings(from: source.id).count)
            : nil,
          isPeeked: peeked == source.id,
          // §7: a one-shot caption under an unpulled key source, after a decisive or
          // supporting finding landed. The Director decides which rows and for how
          // long; the row only draws it.
          nudge: director.worthALook.contains(source.id)
            ? copy.chromeText(FeelCopyKey.sourceWorthALook) : nil,
          spokenLabel: copy.plural(
            "caseSourceSpoken", source.cost,
            ["label": source.label, "question": source.question]),
          spokenHint: copy.chromeText("caseSourceHint"),
          onTap: { peek(source.id, proxy: proxy) },
          onPull: { model.send(.openView(.source(source.id))) })
        .id(source.id)
      }
    }
  }

  /// One row peeks at a time (§3). Tapping the open one closes it, which is what
  /// makes the peek a *look* rather than a mode.
  ///
  /// The scroll is not a flourish. The coach card and the Dock are two stacked bottom
  /// insets, so a row low in the list opens its `Pull · 10m` button **underneath**
  /// them — measured on the simulator, where the fourth source's button landed at
  /// y 702 under a coach card occupying 689–830 and the tap went to the card. Bringing
  /// the row up is what makes the peek reliably reachable at every position.
  private func peek(_ sourceID: String, proxy: ScrollViewProxy) {
    let opening = peeked != sourceID
    withAnimation(Motion.gated(Motion.peek, reduceMotion: reduceMotion)) {
      peeked = opening ? sourceID : nil
    }
    model.feel(.select)
    // §7's caption is answered by the touch, whichever row it lands on.
    director.clearNudge()
    guard opening else { return }
    Task { @MainActor in
      withAnimation(Motion.gated(Motion.peek, reduceMotion: reduceMotion)) {
        proxy.scrollTo(sourceID, anchor: .center)
      }
    }
  }

  private func minutes(_ cost: Int) -> String {
    copy.render(copy.chromeText("minutes"), ["n": String(cost)])
  }

  // MARK: - The two bottom insets

  /// Whether the shift lead is in the player's ear right now.
  private var coachStep: CopyPack.CoachStep? {
    guard model.coachIsActive, director.shows(.coach, of: runID) else { return nil }
    return session.currentCoachStep(model.content)
  }

  /// **§6 — one voice, one card.**
  ///
  /// An interjection and a coach step are the same person saying one sentence, so
  /// they share a slot rather than stacking: while Vale is interjecting, the coach
  /// step waits. It comes back when she stops, because `coachStep` is derived from
  /// the session and not from a flag this view sets.
  @ViewBuilder private var voice: some View {
    if let line = director.valeLine {
      PlayDock {
        MessageCard(
          sender: copy.chromeText("coachEyebrow"),
          line: line,
          skipTitle: copy.chromeText("close"),
          onSkip: { director.dismissVale() })
        .padding(.bottom, 8)
      }
      .transition(.move(edge: .leading).combined(with: .opacity))
    } else if let step = coachStep {
      PlayDock {
        MessageCard(
          sender: copy.chromeText("coachEyebrow"),
          line: step.body,
          counter: copy.render(
            copy.chromeText("coachStepCount"),
            ["n": String(session.coachStep + 1), "m": String(copy.coachSteps.count)]),
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

  @ViewBuilder private var dock: some View {
    if director.shows(.sources, of: runID) {
      let armed = !revealed.isEmpty
      PlayDock(fade: director.valeLine == nil && coachStep == nil) {
        Dock(
          title: copy.chromeText("makeTheCall"),
          hint: armed
            ? copy.plural(
              "dockArmed", revealed.count,
              ["t": String(session.timeSpentOnCurrentCase(model.content))])
            : copy.chromeText("investigateFirst"),
          isEnabled: armed,
          action: { model.send(.openView(.call)) })
      }
      .transition(.move(edge: .bottom).combined(with: .opacity))
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

  /// §2.8: tapping a `FROM` header jumps back to that row in SOURCES, and opens it —
  /// a jump that lands on a collapsed row would have answered "which one?" and hidden
  /// the answer (§3).
  private func jump(to sourceID: String, proxy: ScrollViewProxy) {
    withAnimation(Motion.gated(Motion.screenPush, reduceMotion: reduceMotion)) {
      model.play.caseTab = .sources
      peeked = sourceID
    }
    Task { @MainActor in
      withAnimation(Motion.gated(Motion.screenPush, reduceMotion: reduceMotion)) {
        proxy.scrollTo(sourceID, anchor: .top)
      }
    }
  }
}

// MARK: - The header, as it arrives

/// The alert assembling itself (§2): the trigger at 260 ms, the title and the asset
/// at 1100, the tool's guess stamped in at 1500.
///
/// Every part is drawn only once its beat has landed, and the parts that have not
/// arrived take no space — the header *grows*, which is what makes the ECG spike at
/// 120 ms read as something happening rather than as a screen loading.
private struct CaseHeader: View {
  let socCase: SocCase
  let copy: CopyPack
  let director: Director
  let runID: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // 260 ms — the log's own voice, typed.
      TypedText(
        text: socCase.trigger,
        isActive: director.shows(.trigger, of: runID),
        duration: Double(Sequences.arrivalTriggerTypeMs) / 1000.0,
        font: Typography.meta,
        color: Theme.textSecondary,
        lineSpacing: 3)

      // 1100 ms — what it is called, and what it happened to.
      if director.shows(.title, of: runID) {
        VStack(alignment: .leading, spacing: 8) {
          Text(socCase.alertTitle)
            .font(Typography.screenTitle)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(copy.chromeText("caseAsset")).trackedLabel(Theme.textDisabled)
            // §5.4: `soc-phish-harvest`'s sender is a 33-character unbreakable token,
            // so the asset line is never line-limited and is allowed to tighten.
            Text(socCase.asset)
              .font(Typography.meta)
              .foregroundStyle(Theme.textTertiary)
              .lineLimit(nil)
              .allowsTightening(true)
              .minimumScaleFactor(0.75)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .transition(.opacity)
      }

      // 1500 ms — and only now, the guess.
      if director.shows(.severity, of: runID) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            let severity = copy.severity(socCase.toolSeverity)
            Chip(
              text: copy.render(
                copy.chromeText("caseSeverityChip"), ["severity": severity.label]),
              tone: Theme.tone(severity.tone),
              style: .outline)
              .stamped()

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
        }
        .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }
}

/// The severity chip's 1.3 → 1 stamp (§2, row 5).
///
/// A `ViewModifier` rather than a copy of `StampView`: the analyst's stamp is 1.4 and
/// rotated, and the tool's is neither — a claim, not a verdict. The scale runs once,
/// on appear, and Reduce Motion draws the settled chip.
private struct StampedIn: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var landed = false

  func body(content: Content) -> some View {
    content
      .scaleEffect(landed ? 1 : Motion.severityStampScaleFrom)
      .opacity(landed ? 1 : 0)
      .onAppear {
        withAnimation(Motion.gated(Motion.severityStamp, reduceMotion: reduceMotion)) {
          landed = true
        }
      }
  }
}

extension View {
  fileprivate func stamped() -> some View { modifier(StampedIn()) }
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
