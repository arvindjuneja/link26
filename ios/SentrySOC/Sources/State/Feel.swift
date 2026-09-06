import Foundation
import SwiftUI
import SentryCore

/// **The sound switches, and the one flag that mutes a replay** (F2a, `FEEL.md` §9).
///
/// Settings gains two rows: **Sound**, default on, and **Heartbeat sound**, default
/// off. They live here rather than in `SettingsState` / `SettingKey`, and that is a
/// deliberate divergence from the obvious symmetry — §4.3 pins `UserDefaults` at
/// **exactly five** launch-critical flags and `Flags.set(rawKey:)` trips an
/// `assertionFailure` on a sixth. Two more `SettingKey` cases would mean editing the
/// reducer's action vocabulary, `Flags`, `SettingsState` and every count that names
/// the five — for two switches the reducer has no opinion about. The reducer decides
/// what the *game* does; whether the desk makes a noise is not that.
///
/// So: same shape, own keys, own store, one owner. `SoundService` reads it,
/// `SettingsView` binds to it, and nothing else writes it.
///
/// **`replayMuted`** is the sound half of `GameModel.cuesAreLive`. A QA jump reaches
/// its screen by *playing* the board through the reducer — start, begin, pull, call,
/// next — and every one of those transitions fires its cue. Muted for haptics since
/// P1-8; muted for sound here, or `-SentryQAScreen summary` would fire a dozen ticks,
/// a file thud and a verdict chord into a screenshot run in under a second.
@Observable @MainActor final class Feel {

  /// The app's one instance. A second would be a second view of the same defaults.
  static let shared = Feel()

  /// The two keys, which are also their `UserDefaults` names — the same convention
  /// `SettingKey` uses for the five it owns.
  enum Key: String, CaseIterable, Sendable {
    /// Cues and the room tone. On by default (§9) — `.ambient` means the ringer
    /// switch is still the player's last word.
    case sound = "sentry.sound"
    /// A low thump under the heartbeat haptic. **Off by default** (§9): the beat is
    /// a haptic channel first, and hearing it as well is a different game.
    case heartbeatSound = "sentry.heartbeatSound"

    var defaultValue: Bool {
      switch self {
      case .sound: true
      case .heartbeatSound: false
      }
    }
  }

  private(set) var sound: Bool
  private(set) var heartbeatSound: Bool

  /// True only while a QA jump is replaying its action list. Not persisted — it
  /// belongs to a fast-forward, not to a player.
  var replayMuted = false

  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(
      defaults: Dictionary(
        uniqueKeysWithValues: Key.allCases.map { ($0.rawValue, $0.defaultValue) }))
    self.sound = defaults.bool(forKey: Key.sound.rawValue)
    self.heartbeatSound = defaults.bool(forKey: Key.heartbeatSound.rawValue)
  }

  subscript(key: Key) -> Bool {
    switch key {
    case .sound: sound
    case .heartbeatSound: heartbeatSound
    }
  }

  /// Move a switch: the observed property, the store, and — for `sound` — the tone
  /// that has to stop *now* rather than at the next phase change, because that is
  /// what a player expects of a switch.
  ///
  /// Written as one method rather than as `didSet` observers: `@Observable` rewrites
  /// a stored property into a computed one, and hanging a property observer off that
  /// is a rule the macro does not owe anybody. One entry point is clearer anyway —
  /// the same reason `GameModel.send(_:)` exists.
  func set(_ key: Key, _ value: Bool) {
    guard self[key] != value else { return }
    switch key {
    case .sound: sound = value
    case .heartbeatSound: heartbeatSound = value
    }
    defaults.set(value, forKey: key.rawValue)
    // Both switches take effect **now**, which is the whole difference between a
    // switch and a preference: `sound` stops or restarts the room tone, and
    // `heartbeatSound` stops or starts the thump under a heartbeat that is already
    // buzzing rather than waiting for the next band change.
    switch key {
    case .sound: SoundService.shared.soundSettingChanged()
    case .heartbeatSound: SoundService.shared.heartbeatSoundSettingChanged()
    }
  }

  /// A SwiftUI `Toggle` binds to this, so even a switch goes through `set(_:_:)` —
  /// the same shape as `GameModel.settingBinding(_:)` for the five the reducer owns.
  func binding(_ key: Key) -> Binding<Bool> {
    Binding(
      get: { [weak self] in self?[key] ?? key.defaultValue },
      set: { [weak self] value in self?.set(key, value) })
  }
}
