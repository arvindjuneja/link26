import Foundation
import Testing

@testable import SentryCore

/// What the reducer asks the app to do, and in what order (§10 C5 #2).
///
/// The app-side twin (`SentrySOCTests/EffectScheduleTests`) proves the runner
/// performs each of these exactly once. This half proves the list is right in the
/// first place — one buzz per call, one settlement per board, and the daily ledger's
/// once-a-day standing rule.
@Suite("Effect schedule")
struct EffectScheduleTests {

  // MARK: - One call, one cue

  @Test("one MAKE_CALL emits exactly one haptic")
  func oneCallOneCue() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)

    let effects = run.send(.makeCall(.escalateIRIsolate))

    #expect(effects.compactMap(\.cue) == [.file])
  }

  @Test("no transition emits a cue a screen also owns")
  func noDoubleBuzz() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    run.send(.pullSource(Deck.socCase(Deck.firstShift.caseIds[0]).sourceIds[0]))
    run.playToCompletion()

    let cues = Set(run.effects.compactMap(\.cue))
    // `findingLand` is fired per finding by the source sheet (§5.5); the three
    // `verdict*` cues on the debrief's mount and the three `shift*` cues on the
    // summary's (§4.4). The reducer cannot know when those animations reach them,
    // so it must not fire them — the screen does, through `GameModel.feel(_:)`.
    let ownedByScreens: Set<SocCue> = [
      .findingLand, .verdictGood, .verdictOff, .verdictWrong, .breachThud,
      .shiftClean, .shiftRough, .shiftBreached, .rankup, .holdTick,
    ]
    #expect(cues.isDisjoint(with: ownedByScreens))
  }

  // MARK: - 16:00

  @Test("the settle order is settleShift → persistCareer → clearSession")
  func settleOrder() throws {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    run.playToCompletion()

    let settle = try #require(run.effects.firstIndex(of: .settleShift))
    let persist = try #require(run.effects.firstIndex(of: .persistCareer))
    let clear = try #require(run.effects.firstIndex(of: .clearSession))
    #expect(settle < persist)
    #expect(persist < clear)

    // Once each, for the whole board.
    #expect(run.effects.filter { $0 == .settleShift }.count == 1)
    #expect(run.effects.filter { $0 == .persistCareer }.count == 1)
    #expect(run.effects.filter { $0 == .clearSession }.count == 1)
  }

  @Test("a campaign board settles with exactly those three effects and no daily stamp")
  func campaignBoardHasNoDailyStamp() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    while let current = run.state.currentCase(Deck.pack) {
      run.send(.makeCall(current.correctDisposition))
      let last = run.send(.nextCase)
      if run.state.phase == .complete {
        #expect(last == [.settleShift, .persistCareer, .clearSession])
      }
    }
    #expect(!run.effects.contains { if case .markDailyDone = $0 { true } else { false } })
  }

  @Test("a second NEXT_CASE from the summary does not settle again")
  func settlementIsNotRepeatable() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    run.playToCompletion()
    let settled = run.career

    run.send(.nextCase)

    #expect(run.effects.filter { $0 == .settleShift }.count == 1)
    #expect(run.career == settled, "the board paid twice")
  }

  @Test("the settlement pays what SentryCore says, and nothing else computes it")
  func settlementIsTheEngineArithmetic() throws {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    run.playToCompletion()

    let settlement = try #require(run.state.settlement)
    let board = try #require(run.state.shift)
    let expectedScore = Deck.engine.scoreShift(board)
    var expectedReward = Deck.rules.awardForShift(.initial, expectedScore)
    // DV-9 (P1-3): the settlement is `awardForShift` plus the board's own id in the
    // cleared ledger, and nothing else. `awardForShift` stays parity-guarded against
    // a TypeScript that has no such field, so the ledger is added here, once.
    var settledState = expectedReward.state
    settledState.clearedShiftIDs.insert(Deck.firstShift.id)
    expectedReward = ShiftReward(
      state: settledState, cashGain: expectedReward.cashGain,
      standingGain: expectedReward.standingGain, rankUp: expectedReward.rankUp)

    #expect(settlement.score == expectedScore)
    #expect(settlement.reward == expectedReward)
    #expect(settlement.careerBefore == .initial)
    #expect(run.career == expectedReward.state)
    #expect(run.career.clearedShiftIDs == [Deck.firstShift.id])
  }

  /// DV-9 (P1-3) — the ledger the hub's "cleared" state and §2.3's third Dock label
  /// both read. It has to be exact, campaign-only, and idempotent across a replay.
  @Test("a settled campaign board records itself in the cleared ledger, once")
  func clearedLedger() throws {
    var run = Deck.Run()
    #expect(run.career.clearedShiftIDs.isEmpty, "a fresh career has cleared nothing")

    run.startAndBegin(Deck.firstShift.id)
    run.playToCompletion()
    #expect(run.career.clearedShiftIDs == [Deck.firstShift.id])

    // A replay of the same board does not double the entry, and does not lose it.
    let banked = run.career
    var replay = Deck.Run(career: banked)
    replay.startAndBegin(Deck.firstShift.id)
    replay.playToCompletion()
    #expect(replay.career.clearedShiftIDs == [Deck.firstShift.id])

    // The daily board keeps itself OUT of the ledger: its id carries a date, so a
    // year of dailies would be 365 dead strings in the save.
    let daily = Deck.pack.dailyShift(on: Date())
    var dailyRun = Deck.Run(career: CareerState(standing: daily.unlockStanding))
    dailyRun.startAndBegin(daily.id)
    dailyRun.playToCompletion()
    #expect(dailyRun.career.clearedShiftIDs.isEmpty, "a daily board is not a campaign board")
  }

  @Test("a board that opens another announces it exactly once")
  func unlockDiff() throws {
    // A career one clean shift below the second board's gate.
    let second = try #require(Deck.pack.shifts.first { $0.unlockStanding > 0 })
    var run = Deck.Run(career: CareerState(standing: second.unlockStanding - 1))
    run.startAndBegin(Deck.firstShift.id)
    run.playToCompletion()

    let settlement = try #require(run.state.settlement)
    #expect(settlement.unlocked.contains { $0.id == second.id })
    #expect(settlement.isMilestone)

    // The next board does not announce it a second time.
    var again = Deck.Run(career: run.career)
    again.startAndBegin(Deck.firstShift.id)
    again.playToCompletion()
    let repeated = try #require(again.state.settlement)
    #expect(!repeated.unlocked.contains { $0.id == second.id })
  }

  @Test("the summary routes to the rank-up screen only when the shift earned one")
  func milestoneRouting() throws {
    // Ranked up: standing one below the next rung.
    let ladder = try #require(Deck.pack.ranks.first { $0.min > 0 })
    var promoted = Deck.Run(career: CareerState(standing: ladder.min - 1))
    promoted.startAndBegin(Deck.firstShift.id)
    promoted.playToCompletion()
    let promotion = try #require(promoted.state.settlement)
    #expect(promotion.reward.rankUp != nil)
    promoted.send(.nextCase)
    #expect(promoted.state.phase == .milestone)
    promoted.send(.ackMilestone)
    #expect(promoted.state == .atHub)

    // Nothing earned: straight back to the desk.
    var flat = Deck.Run(career: CareerState(standing: 10_000))
    flat.startAndBegin(Deck.firstShift.id)
    flat.playToCompletion()
    let settlement = try #require(flat.state.settlement)
    #expect(!settlement.isMilestone)
    flat.send(.nextCase)
    #expect(flat.state.phase == .hub)
    #expect(flat.state.settlement == nil)
  }

  // MARK: - The daily board (Appendix A G7)

  @Test("the daily board stamps the ledger after the settlement, not before")
  func dailyStamp() throws {
    var run = Deck.Run(career: Deck.workingCareer)
    run.startAndBegin(Deck.dailyShift.id)
    run.playToCompletion()

    let settlement = try #require(run.state.settlement)
    #expect(settlement.isDaily)
    #expect(settlement.day == "2026-09-05")
    #expect(!settlement.standingSuppressed, "the first run of the day pays standing")

    let settle = try #require(run.effects.firstIndex(of: .settleShift))
    let stamp = try #require(run.effects.firstIndex(of: .markDailyDone(settlement.day)))
    let persist = try #require(run.effects.firstIndex(of: .persistCareer))
    // The settled career still carries yesterday's stamp, so the stamp lands after
    // it and before the write that puts it on disk.
    #expect(settle < stamp)
    #expect(stamp < persist)
    #expect(run.career.dailyDoneOn == settlement.day)
  }

  @Test("a repeat daily pays cash but not standing, and still stamps")
  func repeatDailySuppressesStanding() throws {
    // First run of the day.
    var first = Deck.Run(career: Deck.workingCareer)
    first.startAndBegin(Deck.dailyShift.id)
    first.playToCompletion()
    let afterFirst = first.career
    #expect(afterFirst.standing > Deck.workingCareer.standing)

    // Second run, same calendar day, same career.
    var second = Deck.Run(career: afterFirst)
    second.startAndBegin(Deck.dailyShift.id)
    second.playToCompletion()
    let settlement = try #require(second.state.settlement)

    #expect(settlement.standingSuppressed)
    #expect(settlement.reward.standingGain == 0)
    #expect(settlement.reward.rankUp == nil, "a suppressed award cannot rank you up")
    #expect(second.career.standing == afterFirst.standing, "standing paid twice")
    #expect(settlement.reward.cashGain > 0, "cash still pays — the grind stays worth running")
    #expect(second.career.cash > afterFirst.cash)
    #expect(second.effects.contains(.markDailyDone(settlement.day)))
  }

  @Test("tomorrow's daily pays standing again")
  func theLedgerIsPerDay() throws {
    var today = Deck.Run(career: Deck.workingCareer)
    today.startAndBegin(Deck.dailyShift.id)
    today.playToCompletion()

    var tomorrow = Deck.Run(career: today.career, now: Deck.tomorrow)
    let board = Deck.pack.dailyShift(on: Deck.tomorrow)
    tomorrow.startAndBegin(board.id)
    tomorrow.playToCompletion()

    let settlement = try #require(tomorrow.state.settlement)
    #expect(settlement.day == "2026-09-06")
    #expect(!settlement.standingSuppressed)
    #expect(tomorrow.career.standing > today.career.standing)
  }

  // MARK: - Writes

  @Test("every commit schedules a snapshot, and only settling or abandoning clears it")
  func snapshotSchedule() {
    var run = Deck.Run()
    run.startAndBegin(Deck.firstShift.id)
    #expect(run.effects.contains(.persistSession), "BEGIN did not write a snapshot")

    let pull = run.send(.pullSource(Deck.socCase(Deck.firstShift.caseIds[0]).sourceIds[0]))
    #expect(pull.contains(.persistSession))
    let call = run.send(.makeCall(.escalateIRIsolate))
    #expect(call.contains(.persistSession))
    #expect(!run.effects.contains(.clearSession))

    run.send(.abandon)
    #expect(run.effects.contains(.clearSession))
  }
}
