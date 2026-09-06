import SentryCore
import SwiftUI
import Testing
import UIKit

@testable import SentrySOC

/// **Visual evidence for C7.** Renders every primitive in its key states with
/// `ImageRenderer` and writes the PNGs under `docs/screenshots/ios/components/`, so
/// the look of the component layer can be *reviewed* rather than assumed.
///
/// This stands in for C7 acceptance #7's `-SentryQAScreen kit` harness, which needs
/// C5's `QAJump` and therefore cannot exist while C5 and C7 run in the same stage.
/// The coverage is the same ground #7 asks for — the SystemBar in all four statuses,
/// a sheet, the Dock, every tone, the meters and the ladder — and it runs without a
/// simulator install, a launch argument or a screen registry.
///
/// Deliberately **not** an assertion suite: nothing here compares against a golden
/// image. A byte-comparison snapshot test on a 17-primitive design layer fails on
/// every font-rendering change in every OS update and teaches a reviewer to delete
/// the baseline, which is worse than no test. The output is an artefact for a human
/// (and for `docs/screenshots/ios/`); the *behavioural* invariants that can be
/// asserted are asserted in `ComponentBehaviourTests`.
@MainActor
@Suite("Component snapshots")
struct ComponentSnapshotTests {

  // MARK: - Chrome

  @Test("SystemBar · hub and the four pressure bands")
  func systemBar() throws {
    try shot("SystemBar", "hub") {
      SystemBar(
        leading: "SENTRY · SOC", wallet: ["⬢ 80", "¢ 650"],
        settingsLabel: "Settings", settingsAction: {})
    }

    for (status, label, bpm) in Self.bands {
      try shot("SystemBar", status.rawValue.lowercased()) {
        SystemBar(
          leading: "‹ 3/7", leadingAction: {},
          trace: .init(status: status, label: label, bpm: bpm, now: Self.clock),
          pill: .init(text: "QUEUE 3/7", action: {}),
          settingsLabel: "Settings", settingsAction: {})
      }
    }
  }

  @Test("ECGCanvas · the ramp, and the Reduce Motion degrade")
  func ecg() throws {
    for (status, label, bpm) in Self.bands {
      try shot("ECGCanvas", status.rawValue.lowercased()) {
        HStack(spacing: 14) {
          Text(label).trackedLabel(Theme.status(status).text).frame(width: 92, alignment: .leading)
          ECGCanvas(status: status, bpm: bpm, now: Self.clock).frame(height: 30)
        }
        .padding(20)
      }
    }

    // The Reduce Motion degrade, rendered as the view the environment branch picks
    // — a still frame of the same path, caught mid-beat.
    try shot("ECGCanvas", "reduced-motion") {
      VStack(alignment: .leading, spacing: 18) {
        ForEach(Self.bands, id: \.0) { status, label, _ in
          HStack(spacing: 14) {
            Text(label).trackedLabel(Theme.status(status).text).frame(width: 92, alignment: .leading)
            ECGTrace(status: status, phase: ECGTrace.restingPhase, showsHead: false)
              .frame(height: 30)
          }
        }
      }
      .padding(20)
    }
  }

  @Test("Dock · armed, blocked, secondary, briefing")
  func dock() throws {
    try shot("Dock", "armed") {
      Dock(title: "Make the call", hint: "3 findings · 26m", action: {}).padding(.vertical, 10)
    }
    try shot("Dock", "blocked") {
      Dock(title: "Make the call", hint: "investigate first", isEnabled: false, action: {})
        .padding(.vertical, 10)
    }
    try shot("Dock", "secondary") {
      Dock(title: "Open alert 3", tone: Theme.falsePositive, action: {}).padding(.vertical, 10)
    }
    try shot("Dock", "briefing") {
      Dock(
        title: "Start the shift",
        disclaimer:
          "Fiction simulator — every log line is fabricated; it teaches the analyst's read, never a working technique.",
        action: {}
      ).padding(.vertical, 10)
    }
  }

