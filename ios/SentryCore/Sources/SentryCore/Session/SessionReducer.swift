import Foundation

/// The whole of the deck's behaviour, as one pure function (D9).
///
/// `(SessionState, SocAction) → (SessionState, [Effect])`. No I/O, no clock of its
/// own, no storage, no haptics: everything that has to *happen* leaves as an
/// `Effect` for `EffectRunner` to interpret. That is what makes the seventeen
/// transitions and both guards testable without a simulator, and it is why the
/// re-entrancy guard and the revealed-evidence guard live **here** and not in a
/// disabled button (§10 C5 #1).
///
/// **DV-5:** there is no TypeScript counterpart to fixture-guard this against — the
/// web keeps the same state in a dozen `useState`s inside `SocConsole.tsx`. Every
/// rule below therefore names the line it was lifted from.
///
/// **DV-7 (new, reported to the lead):** the signature gains `now:`, defaulted.
/// Three transitions genuinely need today's date — resolving the daily board,
/// suppressing its repeat standing award (Appendix A G7) and stamping the ledger —
/// and a function that reads `Date()` internally is not pure and cannot be tested
/// across a day boundary. Every existing call site is unchanged.
///
/// **DV-8 (new, reported to the lead — for the C11 doc pass on `SPEC.md` §3.3/§4.1):**
/// `HYDRATE` is inert here. §2.1's HYDRATE row is "→ hub, plus `view:"firstRun"` if
/// the gate is unset", and the gate lives in `UserDefaults`, which a pure reducer
/// cannot read and whose value this signature has no parameter for. The app therefore
/// *constructs* that first session (`GameModel.init`) and sends `.hydrate` as the
/// seam; the action stays in the machine so the count is still seventeen and so the
/// launch has one named transition rather than a silent assignment. The alternative —
/// threading the two gate booleans into `reduce` — buys nothing: no other transition
/// reads them.
///
/// - Parameters:
///   - state: the session as it stands.
///   - action: what the player asked for.
///   - content: the bundle. The reducer reads it; it never mutates it.
///   - career: the career as it stands. The reducer **only reads** the career —
///     every change to it is an `Effect` the model applies (D8).
///   - now: the clock, injected. Defaults to the real one.
/// - Returns: the next session, and what has to happen because of it.
public func reduce(
  _ state: SessionState,
  _ action: SocAction,
  content: ContentPack,
  career: CareerState,
  now: Date = Date()
) -> (SessionState, [Effect]) {
  var next = state
  var effects: [Effect] = []
  // Cheap: value types over the already-decoded bundle. Built here rather than
  // captured so the reducer stays a free function with no stored state.
  let engine = SOCEngine(content: content)
  let rules = CareerRules(content: content)

  switch action {

  case .hydrate:
    // Inert on purpose — see DV-8 above. The launch has already decided what the
    // first frame is: the app builds the starting session (hub, plus the first-run
    // cover when the gate is unset) and hands it in. Nothing here can read
    // `UserDefaults`, and nothing here should.
    break

  case .startShift(let shiftID):
    // §2.1 opens a board from the hub and nowhere else. Unguarded, a START_SHIFT
    // arriving mid-board would swap the board out without a `.clearSession`, leaving
    // `session.json` describing a queue nobody is playing any more.
    guard state.phase == .hub,
          let def = shiftDefinition(shiftID, in: content, on: now)
    else { break }
    // §2.1: `isUnlocked(career, def)` must hold. A locked row is disabled in the
    // hub, but the rule that makes it true lives here — and a refused tap is the
    // one place `denied` is specified (§2.15).
    guard rules.isUnlocked(career, def) else {
      effects.append(.haptic(.denied))
      break
    }
    next = SessionState(
      phase: .briefing,
      shift: engine.assembleShift(def.id, def.caseIds),
      queried: prePulled(def.caseIds.first, career, content, rules))
    effects.append(.haptic(.commitSoft))

  case .begin:
    guard state.phase == .briefing, let shift = state.shift else { break }
    next.phase = .investigating
    // The board opens once per shift, on the first case, then never again unless
    // asked (§2.5).
    next.view = .board
    // §2.1 hangs the intel-feed pre-pull on BEGIN; `SocConsole.tsx:282` hangs it on
    // START_SHIFT. It is the same set either way — a briefing pulls nothing — so it
    // is applied at both ends and is idempotent.
    next.queried = prePulled(shift.caseIds.first, career, content, rules)
    effects.append(.persistSession)

  case .resume(let restored):
    // The snapshot arrives as the payload (R9), so a restore is a transition rather
    // than an assignment the reducer never saw. An open sheet and a half-picked
    // disposition are deliberately not restored (§4.3): coming back from a cold
    // launch into a modal is disorienting, and every sheet is one tap away.
    guard restored.shift != nil else { break }
    next = restored
    next.view = nil
    next.pendingDisposition = nil
    // `session.json` stores the board, not the grade (C6's `SessionSnapshot`). A
    // debrief restored without its `last` would be an empty hero screen, so it is
    // rebuilt from the filed result — the same arithmetic, run again.
    if next.phase.isDebrief, next.last == nil {
      next.last = outcome(for: next.shift?.results.last, content, engine)
    }

  case .openView(let view):
    // SocConsole.tsx:495 — the disposition buttons are `disabled` until at least one
    // finding has been revealed. That is a *rule*, not a look: it lives here, so a
    // second call site (the dock CTA, a VoiceOver action, a QA jump) cannot skip it.
    if view == .call {
      guard state.phase == .investigating, !state.revealedEvidence(content).isEmpty else {
        effects.append(.haptic(.denied))
        break
      }
    }
    next.view = view
    effects.append(.haptic(.select))

  case .closeView:
    if state.view == nil {
      // Nothing is on top, so this is the *other* dismissal the deck has: the coach
      // bubble's "Got it" (S4's `advance: "button"`). Routing it through CLOSE_VIEW
      // is what keeps the machine at seventeen actions.
      next.coachStep = advancedCoach(state, on: .button, content)
      break
    }
    next.view = nil

  case .pullSource(let sourceID):
    guard state.phase == .investigating, !state.queried.contains(sourceID) else { break }
    next.queried.append(sourceID)
    next.coachStep = advancedCoach(state, on: .onFirstSourcePulled, content)
    // `select`, not `commitSoft` (P1-10). DESIGN §2.15 assigns commit-soft to exactly
    // four events — "Start the shift" · Buy kit · Unlock card appears · payout
    // count-up ends — and a source pull is none of them; the table files it under
    // "source row tap → select". The findings are not fired here either: each one
    // fires its own `findingLand` as it lands in the sheet, capped at three (§5.5),
    // and a cue here as well would double every pull.
    effects.append(.haptic(.select))
    effects.append(.persistSession)

  case .pickDisposition(let disposition):
    guard state.phase == .investigating else { break }
    next.pendingDisposition = disposition
    effects.append(.haptic(.select))

  case .makeCall(let disposition):
    // The re-entrancy guard (`SocConsole.tsx:234`): one call per case, and the
    // second tap on a filed call does nothing at all — no second grade, no second
    // meter move, no second buzz.
    guard state.phase == .investigating,
          let shift = state.shift,
          let current = state.currentCase(content)
    else { break }
    let timeSpent = state.timeSpentOnCurrentCase(content)
    // `applyCall` does all of it: grades, appends the ordered result, moves both
    // meters through `Trace.clamp` and advances the index. No meter arithmetic
    // exists in this app (D8).
    let filed = engine.applyCall(
      shift, current, disposition, queriedSourceIds: state.queried, timeSpent: timeSpent)
    next.shift = filed
    next.status = engine.overallShiftStatus(filed)
    next.last = CallOutcome(
      caseId: current.id, chosen: disposition, grade: engine.gradeCall(current, disposition))
    next.phase = .debrief(readOnly: false)
    next.view = nil
    next.pendingDisposition = nil
    effects.append(.haptic(.file))
    // `SocConsole.tsx:241`, verbatim: the coach is done the moment the player files
    // their first real call, so it cannot re-fire on the next shift or reload.
    if shift.index == 0 { effects.append(.setFlag(SentryFlagKey.onboarding, true)) }
    effects.append(.persistSession)

  case .nextCase:
    // §2.1 gives NEXT_CASE two rows: the debrief's advance and the summary's
    // continue. The phase is named here rather than inferred from `shift != nil`,
    // which is still true on the rank-up screen — and the settle path at the bottom
    // of this arm *pays the board*, so a NEXT_CASE that reached it from `.milestone`
    // would award a second time. That is not hypothetical: §2.12 labels the rank-up
    // CTA "Continue ▸", the same words as the summary's, so wiring it to the same
    // action is a one-line mistake. `.milestone` takes ACK_MILESTONE and nothing else.
    guard let shift = state.shift,
          state.phase.isDebrief || state.phase == .complete
    else { break }

    if state.phase.isReadOnly {
      // G5: a read-only debrief returns to the phase it was opened from — the board
      // (still investigating) or the summary (the board is finished). VIEW_RESULT
      // names those two phases and no others, and a board is complete in exactly one
      // of them, so `shiftComplete` here reads back the phase it came from rather
      // than guessing at it.
      next.last = nil
      next.phase = engine.shiftComplete(shift) ? .complete : .investigating
      break
    }

    if state.phase == .complete {
      // G6: `complete → milestone | hub`. §5.9: milestone iff the shift ranked you
      // up or opened a board — which the settlement computed at 16:00 and carries.
      if let settlement = state.settlement, settlement.isMilestone {
        next.phase = .milestone
        next.last = nil
        next.view = nil
        break
      }
      next = .atHub
      break
    }

    next.last = nil
    guard engine.shiftComplete(shift) else {
      next.phase = .investigating
      next.view = nil
      // `SocConsole.tsx:272` — the next case starts with the kit's pre-pull and
      // nothing else.
      next.queried = prePulled(
        shift.index < shift.caseIds.count ? shift.caseIds[shift.index] : nil,
        career, content, rules)
      effects.append(.persistSession)
      break
    }

    // 16:00. The settlement is computed HERE, purely, on the career the reducer was
    // handed — `scoreShift → awardForShift → unlock diff`, in that order
    // (`SocConsole.tsx:251-270`) — and travels on the session. `.settleShift` is
    // then the app *applying* a value, not a second copy of the same arithmetic.
    let settled = settlement(for: shift, career: career, content: content, now: now)
    next.settlement = settled
    next.phase = .complete
    next.view = nil
    next.queried = []
    effects.append(.settleShift)
    // G7: the daily board pays cash every run and standing once a calendar day. The
    // stamp lands *after* the settled career, which still carries yesterday's.
    if settled.isDaily { effects.append(.markDailyDone(settled.day)) }
    effects.append(.persistCareer)
    effects.append(.clearSession)

  case .viewResult(let caseID):
    // **The originating phases, named** (P1-10). G5 says a read-only debrief
    // "returns to the phase it was opened from", and there are exactly two places
    // that can open one: the board sheet's done rows (still `.investigating`) and the
    // summary's glyph strip (`.complete`). Naming them here is what makes NEXT_CASE's
    // return a fact rather than an inference — and it stops a QA jump or a stray
    // VIEW_RESULT from the hub or a live debrief opening a screen with nowhere to go
    // back to.
    guard state.phase == .investigating || state.phase == .complete else { break }
    // G5's guard: `caseId ∈ shift.results`. Re-grading the stored call is how the
    // re-read debrief gets its `CallGrade` — the fold is pure, so it cannot differ
    // from what was shown when the call was filed.
    guard let result = state.shift?.result(for: caseID),
          let outcome = outcome(for: result, content, engine)
    else { break }
    next.last = outcome
    next.phase = .debrief(readOnly: true)
    next.view = nil

  case .ackMilestone:
    // §2.1: the rank-up screen's one exit, and only its. From a live board this
    // would drop the queue and leave its snapshot behind (see TO_HUB).
    guard state.phase == .milestone else { break }
    next = .atHub

  case .ackFirstRun:
    next.view = nil
    effects.append(.setFlag(SentryFlagKey.firstRun, true))

  case .toHub:
    // §2.1 allows this from the briefing — nothing is committed yet, so the back
    // control on the handover header is safe and the board is dropped with no
    // snapshot to clear — and from the hub, where it is the "close whatever is on
    // top" reset the QA jumps and a dismissed sheet both want. From a live board it
    // is refused: leaving a played queue without a `.clearSession` would strand
    // `session.json` on disk describing a board the model no longer holds, and the
    // hub could not offer it until the next cold launch. Those exits are ABANDON
    // (throw it away) and the 16:00 settlement (bank it).
    guard state.phase == .hub || state.phase == .briefing else { break }
    next = .atHub

  case .abandon:
    next = .atHub
    effects.append(.haptic(.destructive))
    effects.append(.clearSession)

  case .buy(let itemID):
    // The debit is `CareerRules.buyKit` and it happens in the model: the reducer
    // only ever reads the career, so the wallet cannot move from here. What the
    // reducer decides is whether the purchase *takes* — `buyKit` returns the career
    // untouched when the item is owned or unaffordable — and therefore whether the
    // player feels a commit or a refusal, and whether anything is written at all.
    guard let item = content.kit.first(where: { $0.id == itemID }),
          rules.buyKit(career, item) != career
    else {
      effects.append(.haptic(.denied))
      break
    }
    effects.append(.haptic(.commitSoft))
    effects.append(.persistCareer)

  case .setSetting(let key, let value):
    // §2.15 files a settings toggle under `select`. It is emitted before the flag so
    // that switching haptics *off* still confirms the tap that did it.
    effects.append(.haptic(.select))
    effects.append(.setFlag(key.rawValue, value))
  }

  return (next, effects)
}

