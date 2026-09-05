import Foundation
import SentryCore

/// `UserDefaults` holds **exactly five** launch-critical flags (§4.3) and nothing
/// else. Everything with any weight — the career, the mid-shift snapshot — is a
/// versioned JSON file behind `SaveStore`, because `UserDefaults` gives no atomicity,
/// no backup rotation and no corruption story.
///
/// Reads are synchronous and cheap, which is what lets hydration finish inside
/// `SentrySOCApp.init()` before the first frame.
/// Not `Sendable`: `UserDefaults` is not, and this type has no business crossing an
/// isolation boundary — every caller (`GameModel`, `EffectRunner`) is `@MainActor`.
nonisolated struct Flags {

  enum Key: String, CaseIterable, Sendable {
    /// The disclaimer gate. Set once, by `ACK_FIRSTRUN` — never by a view (G19).
    case firstRun = "sentry.firstRun.v1"
    /// The Shift-1 coach has been through once.
    case onboarding = "sentry.onboarding.v1"
    case haptics = "sentry.haptics"
    case holdToFile = "sentry.holdToFile"
    case coaching = "sentry.coaching"

    /// The three switches are `SentryCore.SettingKey`, exactly — the reducer emits
    /// those raw values and this is where they land. Going through this initialiser
    /// rather than repeating the mapping is what keeps the two rosters from drifting
    /// apart in a way only a player would notice.
    init(_ setting: SettingKey) {
      switch setting {
      case .haptics: self = .haptics
      case .holdToFile: self = .holdToFile
      case .coaching: self = .coaching
      }
    }

    /// The two one-shot gates, which have no `SettingKey` — nobody toggles them.
    static let gates: [Key] = [.firstRun, .onboarding]
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    // The three switches default ON; the two gates default OFF ("not yet seen").
    defaults.register(defaults: [
      Key.haptics.rawValue: true,
      Key.holdToFile.rawValue: true,
      Key.coaching.rawValue: true,
      Key.firstRun.rawValue: false,
      Key.onboarding.rawValue: false,
    ])
  }

  func bool(_ key: Key) -> Bool { defaults.bool(forKey: key.rawValue) }

  func set(_ key: Key, _ value: Bool) { defaults.set(value, forKey: key.rawValue) }

  /// `Effect.setFlag` carries a raw key, so the reducer never imports this file.
  /// An unrecognised key is dropped rather than written: the five are the five.
  func set(rawKey: String, _ value: Bool) {
    guard let key = Key(rawValue: rawKey) else {
      assertionFailure("unknown flag \(rawKey) — UserDefaults holds exactly five keys")
      return
    }
    set(key, value)
  }

  var settings: SettingsState {
    SettingsState(
      haptics: bool(Key(.haptics)), holdToFile: bool(Key(.holdToFile)),
      coaching: bool(Key(.coaching)))
  }

  /// The disclaimer has been acknowledged.
  var hasSeenFirstRun: Bool { bool(.firstRun) }
  /// The coach has run once.
  var hasSeenOnboarding: Bool { bool(.onboarding) }
}
