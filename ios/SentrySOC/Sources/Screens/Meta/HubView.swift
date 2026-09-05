import SentryCore
import SwiftUI

/// **The Desk** — `DESIGN.md` §2.3; `SPEC.md` §5.1. Phase `.hub`.
///
/// Rank and standing, the snapshot you have not entered, what Vale has to say, the
/// ladder of boards, the kit, and one primary action in the thumb arc. Everything on
/// it is derived: there is no hub state, only the career, the inbox and the bundle.
///
/// Three rules from §5.1 that are easy to lose and are load-bearing here:
///
/// 1. **The Dock is a `.safeAreaInset(edge: .bottom)`**, so the last queue row is
///    scrollable out from under it rather than hidden behind it.
/// 2. **A locked row is inert, its reason is visible text**, never a tooltip — a
///    phone has no hover, so `⬡ LOCKED · opens at ⬢ 120` has to be on the glass.
/// 3. **`denied` fires once per hub visit.** The reducer is what refuses a locked
///    board (and emits the cue); this screen is what stops the tenth tap from
///    buzzing a tenth time.
struct HubView: View {
  let model: GameModel

  /// §5.1: "a tap still fires `denied` once per hub visit".
  ///
  /// **A visit is a visit to the hub, not a return from a sheet** (P1-7). This
  /// re-armed on `session.view` going back to `nil` as well, which turned the rule
  /// into "once per sheet dismissal": open Settings and close it, and the locked row
  /// buzzes again — and the abandon/kit/settings sheets are exactly what a player
  /// opens while browsing the ladder, so the cue the rule exists to ration came back
  /// on a loop. `onAppear` is the whole rule: `PhaseHost` keys the phase view on
  /// `session.phase`, so leaving the hub and coming back rebuilds this screen and
  /// re-arms the cue, and a sheet presented *over* it does not.
  @State private var deniedFired = false

  private var content: ContentPack { model.content }
  private var copy: CopyPack { content.copy }
  private var career: CareerState { model.career }
  private var rules: CareerRules { model.rules }

  var body: some View {
    ZStack {
      DeskGround()

      VStack(spacing: 0) {
        systemBar

        ScrollView {
          LazyVStack(alignment: .leading, spacing: 24) {
            careerHeader
            resumeCard
            inboxSection
            queuesSection
            deskLinks
          }
          .padding(.horizontal, 20)
          .padding(.top, 20)
          .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
    }
    // The ground goes under the inset and into the home-indicator strip: `Dock`
    // paints its own fade over its 72 pt, but the safe area beneath it is not its
    // frame, and without this the last queue row reads straight through it.
    .safeAreaInset(edge: .bottom, spacing: 0) {
      dock.background(Theme.ground.ignoresSafeArea(edges: .bottom))
    }
    .onAppear { deniedFired = false }
    .accessibilityIdentifier("hub.root")
  }

  // MARK: - System bar (hub mode: identity and wealth, no ECG)

  private var systemBar: some View {
    SystemBar(
      leading: copy.chromeText("wordmark"),
      wallet: [
        "\(copy.chromeText("standingUnit")) \(career.standing)",
        "\(copy.chromeText("cashUnit")) \(career.cash)",
      ],
      settingsLabel: copy.chromeText("settingsTitle"),
      settingsAction: { model.send(.openView(.settings)) })
  }

  // MARK: - Rank and the standing bar

  private var careerHeader: some View {
    MetaSection(eyebrow: copy.chromeText("hubEyebrow"), tone: Theme.benign) {
      VStack(alignment: .leading, spacing: 12) {
        // §2.16's scale files a rank under the 28 pt hero step, and the desk's rank
        // is the one identity line on the screen — at the 22 pt screen-title step it
        // read as a section heading rather than as who you are.
        Text(rules.rankFor(career.standing).label)
          .font(Typography.hero)
          .foregroundStyle(Theme.textPrimary)
          .minimumScaleFactor(0.7)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)

        standingBar
      }
    }
  }

  /// 4 pt track, `.smooth(0.6)` sweep, and the gap to the next rung counted with the
  /// native odometer (§5.1). At the top of the ladder there is no gap to state, so
  /// the bar simply reads full and the line is gone — a `0 to nil` is not a sentence.
  private var standingBar: some View {
    let rank = rules.rankFor(career.standing)
    let next = rules.nextRank(career.standing)
    let span = next.map { max(1, $0.min - rank.min) } ?? 1
    let fraction = next == nil ? 1 : min(1, max(0, Double(career.standing - rank.min) / Double(span)))

    return VStack(alignment: .leading, spacing: 7) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule(style: .continuous).fill(Theme.Zinc.z800.opacity(0.55))
          Capsule(style: .continuous)
            .fill(Theme.benign.opacity(0.85))
            .frame(width: fraction * geometry.size.width)
        }
      }
      .frame(height: 4)

