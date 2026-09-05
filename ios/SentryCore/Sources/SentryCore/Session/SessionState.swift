import Foundation

/// The graded call the debrief is about (§5.8).
///
/// The web keeps `last: { case, chosen, grade }` in a `useState` beside the shift;
/// here it rides on the session so a re-read debrief (`VIEW_RESULT`, Appendix A G5)
/// and a lived one are the same screen fed by the same field, and so a restored
/// snapshot can rebuild it instead of showing an empty hero.
///
/// The *case* is not stored — only its id. A `SocCase` is 6 KB of prose that is
/// already in the bundle, and duplicating it into `session.json` would put player
/// copy in the save file where a content update could not reach it.
public struct CallOutcome: Codable, Sendable, Hashable {
  public let caseId: String
  public let chosen: Disposition
  /// `SentryCore`'s arithmetic, never the app's (D8).
  public let grade: CallGrade

  public init(caseId: String, chosen: Disposition, grade: CallGrade) {
    self.caseId = caseId
    self.chosen = chosen
    self.grade = grade
  }

  public func socCase(_ content: ContentPack) -> SocCase? { content.case(caseId) }
}

/// What 16:00 did to the career — computed **in the reducer**, on the career the
/// reducer was handed, before anything is written (§4.1's settlement chain).
///
/// It exists so that the one place that decides `scoreShift → awardForShift →
/// unlock diff` is the pure function, and `GameModel.settleShift()` becomes an
/// *application* of this value rather than a second implementation of the same
/// arithmetic. A double award is then not a bug you can write: there is only one
/// computation, and `complete → milestone | hub` (Appendix A G6) reads its result
/// instead of guessing.
public struct ShiftSettlement: Codable, Sendable, Hashable {
  public let shiftId: String
  /// The ISO day the board settled on — the ledger key of Appendix A G7.
  public let day: String
  public let isDaily: Bool
  public let score: ShiftScore
  /// `reward.state` is the settled career: cash always moves, standing may not.
  public let reward: ShiftReward
  public let unlocked: [UnlockedShift]
  /// The career as it stood at 15:59, for the summary's standing sweep (§5.9).
  public let careerBefore: CareerState
  /// G7: this daily board already paid standing today, so only cash moved.
  public let standingSuppressed: Bool

  public init(
    shiftId: String, day: String, isDaily: Bool, score: ShiftScore, reward: ShiftReward,
    unlocked: [UnlockedShift], careerBefore: CareerState, standingSuppressed: Bool
  ) {
    self.shiftId = shiftId
    self.day = day
    self.isDaily = isDaily
    self.score = score
    self.reward = reward
    self.unlocked = unlocked
    self.careerBefore = careerBefore
    self.standingSuppressed = standingSuppressed
  }

  /// §5.9: the summary's CTA routes to `.milestone` when the shift ranked you up or
  /// opened a board, and to the hub otherwise.
  public var isMilestone: Bool { reward.rankUp != nil || !unlocked.isEmpty }

  /// What the inbox is told happened (C4's `HandlerEvent`).
  public var eventType: HandlerEventType {
    switch score.grade {
    case .clean: .shiftClean
    case .rough: .shiftRough
    case .breached: .shiftBreached
    }
  }

  public var event: HandlerEvent {
    HandlerEvent(type: eventType, rankUp: reward.rankUp, unlocked: unlocked)
  }
}

/// The board in flight plus what is on top of it (D9).
///
/// Every field is written by `reduce(_:_:content:career:now:)` and by nothing else:
/// `send(_:)` is the app's single entry point, so "who moved the meter" has exactly
/// one answer. `Codable` because `session.json` is a snapshot of it (§4.3).
public struct SessionState: Codable, Sendable, Hashable {
  public var phase: Phase
  public var view: ViewID?
  public var shift: ShiftState?
  /// Source ids pulled on the case currently in front of the player.
  public var queried: [String]
  /// Picked on the call sheet, not yet filed.
  public var pendingDisposition: Disposition?
  /// `overallShiftStatus` of the board — the headline, and what the heartbeat reads.
  public var status: TraceStatus
  /// The graded call the debrief is showing (lived or re-read).
  public var last: CallOutcome?
  /// Present from the moment the board completes until the player leaves the
  /// summary. The Shift Summary and the Rank-up screen both read it.
  public var settlement: ShiftSettlement?
  /// Cursor into `copy.coachSteps` for the Shift-1 coach (S4). Whether the coach
  /// draws at all is the app's question (`settings.coaching && !hasSeenOnboarding`);
  /// *which* step is showing is this.
  public var coachStep: Int

  /// Parameter order is load-bearing: `SessionSnapshot` (C6) calls this with the
  /// first six labels, so everything C5 added carries a default.
  public init(
    phase: Phase = .hub,
    view: ViewID? = nil,
    shift: ShiftState? = nil,
    queried: [String] = [],
    pendingDisposition: Disposition? = nil,
    status: TraceStatus = .calm,
    last: CallOutcome? = nil,
    settlement: ShiftSettlement? = nil,
    coachStep: Int = 0
  ) {
    self.phase = phase
    self.view = view
    self.shift = shift
    self.queried = queried
    self.pendingDisposition = pendingDisposition
    self.status = status
    self.last = last
    self.settlement = settlement
    self.coachStep = coachStep
  }

  /// A fresh desk. The reducer returns to exactly this on `TO_HUB`, `ABANDON` and
  /// `ACK_MILESTONE`, so "back at the hub" is one value rather than five
  /// hand-cleared fields that can drift apart.
  public static let atHub = SessionState()

  // MARK: - Derived reads (the app never recomputes these)

  /// The case in front of the player, if any.
  public func currentCase(_ content: ContentPack) -> SocCase? {
    guard let shift, shift.index < shift.caseIds.count else { return nil }
    return content.case(shift.caseIds[shift.index])
  }

  /// The findings the player has actually uncovered — `SocConsole.tsx:218`.
  /// The `OPEN_VIEW("call")` guard is this being non-empty (§2.1, SocConsole.tsx:495).
  public func revealedEvidence(_ content: ContentPack) -> [SocEvidence] {
    guard let current = currentCase(content) else { return [] }
    return current.evidence.filter { queried.contains($0.sourceId) }
  }

  /// Shift-minutes spent on the case in front of the player — `SocConsole.tsx:223`:
  /// the case's OWN sources, filtered by what was pulled, summed by cost.
  public func timeSpentOnCurrentCase(_ content: ContentPack) -> Int {
    guard let current = currentCase(content) else { return 0 }
    return current.sources.filter { queried.contains($0.id) }.reduce(0) { $0 + $1.cost }
  }

  /// The coach step to draw, or `nil` when the cursor has run off the end.
  /// `shift.index == 0` is the web's gate (`SocConsole.tsx:515`): the coach speaks
  /// on the opening alert of a shift and never again.
  public func currentCoachStep(_ content: ContentPack) -> CopyPack.CoachStep? {
    guard phase == .investigating, shift?.index == 0,
          coachStep < content.copy.coachSteps.count
    else { return nil }
    return content.copy.coachSteps[coachStep]
  }
}
