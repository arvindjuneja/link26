import Foundation

/// The three player-controlled switches (§4.1). Not part of the save file: these
/// are launch-critical — the first frame has to know whether the coach draws — so
/// they live in `UserDefaults` alongside the two one-shot gates (§4.3).
///
/// The key type is `SettingKey`, which C5 publishes from `SentryCore` so the
/// reducer can carry a setting change without knowing what storage is.
nonisolated struct SettingsState: Codable, Sendable, Hashable {

  /// The haptics off-switch. **Reduce Motion does not touch this** (D18) — the
  /// heartbeat is a non-visual channel and an accessibility aid, not decoration.
  var haptics: Bool = true
  /// Hold to file. Off swaps in the two-tap confirm, which is also the VoiceOver
  /// path, so the ceremony is never a barrier.
  var holdToFile: Bool = true
  /// The Shift-1 coach marks.
  var coaching: Bool = true

  subscript(key: SettingKey) -> Bool {
    get {
      switch key {
      case .haptics: haptics
      case .holdToFile: holdToFile
      case .coaching: coaching
      }
    }
    set {
      switch key {
      case .haptics: haptics = newValue
      case .holdToFile: holdToFile = newValue
      case .coaching: coaching = newValue
      }
    }
  }
}
