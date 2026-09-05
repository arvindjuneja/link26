import Foundation
import Testing

@testable import SentryCore

/// `career.json` — the ladder walk, the shop and the shared wallet, replayed
/// against the Swift port of `career/state.ts`.
@Suite("Golden career")
struct GoldenCareerTests {

  // ── the 12-award ladder walk ───────────────────────────────────────────────

  /// Each row is self-contained: it carries the career it starts from, so a single
  /// failure names the award rather than every award after it.
  @Test(
    "awardForShift folds a graded shift into the career",
    arguments: try Golden.career().awards)
  func award(_ row: CareerAwardRow) {
    let reward = Golden.rules.awardForShift(row.before, row.score)

    #expect(reward.cashGain == row.reward.cashGain)
    #expect(reward.standingGain == row.reward.standingGain)
    #expect(reward.state == row.reward.state)
    #expect(reward.rankUp == row.reward.rankUp)

    // rank / nextRank / the unlocked set are read AFTER the award lands.
    #expect(Golden.rules.rankFor(reward.state.standing) == row.rank)
    #expect(Golden.rules.nextRank(reward.state.standing) == row.nextRank)
    #expect(Golden.unlockedIds(reward.state) == row.unlockedIds)
  }

  /// The same 12 rows as one unbroken career: every row's `before` is the previous
  /// row's `reward.state`, so the fixture is a walk and not 12 disconnected states.
  @Test("the ladder walk is one career from ⬢0 to Tier-2")
  func ladderIsASequence() throws {
    let file = try Golden.career()
    #expect(file.awards.count == 12)

    var state = CareerState.initial
    for row in file.awards {
      #expect(state == row.before, "\(row.name): the walk is broken before this award")
      state = Golden.rules.awardForShift(state, row.score).state
    }

    #expect(state == file.awards.last?.reward.state)
    #expect(Golden.rules.rankFor(state.standing).id == "t2")
    #expect(Golden.rules.nextRank(state.standing) == nil)
    #expect(Golden.unlockedIds(state) == Golden.pack.shifts.map(\.id))
  }

  /// The blue-only ladder, walked one rung at a time: exactly one clean shift per
  /// unlock, no replays (DESIGN §3.3). ⬢160 opens the last board on standing alone,
  /// which is the second half of B1's assertion.
  @Test("each clean shift opens exactly one more board")
  func cleanRunOpensOneBoardAtATime() throws {
    let shifts = Golden.pack.shifts
    #expect(shifts.count == 5)

    for (index, shift) in shifts.enumerated() {
      let atGate = CareerState(standing: shift.unlockStanding)
      let justUnder = CareerState(standing: shift.unlockStanding - 1)
      #expect(Golden.rules.isUnlocked(atGate, shift))
      #expect(Golden.unlockedIds(atGate).count == index + 1)
      if shift.unlockStanding > 0 {
        #expect(!Golden.rules.isUnlocked(justUnder, shift))
      }
    }

    // B1 — the last board, gated on standing alone.
    let shift5 = try #require(shifts.last)
    #expect(Golden.rules.isUnlocked(CareerState(standing: 160), shift5))
  }

  /// The red-run clause is ported even though no exported shift sets it (B1): the
  /// career state is shared with the other seat, and a gate that silently stopped
  /// gating would be invisible until the day a shift asked for it.
  @Test("the red-run gate still holds on a shift that asks for one")
  func redRunGate() {
    let gated = ShiftDef(
      id: "syn-gated", label: "", caseIds: [], unlockStanding: 40,
      requiresRedRun: true, note: nil, kind: .campaign)

    #expect(!Golden.rules.isUnlocked(CareerState(standing: 999), gated))
    #expect(Golden.rules.isUnlocked(CareerState(standing: 999, redRunsDone: 1), gated))
    #expect(!Golden.rules.isUnlocked(CareerState(standing: 39, redRunsDone: 1), gated))
  }

  // ── the shop ───────────────────────────────────────────────────────────────

  @Test("buyKit spends, refuses or no-ops", arguments: try Golden.career().buys)
  func buy(_ row: CareerBuyRow) throws {
    let item = try #require(Golden.pack.kit.first { $0.id == row.itemId })
    #expect(Golden.rules.buyKit(row.before, item) == row.after)
  }