// MARK: - The pure pieces the transitions lean on

/// The 16:00 chain as one value (`SocConsole.tsx:251-270` + Appendix A G7).
///
/// Pure, and a function of the career it is given — so calling it twice with the
/// same inputs cannot pay twice, and calling it once is the only thing the reducer
/// does.
public func settlement(
  for shift: ShiftState, career: CareerState, content: ContentPack, now: Date = Date()
) -> ShiftSettlement {
  let engine = SOCEngine(content: content)
  let rules = CareerRules(content: content)

  let score = engine.scoreShift(shift)
  let day = DailyCalendar.isoDay(now)
  let isDaily = shiftDefinition(shift.shiftId, in: content, on: now)?.kind == .daily
  // G7: standing once a calendar day on the daily board; cash pays every run,
  // because a grind that pays nothing is a grind nobody runs.
  let suppressed = isDaily && career.dailyDoneOn == day

  var reward = rules.awardForShift(career, score)
  if suppressed {
    var state = reward.state
    state.standing = career.standing
    reward = ShiftReward(
      state: state, cashGain: reward.cashGain, standingGain: 0, rankUp: nil)
  }

  // DV-9 (P1-3): record the board. **After** the award, so the ledger travels on the
  // settled career the model adopts and `persistCareer` writes; and campaign boards
  // only, because a daily id carries its date and the daily's own state is
  // `dailyDoneOn`. `awardForShift` is left alone — it is parity-guarded against the
  // TypeScript, which has no such field.
  if !isDaily {
    var state = reward.state
    state.clearedShiftIDs.insert(shift.shiftId)
    reward = ShiftReward(
      state: state, cashGain: reward.cashGain, standingGain: reward.standingGain,
      rankUp: reward.rankUp)
  }

  // The diff is taken across the award, so a board that opened on this payout is
  // announced exactly once.
  let unlocked = content.shifts
    .filter { !rules.isUnlocked(career, $0) && rules.isUnlocked(reward.state, $0) }
    .map { UnlockedShift(id: $0.id, label: $0.label) }

  return ShiftSettlement(
    shiftId: shift.shiftId, day: day, isDaily: isDaily, score: score, reward: reward,
    unlocked: unlocked, careerBefore: career, standingSuppressed: suppressed)
}

