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

  /// `.iOS` is the same selection run against a career that has already sat in the
  /// other chair (R1): the nudge is never emitted, and the two lines that only make
  /// sense to someone who HAS sat there are voiced by Vale. The fixture carries the
  /// re-voiced bodies, so this is a straight comparison — nothing is transformed on
  /// the way in, which is the point of R1 regenerating `handler.json`.
  @Test("the iOS inbox is the fixture, message for message", arguments: try Golden.handler().scenarios)
  func iOSInbox(_ scenario: HandlerScenario) {
    let inbox = Golden.voice.inboxFor(scenario.career, scenario.event, features: .iOS)
    Golden.expectEqual(inbox, scenario.messagesBlueOnly, scenario.name)
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

  /// The cap is four in both seats, and on the blue seat the nudge never takes one of
  /// the four slots — so the message behind it is admitted instead of leaving a hole.
  /// That promotion is the point of `cap-four`, and the whole of R1's behaviour change.
  @Test("the cap is four, and the nudge never occupies one of them")
  func capIsFour() throws {
    let capacity = ContentPack.bundled.tuning.handler.inboxCapacity
    #expect(capacity == 4)
    for scenario in try Golden.handler().scenarios {
      #expect(
        Golden.voice.inboxFor(scenario.career, scenario.event, features: .all).count
          <= capacity)
      #expect(
        Golden.voice.inboxFor(scenario.career, scenario.event, features: .iOS).count
          <= capacity)
    }

    let capped = try #require(try Golden.handler().scenarios.first { $0.name == "cap-four" })
    let web = Golden.voice.inboxFor(capped.career, capped.event, features: .all)
    let blue = Golden.voice.inboxFor(capped.career, capped.event, features: .iOS)

    // Five messages qualify. The web cap cuts the kit tip; the blue seat never
    // selects the nudge, so the kit tip takes its slot — same length, different tail.
    #expect(web.map(\.id) == ["ev-clean", "ev-rankup", "ev-unlock-handoff-shift", "tip-redrun"])
    #expect(blue.map(\.id) == ["ev-clean", "ev-rankup", "ev-unlock-handoff-shift", "tip-kit"])
  }

  /// R1's property, asserted the way the exporter asserts it: removing the nudge can
  /// promote at most one message, and nothing else about the list may move.
  @Test(
    "the blue seat differs only by the nudge and the two re-voicings",
    arguments: try Golden.handler().scenarios)
  func blueOnlyDiff(_ scenario: HandlerScenario) throws {
    let web = Golden.voice.inboxFor(scenario.career, scenario.event, features: .all)
    let blue = Golden.voice.inboxFor(scenario.career, scenario.event, features: .iOS)
    let kept = web.filter { $0.id != "tip-redrun" }

    #expect(!blue.contains { $0.id == "tip-redrun" }, "\(scenario.name)")
    #expect(blue.count >= kept.count, "\(scenario.name): the blue seat lost a message")
    #expect(blue.count - kept.count <= 1, "\(scenario.name): more than one message appeared")

    for (i, webMessage) in kept.enumerated() where i < blue.count {
      let blueMessage = blue[i]
      #expect(blueMessage.id == webMessage.id, "\(scenario.name) position \(i)")

      guard let key = Self.blueOnlyKey(for: webMessage, event: scenario.event) else {
        #expect(blueMessage == webMessage, "\(scenario.name)/\(webMessage.id)")
        continue
      }
      // The re-voiced pair: Vale's name, the blue-only body and tone, the same beat
      // and the same rendered subject.
      let template = try #require(Golden.copy.handler.templates[key])
      let sender = try #require(Golden.copy.handler.senders[template.sender])
      #expect(blueMessage.from == sender.from, "\(scenario.name)/\(webMessage.id)")
      #expect(blueMessage.role == sender.role, "\(scenario.name)/\(webMessage.id)")
      #expect(blueMessage.body == template.body, "\(scenario.name)/\(webMessage.id)")
      #expect(blueMessage.tone == template.tone, "\(scenario.name)/\(webMessage.id)")
      #expect(blueMessage.subject == webMessage.subject, "\(scenario.name)/\(webMessage.id)")
    }
  }

  /// The two ids DESIGN §3.2 hands to Vale on a build with no red seat.
  private static func blueOnlyKey(for message: HandlerMessage, event: HandlerEvent) -> String? {
    switch message.id {
    case "ev-unlock-handoff-shift": "ev-unlock-handoff-blue-only"
    case "ev-rankup" where event.rankUp?.id == "t2": "ev-rankup-t2-blue-only"
    default: nil
    }
  }

  /// The cross-seat nudge never reaches this build, in any scenario.
  @Test("tip-redrun is never drawn on the blue seat")
  func nudgeIsSuppressed() throws {
    for scenario in try Golden.handler().scenarios {
      let blue = Golden.voice.inboxFor(scenario.career, scenario.event, features: .iOS)
      #expect(!blue.contains { $0.id == "tip-redrun" })
    }

    // …and it is the standing-90 rule that emits it on the web, unchanged — the
    // threshold now read from `content.tuning.handler` (R6).
    let nudgeStanding = ContentPack.bundled.tuning.handler.redRunNudgeStanding
    #expect(nudgeStanding == 90)
    let nudge = CareerState(standing: nudgeStanding, redRunsDone: 0)
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

  /// **DV-7.** `handler.json` now carries the re-voicing in `messagesBlueOnly`
  /// itself (R1), so there is no transform on the way into the comparison above:
  /// Mercer signs the Shift 4 unlock and the Tier-2 rank-up in `messagesAll` only.
  /// The tests below pin the shape of that divergence — one template swap deep,
  /// sender included, and nothing else about either message moves.
  ///
  /// The re-voiced pair changes the sender and the body and nothing else — which is
  /// what lets the fixture keep the rendered subject.
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
