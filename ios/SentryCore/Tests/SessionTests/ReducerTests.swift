import Foundation
import Testing

@testable import SentryCore

/// Every transition of the seventeen-action machine (§10 C5 #1), and both guards.
///
/// The guards are the reason this suite exists at all. A disabled button is a look;
/// a reducer guard is a rule, and only the rule survives a second call site — the
/// dock CTA, a VoiceOver action, a QA jump, a restored snapshot.
@Suite("Session reducer")
struct ReducerTests {

  // MARK: - The shape of the machine

  @Test("the machine has exactly seventeen actions")
  func seventeenActions() {
    // §2.1's fifteen, minus CONTINUE (G6), plus VIEW_RESULT (G5) and ACK_FIRSTRUN (G19).
    #expect(SocAction.allCaseShapes().count == 17)
  }

  @Test("HYDRATE changes nothing — the launch already decided what the first frame is")
  func hydrateIsInert() {
    var run = Deck.Run()
    // The app hands in the first-run cover, because only it can read UserDefaults.
    run.state.view = .firstRun
    let effects = run.send(.hydrate)

    #expect(run.state.view == .firstRun)
    #expect(run.state.phase == .hub)
    #expect(effects.isEmpty)
  }

  // MARK: - Starting a board

  @Test("START_SHIFT assembles the board, opens the briefing and commits")
  func startShift() {
    var run = Deck.Run()
    let effects = run.send(.startShift(Deck.firstShift.id))

    #expect(run.state.phase == .briefing)
    #expect(run.state.shift?.shiftId == Deck.firstShift.id)
    #expect(run.state.shift?.caseIds == Deck.firstShift.caseIds)
    #expect(run.state.shift?.index == 0)
    #expect(run.state.shift?.timeBudget == Deck.tuning.timeBudgetDefault)
    #expect(run.state.view == nil)
    #expect(run.state.status == .calm)
    #expect(effects == [.haptic(.commitSoft)])
  }

  @Test("START_SHIFT is refused when the board is locked, and says so")
  func startShiftRespectsTheLadder() throws {
    let locked = Deck.pack.shifts.first { $0.unlockStanding > 0 }
    let shift = try #require(locked)

    var run = Deck.Run(career: .initial)                 // standing 0
    let effects = run.send(.startShift(shift.id))

    #expect(run.state.phase == .hub, "a locked board must not open")
    #expect(run.state.shift == nil)
    #expect(effects == [.haptic(.denied)])

    // The same tap with the standing the ladder asks for.
    var earned = Deck.Run(career: CareerState(standing: shift.unlockStanding))
    earned.send(.startShift(shift.id))
    #expect(earned.state.phase == .briefing)
  }

  @Test("START_SHIFT opens today's daily board, which is not in shiftsByID")
  func startShiftOpensTheDaily() {
    var run = Deck.Run(career: Deck.workingCareer)
    let daily = Deck.dailyShift
    #expect(Deck.pack.shift(daily.id) == nil, "the daily board is built on demand (S9)")

    run.send(.startShift(daily.id))

    #expect(run.state.phase == .briefing)
    #expect(run.state.shift?.caseIds == daily.caseIds)
  }

  @Test("BEGIN enters the case and opens the board sheet once")
  func begin() {
    var run = Deck.Run()
    run.send(.startShift(Deck.firstShift.id))
    let effects = run.send(.begin)

    #expect(run.state.phase == .investigating)
    #expect(run.state.view == .board)
    #expect(effects == [.persistSession])

    // …and never again on its own: the second case does not re-open it.
    run.send(.closeView)
    run.send(.makeCall(.escalateIRIsolate))
    run.send(.nextCase)
    #expect(run.state.phase == .investigating)
    #expect(run.state.view == nil)
  }

  @Test("BEGIN from anywhere but the briefing is inert")
  func beginIsGuarded() {
    var run = Deck.Run()
    #expect(run.send(.begin).isEmpty)
    #expect(run.state.phase == .hub)
  }

