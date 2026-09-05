import SentryCore
import SwiftUI

/// **The kit** — `SPEC.md` §10 C7 #7.
///
/// Every primitive in the deck on one scrolling page: the `SystemBar` in all four
/// pressure bands, a sheet, the Dock, every tone the content authors, the meters and
/// the ladder. It is the screen a reviewer opens to see whether the design *system*
/// holds together, rather than whether one screen does — and it is the fastest way to
/// catch a Dynamic Type or Reduce Motion regression across seventeen components at
/// once, because everything is on the same glass at the same setting.
///
/// **It is a view, not a screen.** `MetaScreenFactory` and `ViewID.kit` belong to C9
/// and `QAJump` to C5, so C7 cannot mount itself; what it can do is ship the whole
/// harness inside its own directory so mounting it is one line:
/// `case .kit: AnyView(ComponentKitView(content: model.content))`.
///
/// **Every string on this page comes from the bundle** — `copy.chrome`, the exported
/// cases, ranks and coach steps — or from a type's own name. There is no authored
/// copy here (S1): the kit shows the components as the game will actually fill them,
/// which is also the only way it can catch a real string overflowing a real row.
struct ComponentKitView: View {
  let content: ContentPack
  /// The dismiss, when the kit is pushed rather than launched into. `nil` renders no
  /// control — a QA jump has nowhere to go back to.
  var onClose: (() -> Void)?
  /// `false` renders the catalogue in one column with no scroll region — the form
  /// `ImageRenderer` can actually rasterise. The screen always wants `true`.
  var scrolls: Bool = true
  /// Which blocks to draw. The screen draws them all; the snapshot suite renders
  /// them in two passes, because the whole catalogue is ~4800 pt tall and one
  /// surface that size is past what the PNG encoder will take.
  var blocks: [Block] = Block.allCases

  @State private var tab = 0

  /// The catalogue, in the order the deck reads: the chrome you are always under,
  /// then what you press, then what you are told, then what you file.
  enum Block: String, CaseIterable, Identifiable {
    case chrome
    case controls
    case sheet
    case pressure
    case tones
    case rows
    case ceremony
    case ladder
    case prose

    var id: String { rawValue }
  }

  init(
    content: ContentPack = .bundled, onClose: (() -> Void)? = nil, scrolls: Bool = true,
    blocks: [Block] = Block.allCases
  ) {
    self.content = content
    self.onClose = onClose
    self.scrolls = scrolls
    self.blocks = blocks
  }

  private var copy: CopyPack { content.copy }

  var body: some View {
    VStack(spacing: 0) {
      if blocks.contains(.chrome) { chromeBand }

      if scrolls {
        ScrollView { page }
      } else {
        page
      }
    }
    .background(Theme.ground)
    .accessibilityIdentifier("kit.root")
  }

  /// Split from `body` so the same catalogue can be rendered *without* a
  /// `ScrollView` — `ImageRenderer` does not rasterise a scroll region's content, so
  /// the snapshot suite would otherwise capture an empty page. Same rule, and the
  /// same reason, as `SheetChrome.scrolls`.
  private var page: some View {
    VStack(alignment: .leading, spacing: 26) {
      ForEach(blocks) { block in view(for: block) }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 22)
  }

  @ViewBuilder private func view(for block: Block) -> some View {
    switch block {
    // Drawn above the scroll region, pinned like the real strip.
    case .chrome: EmptyView()
    case .controls: tabsAndDock
    case .sheet: sheetBlock
    case .pressure: metersBlock
    case .tones: tonesBlock
    case .rows: rowsBlock
    case .ceremony: ceremonyBlock
    case .ladder: ladderBlock
    case .prose: proseBlock
    }
  }

  // MARK: - Chrome (#7: the SystemBar in all four statuses)

  private var chromeBand: some View {
    VStack(spacing: 0) {
      SystemBar(
        leading: copy.chromeText("wordmark"),
        wallet: [
          "\(Glyph.standingFilled) 80", "\(Glyph.cash) 650",
        ],
        settingsLabel: copy.chromeText("settingsTitle"),
        settingsAction: {})

      ForEach(TraceStatus.allCases, id: \.self) { status in
        SystemBar(
          leading: "\(Glyph.back) \(queueCount)",
          leadingAction: onClose ?? {},
          trace: .init(status: status, label: bandLabel(status), bpm: content.tuning.bpm[status]),
          pill: .init(text: pillText, action: {}),
          settingsLabel: copy.chromeText("settingsTitle"),
          settingsAction: {})
      }
    }
  }

