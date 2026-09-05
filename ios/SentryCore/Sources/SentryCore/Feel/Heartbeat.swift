import Foundation

/// The looping heartbeat, from the pure scheduler (`DESIGN.md` §2.15).
///
/// A *description* of a loop, not a player: `periodMs` is the loop length and each
/// beat is an offset inside it. C10 turns this into a `CHHapticAdvancedPatternPlayer`
/// with `loopEnabled = true`; `SessionTests` reads the numbers without a device.
public struct HeartbeatPlan: Sendable, Hashable, Codable {

  /// One thump inside the loop.
  public struct Beat: Sendable, Hashable, Codable {
    /// Offset from the top of the loop.
    public let atMs: Int
    public let intensity: Float
    public let sharpness: Float

    public init(atMs: Int, intensity: Float, sharpness: Float) {
      self.atMs = atMs
      self.intensity = intensity
      self.sharpness = sharpness
    }
  }

  /// Which band is beating. LOCKDOWN is *sharper* as well as faster — dread, not
  /// volume (§4.4).
  public let status: TraceStatus
  public let periodMs: Int
  /// The lub, then the dub.
  public let beats: [Beat]
  /// Stop beating after this much continuous play (§2.15 guard 2). A player reading
  /// a 566-character `why` is never buzzed for minutes.
  public let autoSuspendMs: Int

  public init(status: TraceStatus, periodMs: Int, beats: [Beat], autoSuspendMs: Int) {
    self.status = status
    self.periodMs = periodMs
    self.beats = beats
    self.autoSuspendMs = autoSuspendMs
  }

  public var lub: Beat? { beats.first }
  public var dub: Beat? { beats.count > 1 ? beats[1] : nil }
}

/// The plan for a status, or `nil` — **silence is the reward** (§2.15).
///
/// Every number comes from `tuning` (D7): the period is `60000 / bpm[status]`
/// rounded (`SocConsole.tsx:210` rounds, so 112 bpm is 536 ms and not 535), floored
/// at `tuning.heartbeat.minPeriodMs` so no band can buzz faster than 2.5 Hz, and the
/// dub sits `tuning.heartbeat.dubOffsetMs` after the lub.
///
/// The intensities are the §4.4 table: HUNT 0.75 / 0.30, LOCKDOWN 1.00 / 0.55, with
/// the dub at 55 % of the lub's intensity and a tenth off its sharpness.
public func heartbeatPlan(status: TraceStatus, tuning: Tuning) -> HeartbeatPlan? {
  guard let lub = HeartbeatFeel.lub(for: status) else { return nil }
  let bpm = max(tuning.bpm[status], 1)
  let period = max(
    Int((60_000.0 / Double(bpm)).rounded()), tuning.heartbeat.minPeriodMs)
  let dub = HeartbeatPlan.Beat(
    atMs: tuning.heartbeat.dubOffsetMs,
    intensity: lub.intensity * HeartbeatFeel.dubIntensityScale,
    sharpness: max(0, lub.sharpness - HeartbeatFeel.dubSharpnessDrop))
  return HeartbeatPlan(
    status: status, periodMs: period, beats: [lub, dub],
    autoSuspendMs: tuning.heartbeat.autoSuspendMs)
}

/// The four numbers the §4.4 table holds that `tuning` does not: how hard the two
/// beating bands hit, and how the dub relates to the lub.
///
/// They are *feel*, not balance — a designer retuning the game never touches them,
/// and a device session might. They live here rather than in `tuning.json` for the
/// same reason the curve control points do: they describe a waveform, not an economy.
public enum HeartbeatFeel {
  public static let huntIntensity: Float = 0.75
  public static let huntSharpness: Float = 0.30
  public static let lockdownIntensity: Float = 1.00
  public static let lockdownSharpness: Float = 0.55
  public static let dubIntensityScale: Float = 0.55
  public static let dubSharpnessDrop: Float = 0.10
  /// The lub is a 90 ms continuous event, not a tap — that is what makes it a
  /// thump instead of a click (§4.4).
  public static let lubDurationSeconds: TimeInterval = 0.09
  /// The attack of the intensity curve. Fast enough to read as a heartbeat.
  public static let lubAttackSeconds: TimeInterval = 0.018

  /// `nil` at CALM and ALERT.
  public static func lub(for status: TraceStatus) -> HeartbeatPlan.Beat? {
    switch status {
    case .calm, .alert: nil
    case .hunt: HeartbeatPlan.Beat(atMs: 0, intensity: huntIntensity, sharpness: huntSharpness)
    case .lockdown:
      HeartbeatPlan.Beat(atMs: 0, intensity: lockdownIntensity, sharpness: lockdownSharpness)
    }
  }
}

/// The guards around the loop, as a value you can step through in a test (§2.15's
/// "all in the pure scheduler so they are testable").
///
/// C10 owns the clock and the player; this owns the rules: HUNT/LOCKDOWN only ·
/// `phase == .investigating` only · the settings toggle · 40 s auto-suspend, re-armed
/// by a status change, by re-entering the case screen, or by the next `PULL_SOURCE`.
/// Backgrounding is the app's job (`scenePhase`), because a value type has no way to
/// notice it.
public struct HeartbeatDirector: Sendable, Hashable {
  public let tuning: Tuning
  /// When the current run was armed, on whatever monotonic millisecond clock the
  /// caller uses.
  public private(set) var armedAtMs: Int
  public private(set) var status: TraceStatus
  public private(set) var phase: Phase

  public init(
    tuning: Tuning, nowMs: Int = 0, status: TraceStatus = .calm, phase: Phase = .hub
  ) {
    self.tuning = tuning
    self.armedAtMs = nowMs
    self.status = status
    self.phase = phase
  }

  /// What should be playing now, or `nil` for silence.
  ///
  /// Re-arms itself on a status change and on entering `.investigating`, which is
  /// why it is `mutating`: the suspend window belongs to a *run* of one status, not
  /// to the app's lifetime.
  public mutating func update(
    status: TraceStatus, phase: Phase, hapticsEnabled: Bool, nowMs: Int
  ) -> HeartbeatPlan? {
    let entered = phase == .investigating && self.phase != .investigating
    if status != self.status || entered { armedAtMs = nowMs }
    self.status = status
    self.phase = phase

    guard phase == .investigating, hapticsEnabled, !isSuspended(nowMs: nowMs) else { return nil }
    return heartbeatPlan(status: status, tuning: tuning)
  }

  /// A pull re-arms the loop (§2.15 guard 2) — the player is working again.
  public mutating func pulledSource(nowMs: Int) {
    armedAtMs = nowMs
  }

  /// The 40 s wall. Reached, the loop goes quiet until something re-arms it.
  public func isSuspended(nowMs: Int) -> Bool {
    nowMs - armedAtMs >= tuning.heartbeat.autoSuspendMs
  }
}
