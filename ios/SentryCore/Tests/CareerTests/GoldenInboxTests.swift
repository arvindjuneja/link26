import Foundation
import Testing

@testable import SentryCore

/// `handler.json` — 14 `(CareerState, HandlerEvent)` scenarios, each rendered under
/// both feature sets and compared **id by id and body by body**. Nothing here is
/// transcribed: every expected string is either the fixture's or the bundle's.
@Suite("Golden inbox")
struct GoldenInboxTests {

  // ── the web inbox ──────────────────────────────────────────────────────────

  /// `.all` is the TypeScript, exactly — Mercer, the cross-seat nudge and all.
  @Test("the web inbox reproduces inboxFor", arguments: try Golden.handler().scenarios)
  func webInbox(_ scenario: HandlerScenario) {
    let inbox = Golden.voice.inboxFor(scenario.career, scenario.event, features: .all)
    Golden.expectEqual(inbox, scenario.messagesAll, scenario.name)
  }

  // ── the iOS inbox ──────────────────────────────────────────────────────────

  /// `.iOS` is the same selection with the red seat taken out of it: `tip-redrun`
  /// dropped after the cap, and the two lines that only make sense to a player who
  /// has sat in the other chair voiced by Vale (DV-7 below).
  @Test("the iOS inbox drops the cross-seat nudge", arguments: try Golden.handler().scenarios)
  func iOSInbox(_ scenario: HandlerScenario) {
    let inbox = Golden.voice.inboxFor(scenario.career, scenario.event, features: .iOS)
    let expected = scenario.messagesBlueOnly.map { revoiced($0, event: scenario.event) }
    Golden.expectEqual(inbox, expected, scenario.name)
  }

  /// `.iOS` is the default: the app never has to remember which seat it is.
  @Test("the default feature set is the blue seat", arguments: try Golden.handler().scenarios)
  func defaultFeatures(_ scenario: HandlerScenario) {
    let byDefault = Golden.voice.inboxFor(scenario.career, scenario.event)
    let explicit = Golden.voice.inboxFor(scenario.career, scenario.event, features: .iOS)
    Golden.expectEqual(byDefault, explicit, scenario.name)
  }

  // ── the shape of the fixture ───────────────────────────────────────────────

