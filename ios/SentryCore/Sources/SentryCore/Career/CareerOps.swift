import Foundation

/// `career/state.ts`, ported function-for-function.
///
/// One identity across the seats. You earn two things, with deliberately different
/// roles: cash (¢) is POWER — earned by completing work, spent on kit; standing (⬢)
/// is ACCESS — earned by doing WELL, never spent, and it moves the ladder.
///
/// Pure and deterministic: no I/O, no clock, no persistence. Every constant is read
/// from the bundle (`ranks`, `kit`, `tuning.career`), so a designer retune is an
/// export and not a build — the only numbers spelled here are the `0` and `1` of the
/// TypeScript's own counters.
public struct CareerRules: Sendable {
  private let ranks: [Rank]
  private let kit: [KitItem]
  private let career: Tuning.CareerTuning

  public init(content: ContentPack) {
    self.init(ranks: content.ranks, kit: content.kit, career: content.tuning.career)
  }

  /// The seam DV-4 needs: the last-match loop can only be told apart from a
  /// `max(by:)` on a deliberately out-of-order `ranks` array, which no export will
  /// ever produce. Not public — the app builds its rules from the bundle.
  init(ranks: [Rank], kit: [KitItem], career: Tuning.CareerTuning) {
    self.ranks = ranks
    self.kit = kit
    self.career = career
  }

  // ── Rank (derived from standing) ───────────────────────────────────────────

  /// The rung you hold at `standing`.
  ///
  /// **DV-4.** This is `state.ts`'s ascending last-match loop ported *as written*,
  /// not as intended: it seeds with the FIRST element and keeps the LAST element
  /// that matches, so an unsorted ladder behaves identically on both sides — a
  /// standing below every `min` returns `ranks[0]`, and a standing above several
  /// `min`s returns the last of them in array order, not the highest. The exported
  /// ladder is sorted, so on the shipped bundle this is simply "your rank".
  public func rankFor(_ standing: Int) -> Rank {
    guard var result = ranks.first else {
      fatalError("content.json carries no ranks — the ladder cannot be resolved")
    }
    for rank in ranks {
      if standing >= rank.min { result = rank }
    }
    return result
  }

  /// The rung above you, or `nil` when the ladder is topped out.
  ///
  /// **DV-4.** `first(where:)` in array order — the first `min` strictly above
  /// `standing`, not the smallest one.
  public func nextRank(_ standing: Int) -> Rank? {
    ranks.first(where: { $0.min > standing })
  }

  // ── Analyst-kit shop (the cash sink — earn → spend → be faster) ─────────────

  public func owns(_ c: CareerState, _ gearId: String) -> Bool {
    c.gear.contains(gearId)
  }

  /// Spend for gear. A purchase you cannot afford, or already own, is a no-op that
  /// returns the career untouched — the caller never has to pre-check.
  public func buyKit(_ c: CareerState, _ item: KitItem) -> CareerState {
    if owns(c, item.id) || c.cash < item.cost { return c }
    var next = c
    next.cash -= item.cost
    next.gear.append(item.id)
    return next
  }

  /// The kit item behind an id, from the bundle's catalogue. Internal: the shop
  /// screen holds the item it is drawing, and the inbox's kit tip is the only
  /// caller that starts from an id.
  func kitItem(_ id: String) -> KitItem? {
    kit.first(where: { $0.id == id })
  }

  // ── Earning ────────────────────────────────────────────────────────────────

  /// Fold a completed shift's score into the career.
  ///
  /// Cash comes from completing work — per correct call, plus a clean-shift bonus,
  /// which is what makes an easy board still worth running. Standing comes from
  /// doing well: a clean shift moves the rank, a rough or breached one barely does.
  public func awardForShift(_ c: CareerState, _ score: ShiftScore) -> ShiftReward {
    let cashGain =
      score.verdictCorrect * career.cashPerCorrect + (score.grade == .clean ? career.cleanBonus : 0)
    let standingGain: Int
    switch score.grade {
    case .clean: standingGain = career.standingClean
    case .rough: standingGain = career.standingRough
    case .breached: standingGain = career.standingBreached
    }

    var state = c
    state.cash += cashGain
    state.standing += standingGain
    state.shiftsCleaned += (score.grade == .clean ? 1 : 0)

    let rankUp =
      rankFor(state.standing).id != rankFor(c.standing).id ? rankFor(state.standing) : nil
    return ShiftReward(
      state: state, cashGain: cashGain, standingGain: standingGain, rankUp: rankUp)
  }

  /// Credit the shared wallet for a completed red-seat run: your personal cut plus
  /// one run on record. Kept because the career state is shared across both seats —
  /// this build never calls it (there is no red seat here, B1), and the fixtures
  /// still pin it so the two implementations cannot drift apart.
  public func awardRedRun(_ c: CareerState, cut: Int? = nil) -> CareerState {
    var next = c
    next.cash += cut ?? career.redRunCut
    next.redRunsDone += 1
    return next
  }

  // ── Unlock gating (the gate lives on the shift) ─────────────────────────────

  /// Whether a board is open to you. Standing is the only gate that can fail on
  /// this build: the export sets `requiresRedRun: false` on every shift (B1).
  public func isUnlocked(_ c: CareerState, _ shift: ShiftDef) -> Bool {
    if c.standing < shift.unlockStanding { return false }
    if shift.requiresRedRun && c.redRunsDone < 1 { return false }
    return true
  }
}
