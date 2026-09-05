import SentryCore
import SwiftUI

/// **The milestone** — `DESIGN.md` §2.12; `SPEC.md` §5.10. Phase `.milestone`.
///
/// **Two beats, not one.** §5.9 routes the shift summary here when the board
/// *ranked you up* **or** *opened a queue* (`ShiftSettlement.isMilestone`), and the
/// second is not rare: the blue-only ladder opens Shift 3 at ⬢ 80, which a second
/// clean board reaches without changing rung. Drawn as a promotion it would read
/// `PROMOTED · Tier-1 Analyst → Tier-1 Analyst`, so an unlock gets its own beat —
/// the fuchsia §2.16 spends on exactly this, the queue's name in the badge, and the
/// exported `summaryUnlocked` / `summaryUnlockedLine` lines.
///
/// The one cinematic beat in a deck that otherwise refuses decorative motion: a
/// 140 pt hexagon whose stroke draws itself over 900 ms, then fills to 10 %. Spent
/// once per rank, and instant under Reduce Motion — the beat is a reward, not a gate.
///
/// **The body is the actual message.** §5.10 is explicit: not a hardcoded headline,
/// but the `ev-rankup` line `HandlerVoice.inboxFor` would have written for this
/// promotion — so the voice that congratulates you here is the same voice that reads
/// your shifts, and a copy change to the template moves both.
///
/// **Divergence from §5.10's `.fullScreenCover`, reported to the lead.** `.milestone`
/// is a *phase*, and `PhaseHost` (C5/C6's file) renders phases into its `ZStack`;
/// only `ViewID.firstRun` goes through a cover. Presenting this as a cover would need
/// an edit to `Sources/App/PhaseHost.swift`, which §11 rule 1 forbids. The screen is
/// therefore full-bleed by construction — it paints its own ground edge to edge and
/// draws no `SystemBar`, which is what §5.10 actually asks for ("no SystemBar — the
/// one cinematic beat"). Nothing is presented over it and there is no back gesture.
struct RankUpView: View {
  let model: GameModel

  private var content: ContentPack { model.content }
  private var copy: CopyPack { content.copy }

  var body: some View {
    ZStack {
      Theme.ground.ignoresSafeArea()
      glow

      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 22) {
            RankBadge(label: badgeLabel, tone: tone, animates: true)
              .accessibilityIdentifier("rankUp.badge")

            VStack(spacing: 8) {
              Text(eyebrow).trackedLabel(tone)

              Text(headline)
                .font(Typography.hero)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

              if isFinale {
                Text(recap)
                  .font(Typography.meta)
                  .tabularNumbers()
                  .foregroundStyle(Theme.textQuiet)
                  .multilineTextAlignment(.center)
                  .accessibilityIdentifier("rankUp.recap")
              }
            }

            message

            ladder
          }
          .padding(.horizontal, 22)
          .padding(.vertical, 18)
          .frame(maxWidth: .infinity)
          // Composed, not top-aligned: the beat is one held moment, and a badge
          // pinned under the notch with 300 pt of nothing under the ladder reads as
          // a page that failed to load. Scrolls the moment it stops fitting.
          .frame(minHeight: geometry.size.height, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
    }
    .safeAreaInset(edge: .bottom) {
      Dock(title: copy.dockTitle("rankUpContinue"), tone: tone) {
        model.send(.ackMilestone)
      }
    }
    .onAppear { model.feel(.rankup) }
    .accessibilityIdentifier("rankUp.root")
  }

  // MARK: - What was earned

  /// Which beat this is. The settlement is still on the session — the reducer put it
  /// there at 16:00 and `ACK_MILESTONE` is what clears it.
  private enum Beat {
    case promotion
    case unlock([UnlockedShift])
  }

  private var beat: Beat {
    guard let settlement = model.session.settlement else { return .promotion }
    if settlement.reward.rankUp != nil { return .promotion }
    return settlement.unlocked.isEmpty ? .promotion : .unlock(settlement.unlocked)
  }

  private var unlocked: [UnlockedShift] {
    if case .unlock(let queues) = beat { return queues }
    return []
  }

  /// The rung this screen is about. `rankFor` is the fallback for a QA jump that
  /// lands here without a settlement, and for the unlock beat, where the rung has
  /// not moved and the ladder is context rather than the news.
  private var rank: Rank {
    model.session.settlement?.reward.rankUp ?? model.rules.rankFor(model.career.standing)
  }

  /// The career as it stood at 15:59, so the `from → to` line names the rung you
  /// actually left rather than the one you are standing on.
  private var previousRank: Rank {
    guard let before = model.session.settlement?.careerBefore else {
      return model.rules.rankFor(max(0, rank.min - 1))
    }
    return model.rules.rankFor(before.standing)
  }

  /// The finale is the top of the exported ladder — derived, never an id spelled here.
  private var isFinale: Bool {
    if case .unlock = beat { return false }
    return rank.id == content.ranks.last?.id
  }

  /// Emerald for a promotion; §2.16's fuchsia for the finale **and** for an unlock,
  /// which is the hue it reserves for "milestone / unlock".
  private var tone: Color {
    if case .unlock = beat { return Theme.crossover }
    return isFinale ? Theme.crossover : Theme.benign
  }

  /// The rank inside the hexagon, or — on an unlock — the queue that opened.
  private var badgeLabel: String {
    if let queue = unlocked.first { return CopyPack.shortLabel(queue.label) }
    return rank.label
  }

  private var eyebrow: String {
    if case .unlock = beat { return copy.chromeText("summaryUnlocked") }
    return copy.chromeText(isFinale ? "rankUpFinaleEyebrow" : "rankUpEyebrow")
  }