/// A campaign board comes from `shiftsByID`; the daily board is built on demand from
/// the template and is not in it (S9).
public func shiftDefinition(
  _ shiftID: String, in content: ContentPack, on now: Date = Date()
) -> ShiftDef? {
  if let campaign = content.shift(shiftID) { return campaign }
  let today = content.dailyShift(on: now)
  return today.id == shiftID ? today : nil
}

/// `SocConsole.tsx:96` — the one kit item that changes how a case opens: owning the
/// intel feed means the threat-intel enrichment is already on the board.
///
/// The two ids are content, not tuning, and the web spells them at the call site;
/// they are named here once so a rename is one edit and a missing source is a no-op
/// rather than a phantom pull.
public enum KitPrePull {
  public static let itemID = "intel-feed"
  public static let sourceID = "threat-intel"
}

private func prePulled(
  _ caseID: String?, _ career: CareerState, _ content: ContentPack, _ rules: CareerRules
) -> [String] {
  guard let caseID, let socCase = content.case(caseID),
        rules.owns(career, KitPrePull.itemID),
        socCase.sourceIds.contains(KitPrePull.sourceID)
  else { return [] }
  return [KitPrePull.sourceID]
}

/// Rebuild the debrief's graded call from a filed result.
private func outcome(
  for result: CaseResult?, _ content: ContentPack, _ engine: SOCEngine
) -> CallOutcome? {
  guard let result, let socCase = content.case(result.caseId) else { return nil }
  return CallOutcome(
    caseId: result.caseId, chosen: result.chosen,
    grade: engine.gradeCall(socCase, result.chosen))
}

/// The coach cursor moves only when the step showing says this is what advances it
/// (S4's `advance`). A `terminal` step is the end of the coach and never moves; a
/// step whose trigger has not fired stays put.
private func advancedCoach(
  _ state: SessionState, on trigger: CopyPack.CoachAdvance, _ content: ContentPack
) -> Int {
  guard let step = state.currentCoachStep(content), step.advance == trigger else {
    return state.coachStep
  }
  return state.coachStep + 1
}