  @Test("SheetChrome · the board sheet")
  func sheetChrome() throws {
    // `scrolls: false`: `ImageRenderer` does not rasterise a `ScrollView`'s content
    // (the header and the footer land, the scroll region comes out empty), so the
    // sheet is captured in its non-scrolling form. The chrome — panel, radius,
    // scrim, eyebrow row, pinned footer — is identical either way.
    try shot("SheetChrome", "board", height: 420) {
      SheetChrome(eyebrow: "Alert queue · Shift 1", trailing: "22m", scrolls: false) {
        VStack(alignment: .leading, spacing: 16) {
          Text("SHIFT PRESSURE").trackedLabel()
          MeterView(
            label: "BREACH RISK", valueText: "30", fraction: 0.30, status: .alert,
            fear: "a real threat you closed is dwelling undetected",
            spokenValue: "30 percent, ALERT")
          MeterView(
            label: "NOISE / FATIGUE", valueText: "0", fraction: 0, status: .calm,
            fear: "crying wolf — Tier-2 stops trusting your tickets",
            spokenValue: "0 percent, CALM")
        }
      } footer: {
        Dock(title: "Open alert 3", tone: Theme.falsePositive, action: {})
      }
      .frame(height: 420)
    }
  }

  @Test("SegmentedTabs · empty board and a live one")
  func segmentedTabs() throws {
    try shot("SegmentedTabs", "empty") {
      SegmentedTabs(
        items: [.init(id: 0, title: "SOURCES", badge: "0/6"), .init(id: 1, title: "EVIDENCE", badge: "0")],
        selection: .constant(0)
      ).padding(20)
    }
    try shot("SegmentedTabs", "evidence") {
      SegmentedTabs(
        items: [.init(id: 0, title: "SOURCES", badge: "3/6"), .init(id: 1, title: "EVIDENCE", badge: "3")],
        selection: .constant(1)
      ).padding(20)
    }
  }

  // MARK: - Numbers

  @Test("MeterView · the three meters across the ramp")
  func meters() throws {
    try shot("MeterView", "calm") {
      MeterView(
        label: "BREACH RISK", valueText: "0", fraction: 0, status: .calm,
        fear: "a real threat you closed is dwelling undetected",
        spokenValue: "0 percent, CALM"
      ).padding(20)
    }
    try shot("MeterView", "alert") {
      MeterView(
        label: "BREACH RISK", valueText: "30", fraction: 0.30, status: .alert,
        fear: "a real threat you closed is dwelling undetected",
        spokenValue: "30 percent, ALERT"
      ).padding(20)
    }
    try shot("MeterView", "hunt") {
      MeterView(
        label: "NOISE / FATIGUE", valueText: "56", fraction: 0.56, status: .hunt,
        fear: "crying wolf — Tier-2 stops trusting your tickets",
        spokenValue: "56 percent, HUNT"
      ).padding(20)
    }
    try shot("MeterView", "lockdown") {
      MeterView(
        label: "BREACH RISK", valueText: "90", fraction: 0.90, status: .lockdown,
        fear: "a real threat you closed is dwelling undetected",
        spokenValue: "90 percent, LOCKDOWN"
      ).padding(20)
    }
    try shot("MeterView", "time") {
      MeterView(
        label: "TIME", valueText: "22 / 90 shift-min", fraction: 22.0 / 90.0, status: .calm,
        fear: "a soft budget — surfaced, never scored",
        spokenValue: "22 of 90 shift-minutes"
      ).padding(20)
    }
  }

