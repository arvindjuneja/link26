import Foundation
import Testing
import SentryCore

@testable import SentrySOC

/// **P1-3 · §2.3's Dock label rule, all three arms.**
///
/// The third — `Daily shift · <date>` once every campaign board is cleared — was
/// unreachable by construction while "cleared" was derived from the unlock ladder,
/// because that derivation makes the highest unlocked board permanently *open*.
/// `career.clearedShiftIDs` (DV-9) is what makes it a fact, and this is the suite
/// that walks a career up the ladder and reads the CTA at every rung.
@MainActor
@Suite("Hub dock label")
struct HubDockTests {

  private static let pack = ContentPack.bundled
  private static let rules = CareerRules(content: pack)
  private static let today = Date()

  private static var campaign: [ShiftDef] { pack.shifts.filter { $0.kind == .campaign } }

  private static func target(_ career: CareerState, resumable: ShiftState? = nil)
    -> HubView.DockTarget?
  {
    HubView.dockTarget(
      resumable: resumable, career: career, content: pack, rules: rules, today: today)
  }

  /// A career that has cleared the first `count` campaign boards and has the standing
  /// the ladder pays for that many clean shifts — enough to keep the next one open.
  private static func cleared(_ count: Int) -> CareerState {
    let ids = campaign.prefix(count).map(\.id)
    let standing = count < campaign.count ? campaign[count].unlockStanding : campaign.last!.unlockStanding
    return CareerState(standing: standing, clearedShiftIDs: Set(ids))
  }

  // MARK: - The three labels

  @Test("a fresh desk clocks in to the first board")
  func freshDeskClocksIn() throws {
    let target = try #require(Self.target(.initial))
    guard case .clockIn(let shift) = target else {
      Issue.record("a fresh desk should clock in, got \(target)")
      return
    }
    #expect(shift.id == Self.campaign.first?.id)
  }

  @Test("a waiting snapshot outranks every other arm")
  func resumeWins() throws {
    let board = ShiftState(
      shiftId: Self.campaign[0].id, caseIds: Self.campaign[0].caseIds, timeBudget: 90)
    // Even from a career that has cleared everything, the snapshot is the CTA.
    let all = CareerState(
      standing: 999, clearedShiftIDs: Set(Self.campaign.map(\.id)))
    let target = try #require(Self.target(all, resumable: board))
    guard case .resume = target else {
      Issue.record("a waiting snapshot should be the CTA, got \(target)")
      return
    }
  }

  @Test("clearing a board moves the CTA to the next one, not past it")
  func clockInFollowsTheLedger() throws {
    for count in 1..<Self.campaign.count {
      let target = try #require(Self.target(Self.cleared(count)))
      guard case .clockIn(let shift) = target else {
        Issue.record("after \(count) cleared boards the CTA should clock in, got \(target)")
        continue
      }
      #expect(
        shift.id == Self.campaign[count].id,
        "after \(count) cleared the CTA should offer board \(count + 1)")
    }
  }

  /// The arm this whole change exists for.
  @Test("every campaign board cleared reads Daily shift")
  func everyBoardClearedReachesTheDaily() throws {
    let done = CareerState(
      standing: Self.campaign.last?.unlockStanding ?? 0,
      clearedShiftIDs: Set(Self.campaign.map(\.id)))
    let target = try #require(Self.target(done))
    guard case .daily(let shift) = target else {
      Issue.record("a finished campaign should read Daily shift, got \(target)")
      return
    }
    #expect(shift.kind == .daily)
    #expect(shift.id == Self.pack.dailyShift(on: Self.today).id)
    // And the board it offers is actually startable, which is the reason the arm is
    // gated on the whole campaign rather than on "everything I have unlocked".
    #expect(Self.rules.isUnlocked(done, shift))
  }

  /// The fourth arm §2.3 does not name: everything you have opened is cleared, but
  /// the ladder is gated above you. Offering the daily there would be a CTA the
  /// reducer refuses — the daily opens at ⬢ 40 and a rough Shift 1 pays ⬢ 15.
  @Test("a gated ladder offers a replay, never a locked board")
  func gatedLadderOffersAReplay() throws {
    let first = try #require(Self.campaign.first)
    let rough = CareerState(standing: 15, clearedShiftIDs: [first.id])
    // The premise: nothing above is open, and the daily is not either.
    #expect(!Self.rules.isUnlocked(rough, Self.campaign[1]))
    #expect(!Self.rules.isUnlocked(rough, Self.pack.dailyShift(on: Self.today)))

    let target = try #require(Self.target(rough))
    guard case .clockIn(let shift) = target else {
      Issue.record("a gated ladder should offer a replay, got \(target)")
      return
    }
    #expect(shift.id == first.id)
    #expect(Self.rules.isUnlocked(rough, shift), "the CTA offered a board the reducer refuses")
  }

  // MARK: - The ledger the rule reads

  /// End to end through the model: play the first board and the hub's answer changes.
  @Test("a played board is cleared, and the CTA moves on")
  func playingABoardMovesTheCTA() async throws {
    let directory = URL.temporaryDirectory
      .appending(path: "HubDock-\(UUID().uuidString)", directoryHint: .isDirectory)
    let suite = "HubDock-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let model = GameModel(
      save: SaveStore(directory: directory), flags: Flags(defaults: defaults),
      registry: ScreenRegistry())

    let first = try #require(model.content.shifts.first)
    #expect(!model.career.clearedShiftIDs.contains(first.id))

    model.send(.startShift(first.id))
    model.send(.begin)
    model.send(.closeView)
    while let current = model.session.currentCase(model.content) {
      // Every key source, so the board grades CLEAN and pays the ⬢ 40 that opens the
      // next one — a blind run pays ⬢ 15 and lands on the gated-ladder arm instead.
      for source in current.keySourceIds { model.send(.pullSource(source)) }
      model.send(.makeCall(current.correctDisposition))
      model.send(.nextCase)
    }
    model.send(.nextCase)                        // leave the summary

    #expect(model.career.clearedShiftIDs.contains(first.id), "a settled board was not recorded")

    let target = try #require(
      HubView.dockTarget(
        resumable: nil, career: model.career, content: model.content, rules: model.rules,
        today: Self.today))
    guard case .clockIn(let next) = target else {
      Issue.record("the CTA should have moved to the next board, got \(target)")
      return
    }
    #expect(next.id != first.id, "the CTA still offers the board just cleared")
  }
}
