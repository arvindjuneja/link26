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

  public init(
    cash: Int = 0, standing: Int = 0, shiftsCleaned: Int = 0,
    redRunsDone: Int = 0, gear: [String] = [], dailyDoneOn: String? = nil
  ) {
    self.cash = cash
    self.standing = standing
    self.shiftsCleaned = shiftsCleaned
    self.redRunsDone = redRunsDone
    self.gear = gear
    self.dailyDoneOn = dailyDoneOn
  }

  /// A fresh career — `INITIAL_CAREER` in `career/state.ts`.
  public static let initial = CareerState()
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
