import Foundation


/// `career/handler.ts`, ported message-for-message.
///
/// The point of contact — the layer that makes the career feel like someone is in
/// your corner. Vale is the blue seat's shift lead; Mercer is the red handler who
/// occasionally reaches across the seats. Messages are DERIVED from career state
/// plus the thing that just happened, so the inbox reacts to how you actually did.
///
/// Pure: state + event → the messages to show. Every string comes from
/// `copy.handler.templates`; nothing is authored here.
public struct HandlerVoice: Sendable {
  private let copy: CopyPack
  private let rules: CareerRules
  /// The two numbers `handler.ts` owns, off the **already-decoded** pack (P1-10).
  private let tuning: Tuning.HandlerTuning

  public init(content: ContentPack) {
    self.copy = content.copy
    self.rules = CareerRules(content: content)
    self.tuning = content.tuning.handler
  }

  /// The inbox to show on the hub, given state and the latest event.
  ///
  /// Ordered: what-just-happened first, then the rank beat, then the queues that
  /// opened, then the tips, then — only when there is genuinely nothing else to say
  /// — the welcome. Capped at four so it never becomes a wall.
  ///
  /// `features` picks the seat framing:
  /// - `.all` reproduces the web exactly, Mercer and all.
  /// - `.iOS` has no red seat (B1), so the selection runs against a career that has
  ///   already sat in the other chair — `redRunsDone` treated as at least 1 — and the
  ///   cross-seat nudge is therefore never emitted at all, **before** the cap rather
  ///   than after it. That matters: filtering afterwards left a hole where the nudge
  ///   had been, and the player lost a message they had earned (R1, superseding S3).
  ///   The two lines that only make sense to someone who has sat in the red chair are
  ///   voiced by Vale instead (DESIGN §3.2), through the `*-blue-only` templates.
  public func inboxFor(
    _ career: CareerState, _ ev: HandlerEvent = .init(), features: SocFeatures = .iOS
  ) -> [HandlerMessage] {
    // R1 — one substitution, and every rule below reads the same career the web does.
    var c = career
    if !features.redSeat { c.redRunsDone = Swift.max(1, career.redRunsDone) }

    var out: [HandlerMessage] = []

    func emit(_ id: String, _ key: String, _ params: [Templating.Placeholder: String] = [:]) {
      guard let built = message(id: id, templateKey: key, params: params) else { return }
      out.append(built)
    }

    switch ev.type {
    case .shiftClean:
      // The one branch inside a message: praise plus the gap to the next rung while
      // there is a rung left, praise plus the top-of-ladder line when there is not.
      if let next = rules.nextRank(c.standing) {
        emit(
          ID.clean, Key.clean,
          [.gap: String(next.min - c.standing), .rank: next.label])
      } else {
        emit(ID.clean, Key.cleanMax)
      }
    case .shiftRough:
      emit(ID.rough, Key.rough)
    case .shiftBreached:
      emit(ID.breach, Key.breach)
    case nil:
      break
    }

    if let rankUp = ev.rankUp {
      // Tier-2 is the cross-seat beat on the web — Mercer, not Vale.
      let cross = rankUp.id == RankID.t2
      let key =
        cross
        ? (features.redSeat ? Key.rankUpT2 : Key.rankUpT2BlueOnly)
        : Key.rankUp
      emit(ID.rankUp, key, [.rank: rankUp.label])
    }

    for unlocked in ev.unlocked {
      let handoff = unlocked.id == ShiftID.handoff
      let key =
        handoff
        ? (features.redSeat ? Key.unlockHandoff : Key.unlockHandoffBlueOnly)
        : Key.unlock
      emit(ID.unlockPrefix + unlocked.id, key, [.queue: unlocked.label])
    }

    // Cross-seat nudge: competent enough for the handoff desk, but has never sat in
    // the red chair. On the blue seat `c.redRunsDone` was raised above, so this rule
    // simply never fires — no filter, no hole, and the cap is free to admit whatever
    // was standing behind it.
    if c.standing >= redRunNudgeStanding && c.redRunsDone < 1 {
      emit(ID.redRunTip, Key.redRunTip)
    }

    // You can afford the kit that pays for itself.
    if let feed = rules.kitItem(KitID.intelFeed), c.cash >= feed.cost,
      !rules.owns(c, KitID.intelFeed)
    {
      emit(ID.kitTip, Key.kitTip, [.cash: String(c.cash), .item: feed.label])
    }

    // First-run welcome — only when genuinely fresh and nothing else to say.
    if out.isEmpty && c.shiftsCleaned == 0 && c.standing == 0 {
      emit(ID.welcome, Key.welcome)
    }

    assert(
      features.redSeat || !out.contains(where: { $0.id == ID.redRunTip }),
      "the blue seat selected the cross-seat nudge — R1's redRunsDone substitution is broken")
    return Array(out.prefix(capacity))
  }

