import Foundation

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
      haptics: bool(.haptics), holdToFile: bool(.holdToFile), coaching: bool(.coaching))
  }

  /// The disclaimer has been acknowledged.
  var hasSeenFirstRun: Bool { bool(.firstRun) }
  /// The coach has run once.
  var hasSeenOnboarding: Bool { bool(.onboarding) }
}