  /// `QUEUE 3/7` — the label and the count are two separate chrome keys, joined the
  /// way §2.5 draws them.
  private var pillText: String {
    "\(copy.chromeText("queueLabel")) \(queueCount)"
  }

  private var queueCount: String {
    copy.render(copy.chromeText("queueCount"), ["n": "3", "m": "7"])
  }

  /// CALM alone is re-voiced (the band word a player sees at CALM is the exported
  /// `statusCalm`); the other three are the band itself.
  private func bandLabel(_ status: TraceStatus) -> String {
    status == .calm ? copy.chromeText("statusCalm") : status.rawValue
  }

  // MARK: - Tabs and the Dock

  private var tabsAndDock: some View {
    section(SegmentedTabs<Int>.self, Dock.self) {
      SegmentedTabs(
        items: [
          .init(id: 0, title: copy.chromeText("caseSourcesTab"), badge: "3/6"),
          .init(id: 1, title: copy.chromeText("caseEvidenceTab"), badge: "3"),
        ],
        selection: $tab)

      Dock(title: copy.chromeText("makeTheCall"), hint: dockHint, action: {})
      Dock(
        title: copy.chromeText("makeTheCall"), hint: copy.chromeText("investigateFirst"),
        isEnabled: false, action: {})
      Dock(
        title: copy.render(
          copy.chromeText("dockClockIn"),
          ["shift": content.shifts.first?.label ?? ""]),
        tone: Theme.falsePositive, disclaimer: copy.intro.disclaimer, action: {})
    }
  }

  private var dockHint: String {
    let findings = copy.render(copy.chromeText("caseFindingsCount"), ["n": "3"])
    return "\(findings) · \(copy.render(copy.chromeText("minutes"), ["n": "26"]))"
  }

  // MARK: - A sheet

  private var sheetBlock: some View {
    section(SheetChrome<AnyView, AnyView>.self) {
      SheetChrome(
        eyebrow: copy.chromeText("boardEyebrow"),
        trailing: copy.render(copy.chromeText("boardClock"), ["n": "22"]),
        scrolls: false
      ) {
        VStack(alignment: .leading, spacing: 14) {
          Text(copy.chromeText("boardPressureEyebrow")).trackedLabel()
          meter(copy.intro.meters.first, value: "30", fraction: 0.30, status: .alert)
        }
      } footer: {
        // `boardOpenAlert` carries its own `▸`, and so does `Dock` — the caret-free
        // keys are the ones a Dock takes.
        Dock(title: copy.chromeText("close"), tone: Theme.falsePositive, action: {})
      }
      .frame(height: 300)
    }
  }

  // MARK: - The meters

  private var metersBlock: some View {
    section(MeterView.self, ECGCanvas.self, StatTile.self) {
      ForEach(Array(copy.intro.meters.enumerated()), id: \.element.key) { index, intro in
        meter(
          intro, value: meterValues[index].0, fraction: meterValues[index].1,
          status: meterValues[index].2)
      }

      StatTileGrid(items: [
        .init(
          id: CopyPack.MeterKey.breach.rawValue, value: "86%",
          label: copy.chromeText("statAccuracy"), tone: Theme.pressure, numericKey: 0.86),
        .init(id: SocVerdict.truePositive.rawValue, value: "7/7", label: copy.chromeText("statCalls")),
        .init(
          id: SocVerdict.falsePositive.rawValue, value: "1", label: copy.chromeText("statMissed"),
          tone: Theme.truePositive, numericKey: 1),
        .init(
          id: SocVerdict.benignTruePositive.rawValue, value: "0",
          label: copy.chromeText("statFalseEscalations"), tone: Theme.benign),
      ])

      ForEach(TraceStatus.allCases, id: \.self) { status in
        HStack(spacing: 12) {
          Text(bandLabel(status))
            .trackedLabel(Theme.status(status).text)
            .frame(width: 88, alignment: .leading)
          ECGCanvas(status: status, bpm: content.tuning.bpm[status]).frame(height: 24)
        }
      }
    }
  }