  // ── assembly ───────────────────────────────────────────────────────────────

  /// Build one message from its template. A missing template or sender is a corrupt
  /// bundle: loud in DEBUG, and in release the message is dropped rather than drawn
  /// as an empty card from an unknown name.
  private func message(
    id: String, templateKey: String, params: [Templating.Placeholder: String]
  ) -> HandlerMessage? {
    guard let template = copy.handler.templates[templateKey] else {
      assertionFailure("copy.json has no handler template \(templateKey)")
      return nil
    }
    guard let sender = copy.handler.senders[template.sender] else {
      assertionFailure("copy.json has no handler sender \(template.sender.rawValue)")
      return nil
    }
    return HandlerMessage(
      id: id,
      from: sender.from,
      role: sender.role,
      subject: Templating.render(template.subject, params, through: copy),
      body: Templating.render(template.body, params, through: copy),
      tone: template.tone)
  }

  // ── the numbers and addresses of `handler.ts` ───────────────────────────────

  //  R6's two numbers now arrive the way every other tuning number does: off
  //  `content.tuning`, decoded once with the rest of the bundle (P1-10). Until this
  //  pass they were a `static let` that opened `content.json` and ran a *second*
  //  `JSONDecoder` over the whole 300 KB file for two integers — a second parse of a
  //  file the caller was already holding, with its own `fatalError` path, on a type
  //  whose whole contract is "pure: state + event → messages".

  /// The wall. `handler.ts`'s `slice(0, 4)`.
  private var capacity: Int { tuning.inboxCapacity }

  /// The standing at which the red seat starts pulling at you.
  private var redRunNudgeStanding: Int { tuning.redRunNudgeStanding }

  /// Message ids. The fixture's ids and the hub's identity — not copy.
  enum ID {
    static let clean = "ev-clean"
    static let rough = "ev-rough"
    static let breach = "ev-breach"
    static let rankUp = "ev-rankup"
    static let unlockPrefix = "ev-unlock-"
    static let redRunTip = "tip-redrun"
    static let kitTip = "tip-kit"
    static let welcome = "welcome"
  }

  /// `copy.handler.templates` keys. The `*BlueOnly` pair is the same beat with the
  /// seat taken out of it (DESIGN §3.2) — sender included, which is why the exported
  /// template carries `sender` (S2) instead of the caller picking a name.
  enum Key {
    static let clean = "ev-clean"
    static let cleanMax = "ev-clean-max"
    static let rough = "ev-rough"
    static let breach = "ev-breach"
    static let rankUp = "ev-rankup"
    static let rankUpT2 = "ev-rankup-t2"
    static let rankUpT2BlueOnly = "ev-rankup-t2-blue-only"
    static let unlock = "ev-unlock"
    static let unlockHandoff = "ev-unlock-handoff"
    static let unlockHandoffBlueOnly = "ev-unlock-handoff-blue-only"
    static let redRunTip = "tip-redrun"
    static let kitTip = "tip-kit"
    static let welcome = "welcome"
  }

  /// Content ids the selection branches on.
  enum RankID { static let t2 = "t2" }
  enum ShiftID { static let handoff = "handoff-shift" }
  enum KitID { static let intelFeed = "intel-feed" }
}