  @Test("owns reads the gear list")
  func owns() throws {
    let item = try #require(Golden.pack.kit.first)
    let bought = Golden.rules.buyKit(CareerState(cash: item.cost), item)
    #expect(!Golden.rules.owns(CareerState(), item.id))
    #expect(Golden.rules.owns(bought, item.id))
    #expect(!Golden.rules.owns(bought, "no-such-gear"))
  }

  // ── the shared wallet ──────────────────────────────────────────────────────

  @Test("awardRedRun credits the cut and the run", arguments: try Golden.career().redRuns)
  func redRun(_ row: CareerRedRunRow) {
    #expect(Golden.rules.awardRedRun(row.before, cut: row.cut) == row.after)
  }

  /// The default cut is the exported one, not a literal in the Swift.
  @Test("the default cut comes from the bundle")
  func defaultCut() {
    let credited = Golden.rules.awardRedRun(CareerState())
    #expect(credited.cash == Golden.pack.tuning.career.redRunCut)
    #expect(credited.redRunsDone == 1)
  }

  // ── DV-4: ported as written, not as intended ───────────────────────────────

  /// `rankFor` is `state.ts`'s ascending last-match loop and `nextRank` its
  /// `find` — both ported literally, so an unsorted ladder behaves identically on
  /// both sides. The expectations below were produced by running the TypeScript
  /// functions verbatim over this same out-of-order array; every one of them is
  /// "wrong" against the intent and right against the code.
  @Test("DV-4: an out-of-order ladder behaves exactly as the TypeScript does")
  func unsortedRanks() throws {
    let byID = Dictionary(uniqueKeysWithValues: Golden.pack.ranks.map { ($0.id, $0) })
    let shuffled = try ["t1-senior", "trainee", "t2", "t1"].map { try #require(byID[$0]) }
    #expect(shuffled.map(\.min) == [150, 0, 210, 40])

    let rules = CareerRules(
      ranks: shuffled, kit: Golden.pack.kit, career: Golden.pack.tuning.career)

    // Below every `min` the loop never fires, so the seed — the FIRST element, not
    // the lowest rung — is what comes back.
    #expect(rules.rankFor(-5).id == "t1-senior")
    // The LAST element that matches wins, not the highest one: at ⬢210 every rung
    // matches and `t1` is last in this array.
    #expect(rules.rankFor(0).id == "trainee")
    #expect(rules.rankFor(39).id == "trainee")
    #expect(rules.rankFor(40).id == "t1")
    #expect(rules.rankFor(149).id == "t1")
    #expect(rules.rankFor(150).id == "t1")
    #expect(rules.rankFor(160).id == "t1")
    #expect(rules.rankFor(209).id == "t1")
    #expect(rules.rankFor(210).id == "t1")
    #expect(rules.rankFor(400).id == "t1")

    // `first(where:)` is array order, not the smallest `min` above `standing`.
    #expect(rules.nextRank(-5)?.id == "t1-senior")
    #expect(rules.nextRank(0)?.id == "t1-senior")
    #expect(rules.nextRank(39)?.id == "t1-senior")
    #expect(rules.nextRank(40)?.id == "t1-senior")
    #expect(rules.nextRank(149)?.id == "t1-senior")
    #expect(rules.nextRank(150)?.id == "t2")
    #expect(rules.nextRank(209)?.id == "t2")
    #expect(rules.nextRank(210) == nil)
    #expect(rules.nextRank(400) == nil)

    // The contrast that makes the divergence visible: the shipped ladder is sorted,
    // so the same standings read the way a player expects.
    #expect(Golden.rules.rankFor(210).id == "t2")
    #expect(Golden.rules.rankFor(-5).id == "trainee")
    #expect(Golden.rules.nextRank(0)?.id == "t1")
  }

  /// The exported ladder, rung by rung — the boundaries the hub draws.
  @Test("the shipped ladder reads 0 / 40 / 150 / 210")
  func shippedLadder() {
    #expect(Golden.pack.ranks.map(\.min) == [0, 40, 150, 210])
    #expect(Golden.pack.ranks.map(\.id) == ["trainee", "t1", "t1-senior", "t2"])

    for rank in Golden.pack.ranks {
      #expect(Golden.rules.rankFor(rank.min).id == rank.id)
      #expect((Golden.rules.nextRank(rank.min)?.min ?? Int.max) > rank.min)
    }
    #expect(Golden.rules.rankFor(39).id == "trainee")
    #expect(Golden.rules.nextRank(209)?.id == "t2")
    #expect(Golden.rules.nextRank(210) == nil)
  }
}