  @Test("the intel-feed kit pre-pulls threat-intel on every case that has it")
  func kitPrePull() {
    let owner = CareerState(cash: 0, standing: 0, gear: [KitPrePull.itemID])
    var run = Deck.Run(career: owner)
    run.send(.startShift(Deck.firstShift.id))

    #expect(run.state.queried == [KitPrePull.sourceID])
    run.send(.begin)
    #expect(run.state.queried == [KitPrePull.sourceID], "BEGIN applies the same set (§2.1)")

    // And on the next case, not just the first (`SocConsole.tsx:272`).
    run.send(.closeView)
    run.send(.makeCall(.escalateIRIsolate))
    run.send(.nextCase)
    #expect(run.state.queried == [KitPrePull.sourceID])

    // Without the kit, a board opens blind.
    var poor = Deck.Run(career: .initial)
    poor.send(.startShift(Deck.firstShift.id))
    #expect(poor.state.queried.isEmpty)
  }

  // MARK: - Views and the two guards

  @Test("OPEN_VIEW puts a sheet on top and CLOSE_VIEW takes it off")
  func openAndCloseView() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)

    let sourceID = Deck.socCase(Deck.firstShift.caseIds[0]).sourceIds[0]
    let effects = run.send(.openView(.source(sourceID)))
    #expect(run.state.view == .source(sourceID))
    #expect(effects == [.haptic(.select)])

    run.send(.closeView)
    #expect(run.state.view == nil)
  }

  /// `SocConsole.tsx:495`, as a rule rather than a `disabled` attribute.
  @Test("OPEN_VIEW(.call) is refused until a finding has been revealed")
  func callSheetNeedsEvidence() throws {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    #expect(run.state.revealedEvidence(Deck.pack).isEmpty)

    let blocked = run.send(.openView(.call))
    #expect(run.state.view == nil, "the call sheet opened with nothing revealed")
    #expect(blocked == [.haptic(.denied)])

    // Pull the source that carries this case's findings, then it opens.
    let current = try #require(run.state.currentCase(Deck.pack))
    let carrying = try #require(current.evidence.first?.sourceId)
    run.send(.pullSource(carrying))
    #expect(!run.state.revealedEvidence(Deck.pack).isEmpty)

    let allowed = run.send(.openView(.call))
    #expect(run.state.view == .call)
    #expect(allowed == [.haptic(.select)])
  }

  @Test("PULL_SOURCE is idempotent, commits, and persists")
  func pullSource() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    let sourceID = Deck.socCase(Deck.firstShift.caseIds[0]).sourceIds[0]

    let first = run.send(.pullSource(sourceID))
    #expect(run.state.queried == [sourceID])
    #expect(first == [.haptic(.commitSoft), .persistSession])

    let again = run.send(.pullSource(sourceID))
    #expect(run.state.queried == [sourceID], "a source cannot be pulled twice")
    #expect(again.isEmpty)
  }

  @Test("PULL_SOURCE outside the case screen is inert")
  func pullSourceIsPhaseGuarded() {
    var run = Deck.Run()
    run.send(.startShift(Deck.firstShift.id))          // still on the briefing
    let sourceID = Deck.socCase(Deck.firstShift.caseIds[0]).sourceIds[0]
    #expect(run.send(.pullSource(sourceID)).isEmpty)
    #expect(run.state.queried.isEmpty)
  }

  @Test("PICK_DISPOSITION holds the pick until the call is filed")
  func pickDisposition() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)

    #expect(run.send(.pickDisposition(.escalateTier2)) == [.haptic(.select)])
    #expect(run.state.pendingDisposition == .escalateTier2)

    run.send(.makeCall(.escalateTier2))
    #expect(run.state.pendingDisposition == nil, "a filed call clears the pick")
  }

  // MARK: - Filing a call

  @Test("MAKE_CALL grades through SentryCore, moves both meters and lands on the debrief")
  func makeCall() throws {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    let current = try #require(run.state.currentCase(Deck.pack))
    let sourceID = current.sourceIds[0]
    run.send(.pullSource(sourceID))

    let effects = run.send(.makeCall(current.correctDisposition))

    // The board the engine would produce from the same call, computed independently.
    let expected = Deck.engine.applyCall(
      Deck.engine.assembleShift(Deck.firstShift.id, Deck.firstShift.caseIds),
      current, current.correctDisposition,
      queriedSourceIds: [sourceID],
      timeSpent: current.sources.first { $0.id == sourceID }?.cost ?? 0)

    #expect(run.state.shift == expected)
    #expect(run.state.phase == .debrief(readOnly: false))
    #expect(run.state.view == nil)
    #expect(run.state.status == Deck.engine.overallShiftStatus(expected))
    #expect(run.state.last?.caseId == current.id)
    #expect(run.state.last?.chosen == current.correctDisposition)
    #expect(run.state.last?.grade == Deck.engine.gradeCall(current, current.correctDisposition))
    // One cue, the onboarding flag (first case of the board), one write.
    #expect(
      effects == [
        .haptic(.file), .setFlag(SentryFlagKey.onboarding, true), .persistSession,
      ])
  }

  /// The re-entrancy guard, `SocConsole.tsx:234`.
  @Test("a second MAKE_CALL on a filed case does nothing at all")
  func makeCallReEntrancyGuard() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    run.send(.makeCall(.escalateIRIsolate))
    let filed = run.state

    let effects = run.send(.makeCall(.closeFalsePositive))

    #expect(run.state == filed, "the second call moved the board")
    #expect(effects.isEmpty, "the second call buzzed")
  }

  @Test("the onboarding flag is written on the opening case and no other")
  func onboardingFlagIsWrittenOnce() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)

    let first = run.send(.makeCall(.escalateIRIsolate))
    #expect(first.contains(.setFlag(SentryFlagKey.onboarding, true)))

    run.send(.nextCase)
    let second = run.send(.makeCall(.escalateIRIsolate))
    #expect(!second.contains(.setFlag(SentryFlagKey.onboarding, true)))
  }

  // MARK: - Moving on

  @Test("NEXT_CASE walks to the next alert and clears the previous case's pulls")
  func nextCase() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    let sourceID = Deck.socCase(Deck.firstShift.caseIds[0]).sourceIds[0]
    run.send(.pullSource(sourceID))
    run.send(.makeCall(.escalateIRIsolate))

    let effects = run.send(.nextCase)

    #expect(run.state.phase == .investigating)
    #expect(run.state.queried.isEmpty, "the next case starts clean")
    #expect(run.state.last == nil)
    #expect(run.state.shift?.index == 1)
    #expect(run.state.currentCase(Deck.pack)?.id == Deck.firstShift.caseIds[1])
    #expect(effects == [.persistSession])
  }

  @Test("the last NEXT_CASE settles the board and stops on the summary")
  func nextCaseCompletesTheShift() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    run.playToCompletion()

    #expect(run.state.phase == .complete)
    #expect(run.state.settlement != nil)
    #expect(run.state.last == nil)
    #expect(run.state.shift != nil, "the summary still draws the board it just closed")
  }

  @Test("NEXT_CASE on the rank-up screen is inert — it cannot pay the board twice")
  func nextCaseIsInertOnTheRankUpScreen() throws {
    // Standing one below the next rung, so the board promotes and the summary routes
    // to `.milestone` with the finished shift still on the session.
    let ladder = try #require(Deck.pack.ranks.first { $0.min > 0 })
    var run = Deck.Run(career: CareerState(standing: ladder.min - 1))
    run.startAndBegin(Deck.firstShift.id)
    run.playToCompletion()
    run.send(.nextCase)                                 // summary → rank-up
    #expect(run.state.phase == .milestone)

    let ranked = run.state
    let paid = run.career

    // §2.12's CTA is labelled "Continue ▸", the same as the summary's, so this is the
    // action a mis-wired rank-up screen would send. It must do nothing at all: no
    // second settlement, no second payout, no bounce back to the summary.
    #expect(run.send(.nextCase).isEmpty)
    #expect(run.state == ranked, "NEXT_CASE moved the rank-up screen")
    #expect(run.career == paid, "the board paid twice")
    #expect(run.effects.filter { $0 == .settleShift }.count == 1)
    #expect(run.effects.filter { $0 == .persistCareer }.count == 1)
    #expect(run.effects.filter { $0 == .clearSession }.count == 1)

    // ACK_MILESTONE is the exit, and it still works.
    run.send(.ackMilestone)
    #expect(run.state == .atHub)
  }

  // MARK: - VIEW_RESULT (G5)

  @Test("VIEW_RESULT re-opens a filed call read-only and returns whence it came")
  func viewResult() throws {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    let firstCaseID = Deck.firstShift.caseIds[0]
    run.send(.makeCall(.escalateIRIsolate))
    run.send(.nextCase)                                  // now investigating case 2

    let effects = run.send(.viewResult(firstCaseID))

    #expect(run.state.phase == .debrief(readOnly: true))
    #expect(run.state.last?.caseId == firstCaseID)
    #expect(run.state.last?.chosen == .escalateIRIsolate)
    #expect(effects.isEmpty, "re-reading a call is not an event")

    run.send(.nextCase)
    #expect(run.state.phase == .investigating, "a read-only debrief returns to the board")
    #expect(run.state.shift?.index == 1, "and does not advance anything")
  }

  @Test("VIEW_RESULT from the summary returns to the summary")
  func viewResultFromTheSummary() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    run.playToCompletion()

    run.send(.viewResult(Deck.firstShift.caseIds[2]))
    #expect(run.state.phase == .debrief(readOnly: true))

    run.send(.nextCase)
    #expect(run.state.phase == .complete)
    #expect(run.state.settlement != nil, "the settlement survived the detour")
  }

  @Test("VIEW_RESULT on a case that was never called is refused")
  func viewResultGuard() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)

    let effects = run.send(.viewResult(Deck.firstShift.caseIds[3]))
    #expect(run.state.phase == .investigating)
    #expect(effects.isEmpty)

    #expect(run.send(.viewResult("no-such-case")).isEmpty)
  }

  // MARK: - Leaving

  @Test("ACK_MILESTONE, TO_HUB and ABANDON each return to a clean desk from their own phase")
  func waysBackToTheHub() throws {
    // ABANDON — from a played board, the only way off one that is not 16:00.
    var abandoning = Deck.Run()
    abandoning.startAndBegin(Deck.firstShift.id)
    abandoning.send(.pullSource(Deck.socCase(Deck.firstShift.caseIds[0]).sourceIds[0]))
    abandoning.send(.makeCall(.escalateIRIsolate))
    abandoning.send(.abandon)
    #expect(abandoning.state == .atHub, "ABANDON left something behind")

    // TO_HUB — from the briefing, where nothing is committed (§2.1).
    var backing = Deck.Run()
    backing.send(.startShift(Deck.firstShift.id))
    backing.send(.toHub)
    #expect(backing.state == .atHub, "TO_HUB left something behind")

    // ACK_MILESTONE — from the rank-up screen the settlement routed to. Standing one
    // below the next rung, so the board is guaranteed to promote.
    let ladder = try #require(Deck.pack.ranks.first { $0.min > 0 })
    var ranked = Deck.Run(career: CareerState(standing: ladder.min - 1))
    ranked.startAndBegin(Deck.firstShift.id)
    ranked.playToCompletion()
    ranked.send(.nextCase)
    #expect(ranked.state.phase == .milestone, "the fixture board no longer ranks anyone up")
    ranked.send(.ackMilestone)
    #expect(ranked.state == .atHub, "ACK_MILESTONE left something behind")
  }

  @Test("§2.1's phase guards: the exits are refused from a live board")
  func leavingIsGuardedByPhase() {
    // TO_HUB mid-board is inert. Dropping the queue here would strand `session.json`
    // on disk — no `.clearSession` rides on TO_HUB, and none should: ABANDON is the
    // action that throws a board away.
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    let board = run.state
    #expect(run.send(.toHub).isEmpty)
    #expect(run.state == board, "TO_HUB abandoned a live board")

    // START_SHIFT mid-board is inert too — it would swap the board out from under
    // its own snapshot.
    #expect(run.send(.startShift(Deck.firstShift.id)).isEmpty)
    #expect(run.state == board, "START_SHIFT replaced a board that was in play")

    // ACK_MILESTONE belongs to the rank-up screen alone.
    #expect(run.send(.ackMilestone).isEmpty)
    #expect(run.state == board, "ACK_MILESTONE walked off a live board")
  }

  @Test("ABANDON throws the snapshot away and says so")
  func abandon() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)

    let effects = run.send(.abandon)
    #expect(effects == [.haptic(.destructive), .clearSession])
  }

  @Test("TO_HUB from the briefing leaves the desk clean and writes nothing")
  func toHubFromTheBriefing() {
    var run = Deck.Run()
    run.send(.startShift(Deck.firstShift.id))          // briefing: nothing committed

    // No `.clearSession`, because nothing has been saved: `.persistSession` first
    // fires on BEGIN. Only ABANDON deletes a snapshot.
    #expect(run.send(.toHub).isEmpty)
    #expect(run.state == .atHub)
  }

  @Test("TO_HUB closes whatever is on top of the hub")
  func toHubFromTheHub() {
    var run = Deck.Run(state: SessionState(view: .kit))

    #expect(run.send(.toHub).isEmpty)
    #expect(run.state == .atHub)
  }

  @Test("ACK_FIRSTRUN closes the cover and writes the gate")
  func ackFirstRun() {
    var run = Deck.Run(state: SessionState(view: .firstRun))

    let effects = run.send(.ackFirstRun)
    #expect(run.state.view == nil)
    #expect(effects == [.setFlag(SentryFlagKey.firstRun, true)])
  }

  // MARK: - RESUME (R9)

  @Test("RESUME carries the snapshot through the reducer, not around it")
  func resume() throws {
    var live = Deck.Run()
    live.startAndBegin(Deck.firstShift.id)
    let current = try #require(live.state.currentCase(Deck.pack))
    live.send(.pullSource(try #require(current.evidence.first?.sourceId)))
    live.send(.openView(.call))
    live.send(.pickDisposition(.escalateTier2))
    let snapshot = live.state

    var relaunched = Deck.Run()
    relaunched.send(.resume(snapshot))

    #expect(relaunched.state.shift == snapshot.shift)
    #expect(relaunched.state.queried == snapshot.queried)
    #expect(relaunched.state.phase == .investigating)
    // §4.3: an open sheet and a half-picked disposition are deliberately not restored.
    #expect(relaunched.state.view == nil)
    #expect(relaunched.state.pendingDisposition == nil)
  }

  @Test("RESUME with no board is refused")
  func resumeNeedsABoard() {
    var run = Deck.Run()
    #expect(run.send(.resume(.atHub)).isEmpty)
    #expect(run.state == .atHub)
  }

  @Test("a debrief restored from a snapshot rebuilds its graded call")
  func resumeRebuildsTheDebrief() {
    var live = Deck.Run()
    live.startAndBegin(Deck.firstShift.id)
    live.send(.makeCall(.escalateTier2))

    // `SessionSnapshot` (C6) stores phase / shift / queried / status only, so the
    // graded call is gone. The reducer regrades it from the filed result.
    var stripped = live.state
    stripped.last = nil

    var relaunched = Deck.Run()
    relaunched.send(.resume(stripped))

    #expect(relaunched.state.phase == .debrief(readOnly: false))
    #expect(relaunched.state.last?.caseId == Deck.firstShift.caseIds[0])
    #expect(relaunched.state.last?.chosen == .escalateTier2)
    #expect(relaunched.state.last == live.state.last)
  }

  // MARK: - Buying

  @Test("BUY commits and persists when the purchase takes")
  func buyTakes() throws {
    let item = try #require(Deck.pack.kit.first)
    var run = Deck.Run(career: CareerState(cash: item.cost, standing: 0))

    let effects = run.send(.buy(item.id))
    #expect(effects == [.haptic(.commitSoft), .persistCareer])
  }

  @Test("BUY is refused — and persists nothing — when it is unaffordable or owned")
  func buyRefused() throws {
    let item = try #require(Deck.pack.kit.first)

    var broke = Deck.Run(career: CareerState(cash: item.cost - 1))
    #expect(broke.send(.buy(item.id)) == [.haptic(.denied)])

    var owner = Deck.Run(career: CareerState(cash: item.cost, gear: [item.id]))
    #expect(owner.send(.buy(item.id)) == [.haptic(.denied)])

    var unknown = Deck.Run(career: CareerState(cash: 99_999))
    #expect(unknown.send(.buy("no-such-gear")) == [.haptic(.denied)])
  }

  // MARK: - Settings

  @Test("SET_SETTING confirms the tap, then writes the flag")
  func setSetting() {
    var run = Deck.Run()
    for key in SettingKey.allCases {
      let effects = run.send(.setSetting(key, false))
      #expect(effects == [.haptic(.select), .setFlag(key.rawValue, false)])
    }
    // The five launch-critical keys are the three settings plus the two gates (§4.3).
    #expect(SettingKey.allCases.count == 3)
    #expect(
      Set(SettingKey.allCases.map(\.rawValue) + [SentryFlagKey.firstRun, SentryFlagKey.onboarding])
        .count == 5)
  }

  // MARK: - The coach cursor (S4)

  @Test("the coach walks its three steps on the opening case and then stops")
  func coachCursor() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)

    let steps = Deck.pack.copy.coachSteps
    #expect(run.state.currentCoachStep(Deck.pack)?.anchor == steps[0].anchor)

    // Step 1 advances on the first pull.
    run.send(.pullSource(Deck.socCase(Deck.firstShift.caseIds[0]).sourceIds[0]))
    #expect(run.state.coachStep == 1)
    #expect(run.state.currentCoachStep(Deck.pack)?.advance == .button)

    // A second pull does not advance a `button` step.
    run.send(.pullSource(Deck.socCase(Deck.firstShift.caseIds[0]).sourceIds[1]))
    #expect(run.state.coachStep == 1)

    // "Got it" is a dismissal with nothing on top — that is CLOSE_VIEW.
    run.send(.closeView)
    #expect(run.state.coachStep == 2)
    #expect(run.state.currentCoachStep(Deck.pack)?.advance == .terminal)

    // A terminal step never advances.
    run.send(.closeView)
    #expect(run.state.coachStep == 2)

    // …and the coach does not speak on the second alert.
    run.send(.makeCall(.escalateIRIsolate))
    run.send(.nextCase)
    #expect(run.state.currentCoachStep(Deck.pack) == nil)
  }

  @Test("closing a sheet is not a coach advance")
  func closingASheetIsNotACoachAdvance() {
    var run = Deck.Run()
    run.send(.startShift(Deck.firstShift.id))
    run.send(.begin)                                     // the board sheet is up
    #expect(run.state.view == .board)

    run.send(.closeView)
    #expect(run.state.view == nil)
    #expect(run.state.coachStep == 0, "dismissing the board advanced the coach")
  }
}