  /// One value per exported meter, in the order the briefing introduces them —
  /// deliberately three different bands, so the ramp is on screen in one glance.
  private let meterValues: [(String, Double, TraceStatus)] = [
    ("30", 0.30, .alert), ("56", 0.56, .hunt), ("22", 22.0 / 90.0, .calm),
  ]

  @ViewBuilder private func meter(
    _ intro: CopyPack.IntroMeter?, value: String, fraction: Double, status: TraceStatus
  ) -> some View {
    if let intro {
      let rendered = copy.render(copy.chromeText("boardMeterValue"), ["n": value])
      MeterView(
        label: intro.label, valueText: rendered, fraction: fraction, status: status,
        fear: intro.fear, spokenValue: "\(rendered), \(bandLabel(status))")
    }
  }

  // MARK: - Every tone (#7)

  private var tonesBlock: some View {
    section(Chip.self) {
      chipRow(ToolSeverity.known.map {
        let meta = copy.severity($0)
        return (meta.label, Theme.tone(meta.tone))
      })
      chipRow(SocVerdict.allCases.map {
        (copy.verdictLabels[$0] ?? $0.rawValue, Theme.verdict($0))
      })
      chipRow(ShiftGrade.allCases.map {
        let meta = copy.gradeMeta[$0]
        return (meta?.label ?? $0.rawValue, Theme.tone(meta?.tone ?? Tone(rawValue: $0.rawValue)))
      })
      chipRow(Disposition.allCases.map {
        let meta = copy.dispositionMeta[$0]
        return (meta?.label ?? $0.rawValue, Theme.disposition($0))
      })
    }
  }

