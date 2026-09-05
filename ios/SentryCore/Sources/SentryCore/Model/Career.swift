import Foundation

/// One identity across the seats. Decodes 1:1 from the fixtures' `CareerJSON`.
///
/// Cash (¢) is power — earned by completing work, spent on kit. Standing (⬢) is
/// access — earned by doing well, never spent.
public struct CareerState: Codable, Sendable, Hashable {
  public var cash: Int
  public var standing: Int
  public var shiftsCleaned: Int
  /// Red-seat runs completed. Always 0 on the blue-only iOS build.
  public var redRunsDone: Int
  /// Owned analyst-kit ids.
  public var gear: [String]
  /// The ISO day the daily board last paid standing (DESIGN §4.2 / Appendix A G7).
  /// **DV-6:** not in the exported `CareerJSON` — it is a client-side hook, absent
  /// from every fixture, and `encodeIfPresent` keeps it out of a round-trip that
  /// never set it.
  public var dailyDoneOn: String?

  /// The **campaign** boards this career has finished, by shift id.
  ///
  /// **DV-9 (iOS only, P1-3).** Not in the exported `CareerJSON` and absent from every
  /// fixture, like `dailyDoneOn` — the web tracks nothing per board. It exists because
  /// the hub was *deriving* "cleared" from the unlock ladder ("every board below the
  /// highest one you have opened was paid for"), which is sound but not true: it calls
  /// a board you never played cleared the moment standing opens the next one, and it
  /// makes the highest board permanently "open", so §2.3's third Dock label ("Daily
  /// shift · <date>" once every campaign board is cleared) was unreachable by
  /// construction. A recorded set is exact.
  ///
  /// Daily boards are deliberately **not** recorded: their ids carry a date
  /// (`daily-2026-09-05`), so a year of play would put 365 dead strings in the save,
  /// and the daily's own "done today" state is already `dailyDoneOn`.
  ///
  /// Written in exactly one place — `settlement(for:career:content:now:)` at 16:00.
  public var clearedShiftIDs: Set<String>

  public init(
    cash: Int = 0, standing: Int = 0, shiftsCleaned: Int = 0,
    redRunsDone: Int = 0, gear: [String] = [], dailyDoneOn: String? = nil,
    clearedShiftIDs: Set<String> = []
  ) {
    self.cash = cash
    self.standing = standing
    self.shiftsCleaned = shiftsCleaned
    self.redRunsDone = redRunsDone
    self.gear = gear
    self.dailyDoneOn = dailyDoneOn
    self.clearedShiftIDs = clearedShiftIDs
  }

  /// A fresh career — `INITIAL_CAREER` in `career/state.ts`.
  public static let initial = CareerState()

  // MARK: - Codable

  /// Hand-written for one reason: **the two client-side fields must be optional on
  /// the way in.** Every `CareerJSON` fixture carries the five web fields and neither
  /// `dailyDoneOn` nor `clearedShiftIDs`, so synthesised decoding of a non-optional
  /// `Set<String>` would fail on all of them. `decodeIfPresent` with a default is the
  /// same lenience `loadCareer`'s object spread gives the web, and it is what lets a
  /// save written before this build still load.
  ///
  /// On the way out an empty set is omitted, so a career that never cleared a board
  /// round-trips to the same bytes it decoded from.
  private enum CodingKeys: String, CodingKey {
    case cash, standing, shiftsCleaned, redRunsDone, gear, dailyDoneOn, clearedShiftIDs
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let initial = CareerState.initial
    cash = try container.decodeIfPresent(Int.self, forKey: .cash) ?? initial.cash
    standing = try container.decodeIfPresent(Int.self, forKey: .standing) ?? initial.standing
    shiftsCleaned =
      try container.decodeIfPresent(Int.self, forKey: .shiftsCleaned) ?? initial.shiftsCleaned
    redRunsDone =
      try container.decodeIfPresent(Int.self, forKey: .redRunsDone) ?? initial.redRunsDone
    gear = try container.decodeIfPresent([String].self, forKey: .gear) ?? initial.gear
    dailyDoneOn = try container.decodeIfPresent(String.self, forKey: .dailyDoneOn)
    clearedShiftIDs =
      try container.decodeIfPresent(Set<String>.self, forKey: .clearedShiftIDs) ?? []
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(cash, forKey: .cash)
    try container.encode(standing, forKey: .standing)
    try container.encode(shiftsCleaned, forKey: .shiftsCleaned)
    try container.encode(redRunsDone, forKey: .redRunsDone)
    try container.encode(gear, forKey: .gear)
    try container.encodeIfPresent(dailyDoneOn, forKey: .dailyDoneOn)
    if !clearedShiftIDs.isEmpty {
      // Sorted: a `Set` has no order, and an unordered array in a save file makes
      // every write a spurious diff.
      try container.encode(clearedShiftIDs.sorted(), forKey: .clearedShiftIDs)
    }
  }
}

/// A rung on the ladder. `min` is the standing at or above which it is held.
public struct Rank: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let label: String
  public let min: Int

  public init(id: String, label: String, min: Int) {
    self.id = id
    self.label = label
    self.min = min
  }
}

/// The cash sink — earn, spend, be faster.
public struct KitItem: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let label: String
  public let cost: Int
  public let blurb: String

  public init(id: String, label: String, cost: Int, blurb: String) {
    self.id = id
    self.label = label
    self.cost = cost
    self.blurb = blurb
  }
}

/// A completed shift folded into the career. Decodes 1:1 from `ShiftRewardJSON`.
public struct ShiftReward: Codable, Sendable, Hashable {
  public let state: CareerState
  public let cashGain: Int
  public let standingGain: Int
  /// The new rank if this shift ranked you up, else `nil`.
  public let rankUp: Rank?

  public init(state: CareerState, cashGain: Int, standingGain: Int, rankUp: Rank?) {
    self.state = state
    self.cashGain = cashGain
    self.standingGain = standingGain
    self.rankUp = rankUp
  }
}

/// Which seats this build exposes. iOS ships blue-only, so `tip-redrun` is
/// suppressed from the inbox and no shift can require a red run (B1/S3).
public struct SocFeatures: Codable, Sendable, Hashable {
  public var redSeat: Bool

  public init(redSeat: Bool) { self.redSeat = redSeat }

  /// The web's feature set — both seats.
  public static let all = SocFeatures(redSeat: true)
  /// This app's feature set.
  public static let iOS = SocFeatures(redSeat: false)
}