  /// The 14 scenarios the ticket names, so a fixture that quietly loses one fails
  /// here instead of passing 13 rows.
  @Test("the fixture covers all 14 scenarios")
  func scenarioCoverage() throws {
    let file = try Golden.handler()
    #expect(file.scenarios.count == 14)
    #expect(
      file.scenarios.map(\.name) == [
        "welcome-fresh", "shift-clean", "shift-rough", "shift-breached",
        "rankup-trainee", "rankup-t1", "rankup-t1-senior", "rankup-t2-clean",
        "unlock-queues", "tip-kit", "tip-redrun", "standing-90-nudge",
        "cap-four", "fresh-rankup",
      ])
  }

  /// The cap is four in both seats, and the blue-only filter runs AFTER it — so the
  /// iOS inbox is sometimes three. That asymmetry is the point of `cap-four`.
  @Test("the inbox is capped at four, and the filter runs after the cap")
  func capIsFour() throws {
    for scenario in try Golden.handler().scenarios {
      #expect(Golden.voice.inboxFor(scenario.career, scenario.event, features: .all).count <= 4)
      #expect(Golden.voice.inboxFor(scenario.career, scenario.event, features: .iOS).count <= 4)
    }

    let capped = try #require(try Golden.handler().scenarios.first { $0.name == "cap-four" })
    let web = Golden.voice.inboxFor(capped.career, capped.event, features: .all)
    let blue = Golden.voice.inboxFor(capped.career, capped.event, features: .iOS)

    // Five messages qualify; the cap keeps four, the filter then drops one.
    #expect(web.count == 4)
    #expect(web.map(\.id) == ["ev-clean", "ev-rankup", "ev-unlock-handoff-shift", "tip-redrun"])
    #expect(blue.count == 3)
    #expect(blue.map(\.id) == ["ev-clean", "ev-rankup", "ev-unlock-handoff-shift"])
    // The kit tip qualified too and was cut by the cap — never re-admitted by the
    // filter, which is what "re-applied after" has to mean.
    #expect(!blue.contains { $0.id == "tip-kit" })
  }

  /// The cross-seat nudge never reaches this build, in any scenario.
  @Test("tip-redrun is never drawn on the blue seat")
  func nudgeIsSuppressed() throws {
    for scenario in try Golden.handler().scenarios {
      let blue = Golden.voice.inboxFor(scenario.career, scenario.event, features: .iOS)
      #expect(!blue.contains { $0.id == "tip-redrun" })
    }

    // …and it is the standing-90 rule that emits it on the web, unchanged.
    let nudge = CareerState(standing: HandlerVoice.redRunNudgeStanding, redRunsDone: 0)
    #expect(Golden.voice.inboxFor(nudge, features: .all).map(\.id) == ["tip-redrun"])
    #expect(Golden.voice.inboxFor(nudge, features: .iOS).isEmpty)

    var justUnder = nudge
    justUnder.standing -= 1
    #expect(!Golden.voice.inboxFor(justUnder, features: .all).contains { $0.id == "tip-redrun" })

    var hasRun = nudge
    hasRun.redRunsDone = 1
    #expect(!Golden.voice.inboxFor(hasRun, features: .all).contains { $0.id == "tip-redrun" })
  }

  // ── DV-7: the two re-voiced lines ──────────────────────────────────────────

  /// **DV-7.** `handler.json`'s `messagesBlueOnly` is a pure filter of the web inbox
  /// (S3), so Mercer still signs the Shift 4 unlock and the Tier-2 rank-up there.
  /// This build has no red seat, so C4 §10.3 and DESIGN §3.2 hand both beats to
  /// Vale, and `copy.json` ships the replacement templates for exactly that. The transform
  /// below is the whole of the divergence; every other field of every other message
  /// is compared byte-for-byte against the fixture.
  private func revoiced(_ message: HandlerMessage, event: HandlerEvent) -> HandlerMessage {
    let key: String
    switch message.id {
    case "ev-unlock-handoff-shift": key = "ev-unlock-handoff-blue-only"
    case "ev-rankup" where event.rankUp?.id == "t2": key = "ev-rankup-t2-blue-only"
    default: return message
    }
    guard let template = Golden.copy.handler.templates[key],
      let sender = Golden.copy.handler.senders[template.sender]
    else { return message }

    return HandlerMessage(
      id: message.id, from: sender.from, role: sender.role,
      subject: message.subject, body: template.body, tone: template.tone)
  }

  /// The re-voiced pair changes the sender and the body and nothing else — which is
  /// what lets the transform above keep the fixture's rendered subject.
  @Test("the blue-only templates are the same beat in Vale's voice")
  func revoicedPair() throws {
    let templates = Golden.copy.handler.templates
    for (webKey, blueKey) in [
      ("ev-unlock-handoff", "ev-unlock-handoff-blue-only"),
      ("ev-rankup-t2", "ev-rankup-t2-blue-only"),
    ] {
      let web = try #require(templates[webKey])
      let blue = try #require(templates[blueKey])
      #expect(web.sender == .mercer)
      #expect(blue.sender == .vale)
      #expect(blue.subject == web.subject)
      #expect(blue.tone == web.tone)
      #expect(blue.body != web.body)
      // No seat, no handler, no "your own run" — the line has to read to a player
      // who has never sat in the other chair.
      #expect(!blue.body.contains("Mercer"))
      #expect(!blue.body.contains("your own"))
    }
  }

  /// The two beats, end to end on the blue seat: Vale's name on the card.
  @Test("Shift 4 and Tier-2 are Vale's on this build")
  func valeVoicesBothBeats() throws {
    let vale = try #require(Golden.copy.handler.senders[.vale])
    let mercer = try #require(Golden.copy.handler.senders[.mercer])

    let unlock = HandlerEvent(unlocked: [
      UnlockedShift(id: "handoff-shift", label: "Shift 4 · the other chair (a red team's runs)")
    ])
    let blueUnlock = try #require(
      Golden.voice.inboxFor(CareerState(standing: 120, redRunsDone: 1), unlock, features: .iOS)
        .first)
    #expect(blueUnlock.id == "ev-unlock-handoff-shift")
    #expect(blueUnlock.from == vale.from)
    #expect(blueUnlock.body == Golden.copy.handler.templates["ev-unlock-handoff-blue-only"]?.body)

    let t2 = try #require(Golden.pack.ranks.last)
    let rankUp = HandlerEvent(rankUp: t2)
    let blueRankUp = try #require(
      Golden.voice.inboxFor(CareerState(standing: 210, redRunsDone: 1), rankUp, features: .iOS)
        .first)
    #expect(blueRankUp.id == "ev-rankup")
    #expect(blueRankUp.from == vale.from)
    #expect(blueRankUp.subject.contains(t2.label))
    #expect(blueRankUp.body == Golden.copy.handler.templates["ev-rankup-t2-blue-only"]?.body)

    // The web keeps Mercer — the divergence is one flag deep, not a fork.
    let webRankUp = try #require(
      Golden.voice.inboxFor(CareerState(standing: 210, redRunsDone: 1), rankUp, features: .all)
        .first)
    #expect(webRankUp.from == mercer.from)

    // A rank-up below Tier-2 is Vale in both seats.
    let t1 = try #require(Golden.pack.ranks.first { $0.id == "t1" })
    for features in [SocFeatures.all, .iOS] {
      let message = try #require(
        Golden.voice.inboxFor(CareerState(standing: 40), HandlerEvent(rankUp: t1), features: features)
          .first)
      #expect(message.from == vale.from)
      #expect(message.subject.contains(t1.label))
    }
  }

  // ── templating ─────────────────────────────────────────────────────────────

  /// Every run in every template is one of the five names `Templating` fills, so a
  /// sixth placeholder authored upstream fails here and not on a player's screen.
  @Test("every template placeholder is a name Templating knows")
  func placeholdersAreClosed() {
    let known = Set(Templating.Placeholder.allCases.map(\.rawValue))
    for (key, template) in Golden.copy.handler.templates {
      for run in Templating.placeholders(in: template.subject) {
        #expect(known.contains(run), "\(key).subject carries {\(run)}")
      }
      for run in Templating.placeholders(in: template.body) {
        #expect(known.contains(run), "\(key).body carries {\(run)}")
      }
    }
  }

  /// Nothing reaches the hub with a brace still in it, in either seat.
  @Test("no rendered message carries an unfilled run")
  func nothingIsLeftUnfilled() throws {
    for scenario in try Golden.handler().scenarios {
      for features in [SocFeatures.all, .iOS] {
        for message in Golden.voice.inboxFor(scenario.career, scenario.event, features: features) {
          #expect(Templating.placeholders(in: message.subject).isEmpty)
          #expect(Templating.placeholders(in: message.body).isEmpty)
        }
      }
    }
  }

  /// The scan matches `CopyPack.render`'s: the runs it reports are the runs that get
  /// substituted, and a lone brace is neither reported nor eaten.
  @Test("the placeholder scan is the render's scan")
  func scanMirrorsRender() {
    #expect(Templating.placeholders(in: "no runs here") == [])
    #expect(Templating.placeholders(in: "{gap} short of {rank}") == ["gap", "rank"])
    #expect(Templating.placeholders(in: "an unterminated { run") == [])

    let filled = Templating.render(
      "{gap} short of {rank}", [.gap: "30", .rank: "Tier-1 · Senior"], through: Golden.copy)
    #expect(filled == "30 short of Tier-1 · Senior")

    // A value is never rescanned: an inserted brace stays text.
    let injected = Templating.render("{item}", [.item: "{gap}"], through: Golden.copy)
    #expect(injected == "{gap}")
  }

  // ── the derivation rules, isolated ─────────────────────────────────────────

  /// The clean-shift line carries the gap to the next rung, and swaps to the
  /// top-of-ladder line when there is no rung left.
  @Test("the clean-shift line counts the standing you still owe")
  func cleanShiftGap() throws {
    let mid = CareerState(standing: 120, shiftsCleaned: 2, redRunsDone: 1)
    let next = try #require(Golden.rules.nextRank(mid.standing))
    let clean = try #require(
      Golden.voice.inboxFor(mid, HandlerEvent(type: .shiftClean), features: .iOS).first)
    #expect(clean.id == "ev-clean")
    #expect(clean.body.contains("\(next.min - mid.standing) short of \(next.label)"))

    let topped = CareerState(standing: 400, shiftsCleaned: 9, redRunsDone: 1)
    #expect(Golden.rules.nextRank(topped.standing) == nil)
    let maxed = try #require(
      Golden.voice.inboxFor(topped, HandlerEvent(type: .shiftClean), features: .iOS).first)
    #expect(maxed.id == "ev-clean")
    #expect(maxed.body == Golden.copy.handler.templates["ev-clean-max"]?.body)
  }

  /// The kit tip fires on affordability and stops the moment you own the thing.
  @Test("the kit tip fires once, on the cash you actually have")
  func kitTip() throws {
    let feed = try #require(Golden.pack.kit.first { $0.id == "intel-feed" })

    let afford = CareerState(cash: feed.cost, standing: 40, shiftsCleaned: 1, redRunsDone: 1)
    let tip = try #require(Golden.voice.inboxFor(afford, features: .iOS).first)
    #expect(tip.id == "tip-kit")
    #expect(tip.body.contains("\(feed.cost)¢"))
    #expect(tip.body.contains(feed.label))

    var short = afford
    short.cash -= 1
    #expect(!Golden.voice.inboxFor(short, features: .iOS).contains { $0.id == "tip-kit" })

    let owned = Golden.rules.buyKit(CareerState(cash: feed.cost * 2, standing: 40, shiftsCleaned: 1, redRunsDone: 1), feed)
    #expect(!Golden.voice.inboxFor(owned, features: .iOS).contains { $0.id == "tip-kit" })
  }

  /// The welcome is the empty-inbox fallback, not a first-run flag: any other
  /// message at all displaces it.
  @Test("the welcome only lands on a genuinely fresh, silent career")
  func welcomeIsTheFallback() throws {
    #expect(Golden.voice.inboxFor(.initial, features: .iOS).map(\.id) == ["welcome"])

    let ranked = HandlerEvent(rankUp: Golden.pack.ranks.first)
    #expect(Golden.voice.inboxFor(.initial, ranked, features: .iOS).map(\.id) == ["ev-rankup"])

    #expect(
      !Golden.voice.inboxFor(CareerState(standing: 5), features: .iOS)
        .contains { $0.id == "welcome" })
    #expect(
      !Golden.voice.inboxFor(CareerState(shiftsCleaned: 1), features: .iOS)
        .contains { $0.id == "welcome" })
  }

  /// One queue that is not Shift 4 stays Vale's, and the label is the run.
  @Test("an ordinary unlock names the queue that opened")
  func ordinaryUnlock() throws {
    let shift = try #require(Golden.pack.shifts.first { $0.id == "lockout-shift" })
    let event = HandlerEvent(unlocked: [UnlockedShift(id: shift.id, label: shift.label)])
    let message = try #require(
      Golden.voice.inboxFor(CareerState(standing: 80, redRunsDone: 1), event, features: .iOS).first)

    #expect(message.id == "ev-unlock-lockout-shift")
    #expect(message.from == Golden.copy.handler.senders[.vale]?.from)
    #expect(message.subject.contains(shift.label))
    #expect(message.body.hasPrefix(shift.label))
  }
}