      if let next {
        Text(
          copy.render(
            copy.chromeText("hubToNextRank"),
            ["gap": "\(next.min - career.standing)", "rank": next.label])
        )
        .font(Typography.meta)
        .tabularNumbers()
        .foregroundStyle(Theme.textQuiet)
        .contentTransition(.numericText(value: Double(career.standing)))
      }
    }
    .gatedAnimation(Motion.meterSweep, value: fraction)
    .accessibilityElement(children: .combine)
  }

  // MARK: - Resume (only when a snapshot is waiting)

  @ViewBuilder private var resumeCard: some View {
    if let snapshot = model.resumable {
      let shift = snapshot.shift
      Button {
        model.resume()
      } label: {
        VStack(alignment: .leading, spacing: 9) {
          Text(copy.chromeText("hubResumeEyebrow")).trackedLabel(Theme.falsePositive)

          Text(resumeLine(shift))
            .font(Typography.rowTitle)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(resumeMeters(shift)).quietLog()
            Spacer(minLength: 8)
            Text("\(copy.chromeText("hubResumeEyebrow")) \(Glyph.forward)")
              .font(Typography.meta)
              .foregroundStyle(Theme.falsePositive)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panelCard()
        .leadingRule(Theme.falsePositive.opacity(0.55))
        .contentShape(Rectangle())
      }
      .buttonStyle(PressableStyle())
      .accessibilityIdentifier("hub.resume")
    }
  }

  private func resumeLine(_ shift: ShiftState) -> String {
    copy.render(
      copy.chromeText("hubResumeLine"),
      [
        "shift": CopyPack.shortLabel(label(forShift: shift.shiftId)),
        "n": "\(min(shift.index + 1, shift.caseIds.count))",
        "m": "\(shift.caseIds.count)",
        "t": "\(shift.timeUsed)",
      ])
  }

  /// `BREACH RISK 30 · NOISE / FATIGUE 0` — both meter names come from
  /// `copy.meters`, which is the same table the briefing and the board read.
  private func resumeMeters(_ shift: ShiftState) -> String {
    let breach = copy.meters[.breach]?.label ?? ""
    let noise = copy.meters[.noise]?.label ?? ""
    return "\(breach) \(shift.breachRisk) · \(noise) \(shift.noise)"
  }

  // MARK: - Inbox

  private var inboxSection: some View {
    MetaSection(eyebrow: copy.chromeText("hubInboxEyebrow"), tone: Theme.falsePositive) {
      if model.inbox.isEmpty {
        Text(copy.chromeText("hubInboxEmpty")).quietLog()
      } else {
        VStack(spacing: 10) {
          ForEach(Array(model.inbox.enumerated()), id: \.element.id) { index, message in
            InboxCard(
              eyebrow: "\(message.from) · \(message.role)",
              subject: message.subject,
              body_: message.body,
              tone: Theme.tone(copy.handlerTone(message.tone).tone),
              counter: model.inbox.count > 1
                ? copy.render(
                  copy.chromeText("coachStepCount"),
                  ["n": "\(index + 1)", "m": "\(model.inbox.count)"])
                : nil,
              spokenLabel: "\(message.from). \(message.subject). \(message.body)")
          }
        }
      }
    }
  }

  // MARK: - The queues

  private var queuesSection: some View {
    MetaSection(eyebrow: copy.chromeText("hubQueuesEyebrow")) {
      VStack(spacing: 8) {
        ForEach(queueEntries) { entry in
          QueueRow(
            title: entry.title,
            count: entry.count,
            statusLine: entry.statusLine,
            cta: entry.cta,
            state: entry.state,
            spokenHint: entry.spokenHint,
            action: { start(entry) })
        }
      }
    }
  }

  /// One row per board. A locked row still calls `send(.startShift)` — the reducer
  /// owns the refusal and its cue — but only once per visit (§5.1).
  private func start(_ entry: QueueEntry) {
    if entry.isLocked {
      guard !deniedFired else { return }
      deniedFired = true
    }
    model.send(.startShift(entry.id))
  }

  private struct QueueEntry: Identifiable {
    let id: String
    let title: String
    let count: String
    let statusLine: String
    let cta: String?
    let state: QueueRow.State
    let spokenHint: String?
    let isLocked: Bool
  }

  /// The campaign ladder, then today's board — **unless** the desk is yours, in which
  /// case the daily is promoted to the top (§2.12's finale, §5.10).
  private var queueEntries: [QueueEntry] {
    let campaign = content.shifts.map(entry(forCampaign:))
    let today = dailyEntry
    let toppedOut = rules.rankFor(career.standing).id == content.ranks.last?.id
    return toppedOut ? [today] + campaign : campaign + [today]
  }

  /// **"Cleared" is recorded, not derived** (P1-3, DV-9).
  ///
  /// It used to be inferred from the unlock ladder: standing is earned by finishing
  /// boards and the ladder is monotonic, so "every board below the highest one you
  /// have unlocked was paid for". Sound, and wrong twice. It called a board you had
  /// never opened *cleared* the moment your standing passed the next gate — a clean
  /// Shift 1 pays ⬢ 40, which opens Shift 2, which promptly claimed Shift 1 was the
  /// cleared one and Shift 2 the open one before a single alert of it was read. And
  /// it made the top unlocked board permanently "open", so §2.3's third Dock label
  /// ("Daily shift · <date>" once every campaign board is cleared) could never be
  /// reached at all.
  ///
  /// `career.clearedShiftIDs` is the answer to the question actually being asked. The
  /// reducer writes it at 16:00, so a board is cleared when it has been *played to a
  /// settlement* and at no other moment.
  private func entry(forCampaign shift: ShiftDef) -> QueueEntry {
    let unlocked = rules.isUnlocked(career, shift)
    let isOpen = unlocked && !career.clearedShiftIDs.contains(shift.id)
    let state: QueueRow.State = !unlocked ? .locked : (isOpen ? .open : .cleared)
    return QueueEntry(
      id: shift.id,
      title: shift.label,
      count: copy.plural("hubAlertCount", shift.caseIds.count),
      statusLine: unlocked
        ? copy.chromeText(isOpen ? "hubOpen" : "hubCleared")
        : copy.render(copy.chromeText("hubLocked"), ["n": "\(shift.unlockStanding)"]),
      cta: unlocked ? copy.chromeText("hubStart") : nil,
      state: state,
      spokenHint: unlocked
        ? nil
        : copy.render(copy.chromeText("hubLockedSpoken"), ["n": "\(shift.unlockStanding)"]),
      isLocked: !unlocked)
  }

  private var dailyEntry: QueueEntry {
    let today = Date()
    let shift = content.dailyShift(on: today)
    let unlocked = rules.isUnlocked(career, shift)
    let done = career.dailyDoneOn == DailyCalendar.isoDay(today)
    let state: QueueRow.State = !unlocked ? .locked : (done ? .dailyDone : .daily)
    return QueueEntry(
      id: shift.id,
      title: shift.label,
      count: copy.plural("hubAlertCount", shift.caseIds.count),
      statusLine: !unlocked
        ? copy.render(copy.chromeText("hubLocked"), ["n": "\(shift.unlockStanding)"])
        : copy.chromeText(done ? "hubDailyDone" : "hubDailyNote"),
      // §2.3's note is that the *status line* changes after play, not the CTA: the
      // daily board pays cash every run and standing once a day (Appendix A G7), so
      // it stays startable and hiding its CTA would be a lie.
      cta: unlocked ? copy.chromeText("hubStart") : nil,
      state: state,
      spokenHint: unlocked
        ? nil
        : copy.render(copy.chromeText("hubLockedSpoken"), ["n": "\(shift.unlockStanding)"]),
      isLocked: !unlocked)
  }

  // MARK: - Kit and About

  private var deskLinks: some View {
    MetaPanel {
      Button {
        model.send(.openView(.kit))
      } label: {
        MetaRow(title: copy.chromeText("hubKitEyebrow"), titleColor: Theme.textTertiary) {
          Text(
            "\(copy.render(copy.chromeText("queueCount"), ["n": "\(ownedKit)", "m": "\(content.kit.count)"])) \(Glyph.forward)"
          )
          .font(Typography.meta)
          .tabularNumbers()
          .foregroundStyle(Theme.falsePositive)
        }
      }
      .buttonStyle(PressableStyle())
      .accessibilityIdentifier("hub.kit")

      MetaDivider()

      Button {
        model.send(.openView(.settings))
      } label: {
        MetaRow(title: copy.chromeText("hubAbout"), titleColor: Theme.textTertiary) {
          Text(Glyph.forward)
            .font(Typography.meta)
            .foregroundStyle(Theme.textQuiet)
        }
      }
      .buttonStyle(PressableStyle())
      .accessibilityIdentifier("hub.about")
    }
  }

  private var ownedKit: Int {
    content.kit.filter { rules.owns(career, $0.id) }.count
  }

  // MARK: - The Dock (§2.3's label rule)

  private var dock: some View {
    Dock(title: dockTitle, action: dockAction)
  }

  /// **§2.3's three-label rule, as one value** (P1-3).
  ///
  /// `Resume Shift 2 · alert 3/8` when a snapshot is waiting · `Clock in · <the next
  /// board you have not cleared>` · `Daily shift · <date>` once every campaign board
  /// is cleared.
  ///
  /// A rule, not a rendering: the label and the tap have to agree — a CTA that reads
  /// `Clock in · Shift 2` and starts Shift 3 is worse than either — so both come off
  /// this one enum, and a test can read it without a view (`HubDockTests`).
  ///
  /// The fourth arm has no §2.3 label because §2.3 assumed the third was the end of
  /// the ladder. It is not: a player can clear every board their standing has opened
  /// while boards above them are still locked (a rough Shift 1 pays ⬢ 15 and Shift 2
  /// opens at ⬢ 40). "Daily shift" would be a lie there — the daily itself opens at
  /// ⬢ 40 — so the CTA offers the replay that is actually available, which is what
  /// the queue rows already call `cleared · replay`.
  enum DockTarget: Equatable {
    case resume(ShiftState)
    /// A board to clock in to — the next uncleared one, or the highest cleared one
    /// when the ladder is gated above you.
    case clockIn(ShiftDef)
    case daily(ShiftDef)
  }

  /// The rule. Pure — career, bundle, clock in; one target out.
  static func dockTarget(
    resumable: ShiftState?, career: CareerState, content: ContentPack, rules: CareerRules,
    today: Date
  ) -> DockTarget? {
    if let resumable { return .resume(resumable) }

    let campaign = content.shifts.filter { $0.kind == .campaign }
    let unlocked = campaign.filter { rules.isUnlocked(career, $0) }

    if let next = unlocked.first(where: { !career.clearedShiftIDs.contains($0.id) }) {
      return .clockIn(next)
    }
    // Every campaign board cleared — §2.3's third label, reachable at last.
    if !campaign.isEmpty, campaign.allSatisfy({ career.clearedShiftIDs.contains($0.id) }) {
      return .daily(content.dailyShift(on: today))
    }
    // Everything open has been cleared, but the ladder goes on: replay the last one.
    if let last = unlocked.last { return .clockIn(last) }
    return nil
  }

  private var dockTarget: DockTarget? {
    Self.dockTarget(
      resumable: model.resumable?.shift, career: career, content: content, rules: rules,
      today: Date())
  }

  private var dockTitle: String {
    switch dockTarget {
    case .resume(let shift):
      return copy.render(
        copy.chromeText("dockResume"),
        [
          "shift": CopyPack.shortLabel(label(forShift: shift.shiftId)),
          "n": "\(min(shift.index + 1, shift.caseIds.count))",
          "m": "\(shift.caseIds.count)",
        ])
    case .clockIn(let shift):
      return copy.render(
        copy.chromeText("dockClockIn"), ["shift": CopyPack.shortLabel(shift.label)])
    case .daily(let shift):
      // `chrome.dockDaily` and the daily template's own label are the same sentence
      // (`Daily shift · {date}`), and the label arrives with the date already
      // interpolated — so the board's label *is* the CTA, with no second render.
      return shift.label
    case nil:
      return ""
    }
  }

  /// The same rule, so the CTA does what it says.
  private func dockAction() {
    switch dockTarget {
    case .resume: model.resume()
    case .clockIn(let shift): model.send(.startShift(shift.id))
    case .daily(let shift): model.send(.startShift(shift.id))
    case nil: break
    }
  }

  // MARK: - Lookups

  /// A board's label by id — campaign or today's daily (which is built on demand and
  /// is not in `shiftsByID`, S9).
  private func label(forShift id: String) -> String {
    shiftDefinition(id, in: content)?.label ?? id
  }
}

#Preview("Hub · fresh career") {
  HubView(model: GameModel())
}
