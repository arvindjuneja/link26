import Foundation
import Testing

@testable import SentryCore

/// Shared handles and a tiny driver for the session suites.
///
/// The reducer is pure, so a "playthrough" is just a fold: hand it the state, take
/// the state back, and keep the effects it asked for. `Deck.Run` is that fold with
/// the one thing a fold cannot do on its own — applying the settlement to the
/// career, exactly as `GameModel` does — so a test can play a whole board and then
/// ask what the career became.
enum Deck {
  static let pack = ContentPack.bundled
  static let engine = SOCEngine(content: pack)
  static let rules = CareerRules(content: pack)
  static let tuning = ContentPack.bundled.tuning

  /// A fixed clock. `daily.json`'s horizon opens on this day, so `dailyShift(on:)`
  /// resolves to the first exported board and nothing depends on when the suite runs.
  static let today = DailyCalendar.date(fromISO: "2026-09-05") ?? Date(timeIntervalSince1970: 0)
  static let tomorrow = today.addingTimeInterval(24 * 60 * 60)

  static var firstShift: ShiftDef { pack.shifts[0] }
  static var dailyShift: ShiftDef { pack.dailyShift(on: today) }

  /// The career that opens every board — enough standing for the daily row (40) but
  /// nothing bought.
  static let workingCareer = CareerState(cash: 0, standing: 40, shiftsCleaned: 1)

  static func socCase(_ id: String) -> SocCase {
    guard let c = pack.case(id) else {
      fatalError("content.json has no case \(id) — the fixture ids moved")
    }
    return c
  }

  /// One player, one machine, one clock.
  struct Run {
    var state: SessionState = .atHub
    var career: CareerState = .initial
    var now: Date = Deck.today
    /// Every effect the reducer has asked for, in order.
    private(set) var log: [Effect] = []

    init(career: CareerState = .initial, state: SessionState = .atHub, now: Date = Deck.today) {
      self.career = career
      self.state = state
      self.now = now
    }

    /// Send one action. Returns just the effects that action produced.
    @discardableResult
    mutating func send(_ action: SocAction) -> [Effect] {
      let (next, effects) = reduce(state, action, content: Deck.pack, career: career, now: now)
      state = next
      log += effects
      // What `EffectRunner` + `GameModel` do with the two effects that move the
      // career, and nothing else: the test is about the reducer, not the runner.
      for effect in effects {
        switch effect {
        case .settleShift:
          if let settlement = next.settlement { career = settlement.reward.state }
        case .markDailyDone(let day):
          career.dailyDoneOn = day
        default:
          break
        }
      }
      return effects
    }

    /// Open the board and walk to the first case.
    mutating func startAndBegin(_ shiftID: String) {
      send(.startShift(shiftID))
      send(.begin)
      send(.closeView)                                   // the board auto-opens once
    }

    /// File the ideal call on every remaining alert and stop on the summary.
    mutating func playToCompletion(ideal: Bool = true) {
      while let current = state.currentCase(Deck.pack) {
        let disposition = ideal ? current.correctDisposition : Deck.wrongCall(for: current)
        send(.makeCall(disposition))
        send(.nextCase)
      }
    }

    var effects: [Effect] { log }
  }

  /// A call that is wrong on purpose: closing a true positive is the miss that
  /// costs 30 breach, and escalating anything else is the noise.
  static func wrongCall(for c: SocCase) -> Disposition {
    c.truth == .truePositive ? .closeFalsePositive : .escalateIRIsolate
  }
}

/// Float equality after a subtraction is a coin toss — `0.30 - 0.10` is not
/// `Float(0.20)` — and a haptic parameter is meaningful to about three decimal
/// places, not to the last bit. Every derived intensity and sharpness is therefore
/// compared with a tolerance; every *authored* one is compared exactly.
func isClose(_ actual: Float?, _ expected: Float, tolerance: Float = 1e-5) -> Bool {
  guard let actual else { return false }
  return abs(actual - expected) <= tolerance
}

func isClose(_ actual: TimeInterval?, _ expected: TimeInterval, tolerance: TimeInterval = 1e-9)
  -> Bool
{
  guard let actual else { return false }
  return abs(actual - expected) <= tolerance
}

extension Effect {
  /// `.haptic(.select)` → `.select`, for asserting cue order without the wrapper.
  var cue: SocCue? { if case .haptic(let cue) = self { cue } else { nil } }
}