  /// `Trainee → Tier-1 Analyst`, or `New queue unlocked — <label>` per opened board.
  private var headline: String {
    if case .unlock(let queues) = beat {
      // The board's NAME at the hero step; its full billing is one card below, in
      // Vale's line. `New queue unlocked — Shift 3 · the lockout queue (mostly not a
      // threat)` set at 28 pt is three lines of headline and stops being one.
      return queues
        .map {
          copy.render(
            copy.chromeText("summaryUnlockedLine"), ["queue": CopyPack.shortLabel($0.label)])
        }
        .joined(separator: "\n")
    }
    return copy.render(
      copy.chromeText("rankUpTransition"), ["from": previousRank.label, "to": rank.label])
  }

  /// `{shifts} shifts · {clean} clean · {cases} cases read`.
  ///
  /// **Request to the lead.** `CareerState` carries `shiftsCleaned` and nothing else
  /// countable, so only `{clean}` is stored. The other two are derived from the
  /// ladder the career has opened — the boards you have worked, and the alerts on
  /// them — which is true of a player who reached the top rung but is a derivation,
  /// not a ledger. `shiftsPlayed`/`casesRead` counters on `CareerState` would make it
  /// exact; the same two counters would also make the hub's "cleared" state exact.
  private var recap: String {
    let worked = content.shifts.filter { model.rules.isUnlocked(model.career, $0) }
    // Summed into a local rather than interpolated: R12's pay-figure guard runs
    // `/\$\s?\d/` over extracted string literals, and a `$0` inside a `\( )` run is
    // exactly the closure-argument false positive it warns about.
    let alerts = worked.reduce(0) { total, shift in total + shift.caseIds.count }
    return copy.render(
      copy.chromeText("rankUpRecap"),
      [
        "shifts": "\(worked.count)",
        "clean": "\(model.career.shiftsCleaned)",
        "cases": "\(alerts)",
      ])
  }

  // MARK: - Vale's line

  /// **Not an `InboxCard`.** The hub's card clamps a body to two lines and expands on
  /// tap, which is right for a list of four messages and wrong for the one message
  /// this screen exists to deliver: a promotion the player has to *tap* to finish
  /// reading is a beat that did not land. Same card language — panel, hairline,
  /// leading tone rule, tone dot — with nothing clamped.
  @ViewBuilder private var message: some View {
    if let note = rankUpMessage {
      let noteTone = Theme.tone(copy.handlerTone(note.tone).tone)
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 8) {
          Text(Glyph.dot)
            .font(Typography.quietLog)
            .foregroundStyle(noteTone)
          Text("\(note.from) · \(note.role)").trackedLabel(noteTone)
          Spacer(minLength: 0)
        }

        Text(note.subject)
          .font(Typography.rowTitle)
          .foregroundStyle(Theme.textPrimary)
          .fixedSize(horizontal: false, vertical: true)

        Text(note.body).prose(Theme.textSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .panelCard()
      .leadingRule(noteTone.opacity(0.55))
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("rankUp.message")
    }
  }

  /// The `ev-rankup` (or `ev-unlock-*`) message for this beat, from the real handler.
  ///
  /// Asked for with an event that carries **only** what this screen is about, so the
  /// selection has exactly one what-just-happened beat to emit; `HandlerVoice` puts
  /// it first, before the tips. `.iOS` is the blue-only framing (R1), so the t2 beat
  /// and the Shift-4 unlock arrive re-voiced as Vale rather than as Mercer — which is
  /// the whole reason §5.10 says "the actual message" instead of a string.
  private var rankUpMessage: HandlerMessage? {
    let event: HandlerEvent
    if case .unlock(let queues) = beat {
      event = HandlerEvent(unlocked: queues)
    } else {
      event = HandlerEvent(rankUp: rank)
    }
    return model.voice.inboxFor(model.career, event, features: .iOS).first
  }

  // MARK: - The ladder

  private var ladder: some View {
    MetaSection(eyebrow: copy.ladder.eyebrow, tone: Theme.textQuiet) {
      VStack(alignment: .leading, spacing: 14) {
        // C7's component (P1-7). The fork this screen used to draw is gone: the
        // gutter and the flexible-frame fix it existed for now live in `LadderTrack`
        // itself, so the kit screenshot and the rank-up screen show the same ladder.
        LadderTrack(rungs: rungs, tone: tone)

        // The BTL1 / NICE framing and the "not a certification, no pay claims" line,
        // verbatim from the bundle — the credibility guardrail of Appendix A G21.
        Text(copy.ladder.note).quietLog()
      }
    }
    .padding(.top, 4)
  }

  /// The four rungs, built from the exported ranks so the track can never disagree
  /// with `CareerRules.rankFor`. Spelled as a `for` loop rather than a `map` for the
  /// same R12 reason as `recap`: no `$0` inside a string interpolation.
  private var rungs: [LadderTrack.Rung] {
    var out: [LadderTrack.Rung] = []
    for rung in content.ranks {
      let threshold = rung.min
      out.append(
        .init(
          id: rung.id, label: rung.label, threshold: "\(threshold)",
          held: threshold <= model.career.standing))
    }
    return out
  }

  // MARK: - Ground

  /// A single soft bloom behind the badge. Static: §2.14 bans idle decorative motion,
  /// and the badge's own 900 ms draw is the motion this screen is allowed.
  private var glow: some View {
    RadialGradient(
      colors: [tone.opacity(0.16), tone.opacity(0.04), .clear],
      center: .init(x: 0.5, y: 0.24), startRadius: 0, endRadius: 320)
      .ignoresSafeArea()
      .accessibilityHidden(true)
  }
}

#Preview("RankUp") {
  RankUpView(model: GameModel())
}