  @Test("StatTile · a clean shift and a rough one")
  func statTiles() throws {
    try shot("StatTile", "clean") {
      StatTileGrid(items: [
        .init(id: "acc", value: "100%", label: "Accuracy", tone: Theme.benign, numericKey: 1),
        .init(id: "calls", value: "7/7", label: "Calls", numericKey: 7),
        .init(id: "missed", value: "0", label: "Missed threats", tone: Theme.benign),
        .init(id: "false", value: "0", label: "False escalations", tone: Theme.benign),
      ]).padding(20)
    }
    try shot("StatTile", "rough") {
      StatTileGrid(items: [
        .init(id: "acc", value: "86%", label: "Accuracy", tone: Theme.pressure, numericKey: 0.86),
        .init(id: "calls", value: "7/7", label: "Calls", numericKey: 7),
        .init(id: "missed", value: "1", label: "Missed threats", tone: Theme.truePositive, numericKey: 1),
        .init(id: "false", value: "1", label: "False escalations", tone: Theme.truePositive, numericKey: 1),
      ]).padding(20)
    }
  }

  @Test("Chip · every tone the content authors")
  func chips() throws {
    let copy = ContentPack.bundled.copy
    try shot("Chip", "tones") {
      VStack(alignment: .leading, spacing: 12) {
        Text("SEVERITY · severityMeta").trackedLabel()
        HStack(spacing: 8) {
          ForEach(["Critical", "High", "Medium", "Low"], id: \.self) { key in
            let meta = copy.severityMeta.meta(for: key)
            Chip(text: meta.label, tone: Theme.tone(meta.tone))
          }
          Spacer(minLength: 0)
        }

        Text("TRUTH · verdictLabels").trackedLabel()
        VStack(alignment: .leading, spacing: 8) {
          ForEach(SocVerdict.allCases, id: \.self) { verdict in
            Chip(
              text: copy.verdictLabels[verdict] ?? verdict.rawValue,
              tone: Theme.verdict(verdict), style: .filled, tracked: false)
          }
        }

        Text("CROSSOVER · MITRE").trackedLabel()
        HStack(spacing: 8) {
          Chip(text: "↔ red-team run", tone: Theme.crossover, style: .filled)
          Chip(text: "T1059.001 · PowerShell", tone: Theme.textTertiary, style: .filled, tracked: false)
          Spacer(minLength: 0)
        }
      }
      .padding(20)
    }
  }

  // MARK: - The call

  @Test("StampView · all four dispositions")
  func stamp() throws {
    let copy = ContentPack.bundled.copy
    for disposition in Disposition.allCases {
      let meta = copy.dispositionMeta[disposition]
      try shot("StampView", disposition.rawValue) {
        StampView(
          text: meta?.label ?? disposition.rawValue,
          tone: Theme.disposition(disposition),
          spokenLabel: "Filed: \(meta?.label ?? disposition.rawValue)",
          animates: false
        )
        .padding(28)
      }
    }
  }

  @Test("HoldToFileButton · rest, mid-hold, complete, two-tap, reduced")
  func holdToFile() throws {
    try shot("HoldToFileButton", "rest") {
      HoldToFileButton(
        title: "Hold to file · Escalate → IR + isolate host", actionLabel: "File this call",
        onFile: {}
      ).padding(20)
    }
    // Mid-flight and complete are frames of a gesture: `HoldFace` is the frame, and
    // it is the same view the live button draws — there is no test-only parameter on
    // `HoldToFileButton` for a screen to reach for.
    try shot("HoldToFileButton", "holding") {
      HoldFace(title: "Hold to file · Escalate → IR + isolate host", progress: 0.42)
        .padding(20)
    }
    try shot("HoldToFileButton", "complete") {
      HoldFace(
        title: "Hold to file · Close · Benign (authorized)", tone: Theme.benign, progress: 1
      ).padding(20)
    }
    try shot("HoldToFileButton", "two-tap") {
      HoldToFileButton(
        title: "File ▸", confirmTitle: "Confirm", actionLabel: "File this call",
        tone: Theme.falsePositive, holdEnabled: false, onFile: {}
      ).padding(20)
    }
    // Reduce Motion: the ring steps once per tick instead of sweeping, so the two
    // frames a held button can show are 1/3 and 2/3 — asserted in
    // `ComponentBehaviourTests.holdReducedMotionSteps`, drawn here.
    try shot("HoldToFileButton", "reduced-motion") {
      VStack(spacing: 14) {
        HoldFace(
          title: "Hold to file · Escalate → Tier 2", tone: Theme.pressure,
          progress: 1.0 / 3.0)
        HoldFace(
          title: "Hold to file · Escalate → Tier 2", tone: Theme.pressure,
          progress: 2.0 / 3.0)
      }
      .padding(20)
    }
  }