  private func chipRow(_ entries: [(String, Color)]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
        Chip(text: entry.0, tone: entry.1, style: .filled, tracked: false)
      }
    }
  }

  // MARK: - Rows and cards

  private var rowsBlock: some View {
    section(QueueRow.self, SourceRow.self, EvidenceCard.self, InboxCard.self, CoachBubble.self) {
      ForEach(Array(content.shifts.prefix(3).enumerated()), id: \.element.id) { index, shift in
        QueueRow(
          title: shift.label,
          count: copy.render(
            copy.chromeText("hubAlertCount"), ["n": "\(shift.caseIds.count)"]),
          statusLine: queueStatus(index: index, shift: shift),
          cta: index == 2 ? nil : copy.chromeText("hubStart"),
          state: index == 0 ? .cleared : (index == 1 ? .open : .locked),
          spokenHint: index == 2
            ? copy.render(copy.chromeText("hubLockedSpoken"), ["n": "\(shift.unlockStanding)"])
            : nil,
          action: {})
      }

      if let sample = content.cases.first {
        ForEach(Array(sample.sources.prefix(2).enumerated()), id: \.element.id) { index, source in
          SourceRow(
            label: source.label, question: source.question,
            cost: copy.render(copy.chromeText("minutes"), ["n": "\(source.cost)"]),
            isPulled: index == 1, pulledLabel: copy.chromeText("caseSourcePulled"),
            spokenLabel: "\(source.label). \(source.question)",
            spokenHint: copy.chromeText("caseSourceHint"), action: {})
        }

        ForEach(Array(sample.evidence.prefix(2)), id: \.id) { finding in
          EvidenceCard(label: finding.label, detail: finding.detail)
        }

        EvidenceEmptyState(
          title: copy.chromeText("caseEmptyBoard"),
          line: copy.chromeText("caseEmptyBoardBlind"))
      }

      ForEach(Array(inboxSample.prefix(2).enumerated()), id: \.element.id) { index, message in
        InboxCard(
          eyebrow: "\(message.from.uppercased()) · \(message.role.uppercased())",
          subject: message.subject, body_: message.body,
          tone: Theme.tone(copy.handlerTone(message.tone).tone),
          counter: copy.render(
            copy.chromeText("coachStepCount"),
            ["n": "\(index + 1)", "m": "\(min(inboxSample.count, 2))"]),
          spokenLabel: "\(message.from). \(message.subject).")
      }

      if let step = copy.coachSteps.first {
        CoachBubble(
          eyebrow: copy.chromeText("coachEyebrow"),
          counter: copy.render(
            copy.chromeText("coachStepCount"), ["n": "1", "m": "\(copy.coachSteps.count)"]),
          title: step.title, body_: step.body, buttonTitle: step.button,
          skipTitle: copy.chromeText("coachSkip"),
          onButton: step.button == nil ? nil : {}, onSkip: {})
      }
    }
  }

  private func queueStatus(index: Int, shift: ShiftDef) -> String {
    switch index {
    case 0: copy.chromeText("hubCleared")
    case 1: copy.chromeText("hubOpen")
    default:
      copy.render(copy.chromeText("hubLocked"), ["n": "\(max(shift.unlockStanding, 80))"])
    }
  }

  private var inboxSample: [HandlerMessage] {
    HandlerVoice(content: content).inboxFor(
      CareerState(cash: 650, standing: 80, shiftsCleaned: 2),
      HandlerEvent(type: .shiftClean))
  }

  // MARK: - The call

  private var ceremonyBlock: some View {
    section(StampView.self, HoldToFileButton.self) {
      ForEach(Disposition.allCases, id: \.self) { disposition in
        let meta = copy.dispositionMeta[disposition]
        StampView(
          text: meta?.label ?? disposition.rawValue,
          tone: Theme.disposition(disposition),
          spokenLabel: meta?.label ?? disposition.rawValue,
          animates: false)
      }

      HoldToFileButton(
        title: holdTitle, actionLabel: copy.chromeText("callFileAction"), onFile: {})
      // The mid-flight frame, so the ring's fill is on the page without a finger.
      HoldFace(title: holdTitle, progress: 0.42)
      HoldToFileButton(
        title: copy.chromeText("callFile"), confirmTitle: copy.chromeText("callConfirm"),
        actionLabel: copy.chromeText("callFileAction"), tone: Theme.falsePositive,
        holdEnabled: false, onFile: {})
    }
  }

  private var holdTitle: String {
    let disposition = copy.dispositionMeta[.escalateIRIsolate]?.label ?? Disposition.escalateIRIsolate.rawValue
    return copy.render(copy.chromeText("callHoldToFile"), ["disposition": disposition])
  }

  // MARK: - The ladder (#7)

  private var ladderBlock: some View {
    section(RankBadge.self, LadderTrack.self) {
      HStack(spacing: 18) {
        RankBadge(
          label: content.ranks.dropFirst().first?.label ?? "", size: 110, animates: false)
        Spacer(minLength: 0)
      }
      LadderTrack(
        rungs: content.ranks.map {
          .init(id: $0.id, label: $0.label, threshold: "\($0.min)", held: $0.min <= 40)
        })
    }
  }

  // MARK: - Prose

  private var proseBlock: some View {
    section(RichTextView.self, TaxonomyRow.self) {
      RichTextView(segments: copy.intro.taxonomy)
      ForEach(SocVerdict.allCases, id: \.self) { verdict in
        TaxonomyRow(
          verdict: copy.verdictLabels[verdict] ?? verdict.rawValue,
          meaning: verdict.rawValue, tone: Theme.verdict(verdict))
      }
      RichTextView(segments: copy.intro.severity)
      Text(copy.ladder.note).quietLog()
    }
  }

  // MARK: - Section chrome

  /// A block, labelled with the **type names** it contains.
  ///
  /// `String(describing:)` rather than an authored heading: this page is a catalogue
  /// of types, the type's own name is the most accurate label it can carry, and it
  /// keeps the kit free of the player-facing literals S1 forbids in `Components/`.
  private func section(
    _ types: Any.Type..., @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      // Not `trackedLabel()`: it clamps to one line, and a block that lists five
      // type names does not fit one — same reason `RankBadge` spells the step out.
      Text(types.map { String(describing: $0) }.joined(separator: " · "))
        .font(Typography.label)
        .tracking(Typography.labelTracking)
        .textCase(.uppercase)
        .foregroundStyle(Theme.textQuiet)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#Preview("Component kit · the whole deck on one page") {
  ComponentKitView()
}