  // MARK: - Rows and cards

  @Test("SourceRow · real sources from the bundle, fresh and spent")
  func sourceRows() throws {
    let pack = ContentPack.bundled
    let sources = Array(pack.cases.first?.sources.prefix(3) ?? [])
    try shot("SourceRow", "list") {
      VStack(spacing: 8) {
        ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
          // FEEL.md §3's three states in one strip: at rest (name + cost only), spent
          // (a tick and what it surfaced), and peeked (the question and the commit).
          SourceRow(
            label: source.label, question: source.question, cost: "\(source.cost)m",
            pullTitle: "Pull the log  \(source.cost)m",
            isPulled: index == 1, pulledLabel: "2 findings",
            isPeeked: index == 2,
            spokenLabel:
              "\(source.label). Answers: \(source.question). Costs \(source.cost) shift-minutes.",
            spokenHint: "Pulls this log", onTap: {}, onPull: {})
        }
      }
      .padding(20)
    }
  }

  @Test("EvidenceCard · real findings, the debrief markers, the empty board")
  func evidence() throws {
    let pack = ContentPack.bundled
    let findings = Array(pack.cases.first?.evidence.prefix(2) ?? [])
    try shot("EvidenceCard", "board") {
      VStack(spacing: 10) {
        ForEach(findings, id: \.id) { finding in
          EvidenceCard(label: finding.label, detail: finding.detail)
        }
      }
      .padding(20)
    }
    try shot("EvidenceCard", "decisive") {
      VStack(spacing: 10) {
        ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
          EvidenceCard(
            label: finding.label, detail: finding.detail,
            marker: index == 0
              ? (Glyph.correct, Theme.benign) : (Glyph.missed, Theme.textDisabled))
        }
      }
      .padding(20)
    }
    try shot("EvidenceCard", "empty") {
      EvidenceEmptyState(
        title: "Pull a source to surface findings.", line: "You can't make the call blind."
      ).padding(20)
    }
  }

  @Test("QueueRow · the whole ladder, including the locked reasons")
  func queueRows() throws {
    try shot("QueueRow", "ladder") {
      VStack(spacing: 8) {
        QueueRow(
          title: "Shift 1 · fundamentals", count: "7 alerts", statusLine: "cleared · replay",
          cta: "Start ▸", state: .cleared, action: {})
        QueueRow(
          title: "Shift 2 · phishing · identity", count: "8 alerts", statusLine: "open",
          cta: "Start ▸", state: .open, action: {})
        QueueRow(
          title: "Shift 3 · the lockout queue", count: "3 alerts",
          statusLine: "⬡ LOCKED · opens at ⬢ 80", state: .locked,
          spokenHint: "Locked. Opens at 80 standing.", action: {})
        QueueRow(
          title: "Daily shift · Fri 05 Sep", count: "5 alerts",
          statusLine: "a fresh board every day", cta: "Start ▸", state: .daily, action: {})
        QueueRow(
          title: "Daily shift · Fri 05 Sep", count: "5 alerts", statusLine: "done today ✓",
          state: .dailyDone, action: {})
      }
      .padding(20)
    }
  }

  @Test("InboxCard · the real handler voice from the bundle")
  func inbox() throws {
    let pack = ContentPack.bundled
    let voice = HandlerVoice(content: pack)
    let messages = voice.inboxFor(
      CareerState(cash: 650, standing: 80, shiftsCleaned: 2),
      HandlerEvent(type: .shiftClean))

    try shot("InboxCard", "handler") {
      VStack(spacing: 10) {
        ForEach(Array(messages.prefix(3).enumerated()), id: \.element.id) { index, message in
          InboxCard(
            eyebrow: "\(message.from.uppercased()) · \(message.role.uppercased())",
            subject: message.subject, body_: message.body,
            tone: Theme.tone(pack.copy.handlerTone(message.tone).tone),
            counter: "\(index + 1)/\(min(messages.count, 3))",
            spokenLabel: "\(message.from). \(message.subject). \(message.body)")
        }
      }
      .padding(20)
    }
  }

  @Test("CoachBubble · a stepped hint and a terminal one")
  func coach() throws {
    let steps = ContentPack.bundled.copy.coachSteps
    try shot("CoachBubble", "steps") {
      VStack(spacing: 16) {
        ForEach(Array(steps.prefix(2).enumerated()), id: \.offset) { index, step in
          CoachBubble(
            eyebrow: "Shift lead · in your ear", counter: "\(index + 1)/\(steps.count)",
            title: step.title, body_: step.body, buttonTitle: step.button,
            skipTitle: "skip coaching",
            onButton: step.button == nil ? nil : {}, onSkip: {})
        }
      }
      .padding(.vertical, 20)
    }
  }

  // MARK: - Ceremony and prose

  @Test("RankBadge · the promotion and the finale, plus the ladder track")
  func rankBadge() throws {
    let ranks = ContentPack.bundled.ranks
    try shot("RankBadge", "promotion") {
      RankBadge(label: "TIER-1 ANALYST", animates: false).padding(24)
    }
    try shot("RankBadge", "finale") {
      RankBadge(label: "TIER-2 LEAD", tone: Theme.crossover, size: 110, animates: false)
        .padding(24)
    }
    try shot("RankBadge", "ladder") {
      LadderTrack(
        rungs: ranks.map {
          .init(id: $0.id, label: $0.label, threshold: "\($0.min)", held: $0.min <= 40)
        }
      ).padding(24)
    }
  }

  @Test("RichTextView · the exported taxonomy, severity and ladder paragraphs")
  func richText() throws {
    let copy = ContentPack.bundled.copy
    try shot("RichTextView", "taxonomy") {
      VStack(alignment: .leading, spacing: 14) {
        Text("THE THREE VERDICTS").trackedLabel(Theme.benign)
        RichTextView(segments: copy.intro.taxonomy)
        VStack(alignment: .leading, spacing: 12) {
          TaxonomyRow(verdict: "True Positive", meaning: "a real threat", tone: Theme.truePositive)
          TaxonomyRow(
            verdict: "False Positive", meaning: "the detection misfired",
            tone: Theme.falsePositive)
          TaxonomyRow(
            verdict: "Benign True Positive",
            meaning: "the detection was right — the activity was authorized",
            tone: Theme.benign)
        }
      }
      .padding(20)
    }
    try shot("RichTextView", "severity") {
      VStack(alignment: .leading, spacing: 12) {
        Text("THE TOOL'S GUESS").trackedLabel(Theme.Orange.c300)
        RichTextView(segments: copy.intro.severity)
      }
      .padding(20)
    }
    try shot("RichTextView", "ladder") {
      VStack(alignment: .leading, spacing: 12) {
        Text(copy.ladder.eyebrow).trackedLabel(Theme.crossover)
        RichTextView(segments: copy.ladder.body)
        Text(copy.ladder.note).quietLog()
      }
      .padding(20)
    }
  }

  // MARK: - Galleries

  @Test("Gallery · the whole component layer, for review at a glance")
  func galleries() throws {
    try shot("Gallery", "chrome", height: nil) {
      VStack(spacing: 0) {
        SystemBar(
          leading: "SENTRY · SOC", wallet: ["⬢ 80", "¢ 650"], settingsLabel: "Settings",
          settingsAction: {})
        ForEach(Self.bands, id: \.0) { status, label, bpm in
          SystemBar(
            leading: "‹ 3/7", leadingAction: {},
            trace: .init(status: status, label: label, bpm: bpm),
            pill: .init(text: "QUEUE 3/7", action: {}),
            settingsLabel: "Settings", settingsAction: {})
        }
        VStack(spacing: 14) {
          SegmentedTabs(
            items: [
              .init(id: 0, title: "SOURCES", badge: "3/6"),
              .init(id: 1, title: "EVIDENCE", badge: "3"),
            ], selection: .constant(1))
          Dock(title: "Make the call", hint: "3 findings · 26m", action: {})
          Dock(title: "Make the call", hint: "investigate first", isEnabled: false, action: {})
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
      }
    }

    try shot("Gallery", "pressure") {
      VStack(alignment: .leading, spacing: 18) {
        MeterView(
          label: "BREACH RISK", valueText: "30", fraction: 0.30, status: .alert,
          fear: "a real threat you closed is dwelling undetected",
          spokenValue: "30 percent, ALERT")
        MeterView(
          label: "NOISE / FATIGUE", valueText: "56", fraction: 0.56, status: .hunt,
          fear: "crying wolf — Tier-2 stops trusting your tickets",
          spokenValue: "56 percent, HUNT")
        MeterView(
          label: "TIME", valueText: "22 / 90 shift-min", fraction: 22.0 / 90.0, status: .calm,
          fear: "a soft budget — surfaced, never scored",
          spokenValue: "22 of 90 shift-minutes")
        StatTileGrid(items: [
          .init(id: "acc", value: "86%", label: "Accuracy", tone: Theme.pressure, numericKey: 0.86),
          .init(id: "calls", value: "7/7", label: "Calls", numericKey: 7),
          .init(id: "missed", value: "1", label: "Missed threats", tone: Theme.truePositive),
          .init(id: "false", value: "0", label: "False escalations", tone: Theme.benign),
        ])
      }
      .padding(20)
    }

    try shot("Gallery", "ceremony") {
      VStack(spacing: 24) {
        StampView(
          text: "Escalate → IR + isolate host", tone: Theme.truePositive,
          spokenLabel: "Filed: Escalate → IR + isolate host", animates: false)
        HoldFace(title: "Hold to file · Escalate → IR", progress: 0.42)
        RankBadge(label: "TIER-1 ANALYST", size: 120, animates: false)
        LadderTrack(rungs: ContentPack.bundled.ranks.map {
          .init(id: $0.id, label: $0.label, threshold: "\($0.min)", held: $0.min <= 40)
        })
      }
      .padding(24)
    }
  }

  // MARK: - The kit (acceptance #7)

  @Test("ComponentKit · the harness view C9 mounts at ViewID.kit")
  func kit() throws {
    // `scrolls: false`: `ImageRenderer` does not rasterise a `ScrollView`'s content.
    // Two passes, because the whole catalogue is ~4800 pt tall and one surface that
    // size is past what the PNG encoder will take — the `blocks` parameter is there
    // for exactly this, and the two halves together are the whole kit.
    try shot("ComponentKit", "chrome", scale: 2) {
      ComponentKitView(
        scrolls: false, blocks: [.chrome, .controls, .sheet, .pressure, .tones],
        now: Self.clock)
    }
    try shot("ComponentKit", "content", scale: 2) {
      ComponentKitView(scrolls: false, blocks: [.rows, .ceremony, .ladder, .prose])
    }
  }

  // MARK: - Dynamic Type stress (SPEC §4.5: .xSmall … .accessibility1)

  /// The `SystemBar` is the one strip drawn on six screens, it is the strip the
  /// player reads position and queue depth off, and it is the strip that has the
  /// least room. So it is stressed at both ends of the §4.5 clamp and at the
  /// narrowest device the deck supports — a truncated `QUEUE 3/7` on any of these
  /// frames is a regression, not a cosmetic one.
  ///
  /// 375 pt is the real floor (the narrowest iPhone that runs the 18.0 deployment
  /// target); 320 pt is rendered as a courtesy frame, one device generation below
  /// anything this app installs on.
  @Test("SystemBar · the §4.5 Dynamic Type clamp, and a 320 pt phone")
  func systemBarUnderStress() throws {
    let frames: [(String, CGFloat, DynamicTypeSize)] = [
      ("390-xxxLarge", 390, .xxxLarge),
      ("390-accessibility1", 390, .accessibility1),
      ("430-xxxLarge", 430, .xxxLarge),
      ("375-accessibility1", 375, .accessibility1),
      ("320-large", 320, .large),
      ("320-accessibility1", 320, .accessibility1),
    ]
    for (name, width, typeSize) in frames {
      try shot("SystemBar", name, width: width, typeSize: typeSize) {
        VStack(spacing: 0) {
          SystemBar(
            leading: "SENTRY · SOC", wallet: ["⬢ 80", "¢ 650"], settingsLabel: "Settings",
            settingsAction: {})
          ForEach(Self.bands, id: \.0) { status, label, bpm in
            SystemBar(
              leading: "‹ 3/7", leadingAction: {},
              trace: .init(status: status, label: label, bpm: bpm, now: Self.clock),
              pill: .init(text: "QUEUE 3/7", action: {}),
              settingsLabel: "Settings", settingsAction: {})
          }
        }
      }
    }
  }

  /// The rest of the deck at the ceiling, for the same reason — a row that reflows
  /// is fine, a row that collides or overflows is not.
  ///
  /// **One `shot` per component, deliberately.** Stacking several of these under a
  /// single unbounded height proposal makes `ImageRenderer` mis-size the cards'
  /// backgrounds and produces a PNG that looks like clipping the components do not
  /// have. Rendering each on its own is the frame that tells the truth.
  @Test("rows and cards at .accessibility1 on a 320 pt phone")
  func rowsUnderStress() throws {
    let width: CGFloat = 320
    let size = DynamicTypeSize.accessibility1

    try shot("Stress", "QueueRow-locked", width: width, typeSize: size) {
      QueueRow(
        title: "Shift 3 · the lockout queue", count: "3 alerts",
        statusLine: "⬡ LOCKED · opens at ⬢ 80", state: .locked,
        spokenHint: "Locked. Opens at 80 standing.", action: {}
      ).padding(16)
    }
    try shot("Stress", "SourceRow", width: width, typeSize: size) {
      SourceRow(
        label: "EDR process tree", question: "What spawned this, and what did it do after?",
        cost: "6m", pullTitle: "Pull the log  6m", isPeeked: true,
        spokenLabel: "EDR process tree", onTap: {}, onPull: {}
      ).padding(16)
    }
    try shot("Stress", "SegmentedTabs", width: width, typeSize: size) {
      SegmentedTabs(
        items: [
          .init(id: 0, title: "SOURCES", badge: "3/6"),
          .init(id: 1, title: "EVIDENCE", badge: "3"),
        ], selection: .constant(1)
      ).padding(16)
    }
    try shot("Stress", "Dock", width: width, typeSize: size) {
      Dock(title: "Make the call", hint: "3 findings · 26m", action: {}).padding(16)
    }
    try shot("Stress", "StatTileGrid", width: width, typeSize: size) {
      StatTileGrid(items: [
        .init(id: "acc", value: "86%", label: "Accuracy", tone: Theme.pressure),
        .init(id: "calls", value: "7/7", label: "Calls"),
      ]).padding(16)
    }
    try shot("Stress", "MeterView", width: width, typeSize: size) {
      MeterView(
        label: "BREACH RISK", valueText: "30", fraction: 0.30, status: .alert,
        fear: "a real threat you closed is dwelling undetected",
        spokenValue: "30 percent, ALERT"
      ).padding(16)
    }
  }

  // MARK: - Machinery

  /// **The clock these PNGs are drawn at** (P1-9).
  ///
  /// Eleven of the images below contain a live `ECGCanvas`, whose scroll phase is a
  /// function of `Date()`. They therefore changed on every single run, which made
  /// `git status` after `xcodebuild test` a wall of modified binaries and made the one
  /// artefact that should shout about a visual regression impossible to read. A
  /// pinned instant — an arbitrary one, chosen only for being fixed — makes them
  /// byte-stable, and `ECGCanvas.now` is the seam that takes it.
  ///
  /// It is deliberately not a round number of beats: at phase 0 every band draws the
  /// same flat run-in, and a snapshot that hides the difference between CALM and
  /// LOCKDOWN is worse than a noisy one.
  private static let clock = Date(timeIntervalSinceReferenceDate: 812_345_678.137)

  /// Whether this run may write to `docs/screenshots/ios/components/`.
  ///
  /// **Off by default** (P1-9). A test suite that rewrites eleven committed binaries
  /// as a side effect of `xcodebuild test` dirties the working tree on every CI run
  /// and every local check, and a dirty tree is how a real change gets committed by
  /// accident. The rendering still happens either way — an `ImageRenderer` that
  /// returns nothing, or a view that traps, still fails the test — so the coverage is
  /// unchanged; only the write is opt-in. Regenerate with
  /// `SENTRY_SNAPSHOTS=1 xcodebuild test …`.
  private static let writesPNGs: Bool =
    ProcessInfo.processInfo.environment["SENTRY_SNAPSHOTS"] == "1"

  /// The four bands with the BPM the bundle actually carries — never a literal, so
  /// a retune in `tuning.ts` re-times the ECG in these PNGs too (D7).
  private static let bands: [(TraceStatus, String, Int)] = {
    let bpm = ContentPack.bundled.tuning.bpm
    let labels: [TraceStatus: String] = [
      .calm: ContentPack.bundled.copy.chromeText("statusCalm"),
      .alert: TraceStatus.alert.rawValue,
      .hunt: TraceStatus.hunt.rawValue,
      .lockdown: TraceStatus.lockdown.rawValue,
    ]
    return TraceStatus.allCases.map { ($0, labels[$0] ?? $0.rawValue, bpm[$0]) }
  }()

  /// 390 pt wide (the §2.2 design width), rendered at scale 3 in the dark scheme —
  /// the only scheme the app has (§4.6) — onto the real ground colour, so what lands
  /// on disk is what a player sees and not a component floating on white.
  private func shot(
    _ component: String, _ state: String, height: CGFloat? = nil,
    width: CGFloat = Self.width, typeSize: DynamicTypeSize = .large, scale: CGFloat = 3,
    @ViewBuilder view: () -> some View
  ) throws {
    let content =
      view()
      .frame(width: width)
      .frame(height: height)
      .background(Theme.ground)
      .environment(\.colorScheme, .dark)
      .dynamicTypeSize(typeSize)

    let renderer = ImageRenderer(content: content)
    renderer.scale = scale
    renderer.isOpaque = true
    renderer.proposedSize = ProposedViewSize(width: width, height: height)

    let image = try #require(
      renderer.uiImage, "ImageRenderer produced nothing for \(component)-\(state)")
    let data = try #require(image.pngData(), "PNG encoding failed for \(component)-\(state)")

    guard Self.writesPNGs else { return }
    let url = Self.outputDirectory.appending(path: "\(component)-\(state).png")
    try FileManager.default.createDirectory(
      at: Self.outputDirectory, withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  private static let width: CGFloat = 390

  /// `<repo>/docs/screenshots/ios/components/`, resolved from `#filePath` — this
  /// file is at `ios/SentrySOC/Tests/Components/`, so the repo root is five
  /// components up. Resolving from the source path rather than from a build setting
  /// keeps the artefact in the repo whatever `-derivedDataPath` the caller used.
  private static let outputDirectory: URL = {
    var root = URL(filePath: #filePath)
    for _ in 0..<5 { root = root.deletingLastPathComponent() }
    return root.appending(path: "docs/screenshots/ios/components", directoryHint: .isDirectory)
  }()
}
