import CoreHaptics
import Foundation
import OSLog
import SentryCore

/// Where every cue in the game comes out (§4.4, D17, D18).
///
/// One sink, installed into `ScreenRegistry` by `HapticsComposition`, so a view can
/// never reach Core Haptics and `EffectRunner` stays the only thing that decides
/// *when*. Three routes leave this class and there is never a fourth:
///
/// - `file`, `breachThud`, `rankup` → a bespoke `CHHapticPattern` from
///   `SentryCore.CHPatternSpec`, because `.sensoryFeedback` cannot express them;
/// - `heartbeat(_:)` → `HeartbeatPlayer`, a single looping advanced player;
/// - the other twelve → `.sensoryFeedback`, which needs no engine warm-up and keeps
///   working after Core Haptics has auto-shut-down. `HapticsComposition` wraps the
///   screen factories so a host for it is mounted on every screen the app draws.
///
/// **Reduce Motion does not disable haptics** — a deliberate divergence from
/// `DESIGN.md` §2.15, ruled as **D18**. Reduce Motion is a vestibular setting; the
/// heartbeat is a non-visual channel and an accessibility *aid* for a player who
/// cannot track a sweeping meter. The Settings toggle (checked by `EffectRunner` and
/// `GameModel.feel`) is the off-switch, and `supportsHaptics` is the hardware gate.
///
/// Every call is gated on `capabilitiesForHardware().supportsHaptics`, which is
/// **false on the Simulator** — so the whole file is a silent no-op there rather
/// than a crash (X7). That is also why nothing below is verified by running the app:
/// the waveforms are pure values in `SentryCore/Feel/` and are asserted by
/// `SessionTests/HapticPatternTests` on macOS.
@MainActor final class HapticsEngine: HapticsSink {

  /// The app's one engine. A second `CHHapticEngine` would mean a second audio
  /// session client and two loops fighting over the same actuator.
  static let shared = HapticsEngine()

  /// Read once. `false` on the Simulator and on hardware without a Taptic Engine.
  static let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

  /// The `.sensoryFeedback` side of the sink. `HapticsComposition` mounts a host for
  /// it on every screen, by wrapping C8's and C9's factories in `.sentryHaptics()`.
  let sensory: SensoryRelay

  private let tuning: Tuning
  /// Readable by `SentryHeartbeatDriver`, which is the only other thing in this
  /// module with something worth saying under `-hapticTrace`.
  let trace: HapticTrace

  /// The ear's half of the **heartbeat** (F2a). Not the ear's half of everything:
  /// individual cues reach the sound service from `GameModel.feel(_:)` and
  /// `EffectRunner`, one call site each, and this class never sees them.
  ///
  /// The loop is the exception, and it has to be: it is a *state*, not a cue, and
  /// `setHeartbeat(_:)` below is the only place in the app that knows which band is
  /// beating and when it stops. Injected the way `EffectRunner` and `GameModel`
  /// inject it, so the fan-out is a dependency rather than a singleton reached for
  /// from inside a method.
  private let ear: SoundService

  /// Lazy on purpose: constructing a `CHHapticEngine` opens an audio session, and a
  /// player who never reaches HUNT and never files a call should never pay for one.
  private var engine: CHHapticEngine?
  private var isRunning = false
  /// Set after the engine has failed to come up repeatedly. Without it a broken
  /// audio session turns every cue into another failed `start()`.
  private var isUnavailable = false
  private var consecutiveFailures = 0
  private static let failureLimit = 3

  private lazy var heartbeatPlayer = HeartbeatPlayer(
    tuning: tuning, trace: trace,
    startedEngine: { [weak self] in self?.startedEngine() })

  /// What decides *whether* the loop should be running. Lazy for the same reason the
  /// engine is: a launch that never reaches a screen never registers an observation.
  private lazy var heartbeatDriver = HeartbeatDriver(
    tuning: tuning, trace: trace,
    setPlan: { [weak self] plan in self?.setHeartbeat(plan) },
    rearmPlayer: { [weak self] in self?.rearmHeartbeat() })

  private static let log = Logger(subsystem: "pl.oumm.sentry.soc", category: "Haptics")

  init(
    tuning: Tuning = ContentPack.bundled.tuning,
    arguments: [String] = ProcessInfo.processInfo.arguments,
    ear: SoundService = .shared
  ) {
    self.tuning = tuning
    self.trace = HapticTrace(arguments: arguments)
    self.sensory = SensoryRelay(trace: trace)
    self.ear = ear
  }

  var isTracing: Bool { trace.isEnabled }

  /// Point the heartbeat driver at the live model (`sentryHaptics`, called from every
  /// screen `HapticsComposition` wraps). Idempotent, and a pointer compare for the
  /// model it is already watching.
  ///
  /// This is the one thing the service cannot get for itself: `HapticsSink` is the
  /// two-method contract C6 froze and neither method carries the session, so somebody
  /// with a `GameModel` in hand has to hand it over once.
  func attach(_ model: GameModel) {
    heartbeatDriver.attach(model)
  }

  // MARK: - HapticsSink

  func play(_ cue: SocCue) {
    switch cue {
    case .heartbeat(let status):
      // The loop belongs to `setHeartbeat(_:)`. A `heartbeat` arriving here is a
      // one-shot request — the QA cue list, a preview — so it plays a single beat of
      // that band and does not disturb whatever is looping.
      trace.cue(cue, route: "pattern")
      guard let pattern = CHPatternSpec.heartbeat(status, tuning) else { return }
      play(pattern)

    default:
      if let pattern = CHPatternSpec.pattern(for: cue) {
        trace.cue(cue, route: "pattern")
        play(pattern)
      } else if cue.isSoundOnly {
        // Heard, never felt (F2a, `FEEL.md` §9's `—` rows). It still traces: "did
        // that cue fire, once, at the right moment?" is the question `-hapticTrace`
        // answers, and a cue the hand skips is one the ear did not.
        trace.cue(cue, route: "soundOnly")
      } else {
        trace.cue(cue, route: sensory.isHosted ? "sensoryFeedback" : "feedbackGenerator")
        let expressed = sensory.fire(cue)
        assert(expressed, "\(cue.name) has neither a pattern nor a sensory route")
      }
    }
  }

  /// `nil` is silence. Every guard that produces that `nil` — HUNT/LOCKDOWN only,
  /// `phase == .investigating` only, the 400 ms floor, the Settings toggle — lives in
  /// `SentryCore`'s pure `heartbeatPlan` / `HeartbeatDirector`, and the 40 s
  /// auto-suspend lives in `HeartbeatPlayer`. `GameModel.scenePhaseChanged` sends
  /// `nil` here when the app leaves the foreground (§4.4: never beat backgrounded).
  /// Both channels, from one plan (F2a). The hand gets a looping advanced player the
  /// OS schedules; the ear gets the same plan as a list of thumps it walks, gated by
  /// the **Heartbeat sound** switch of §9. Armed here rather than anywhere else so
  /// the buzz and the thump can never be beating different bands.
  func setHeartbeat(_ plan: HeartbeatPlan?) {
    heartbeatPlayer.set(plan)
    ear.setHeartbeat(plan)
  }

  /// A `PULL_SOURCE` re-arms the 40-second wall (§2.15 guard 2). Not part of
  /// `HapticsSink`: the sink's two methods are the contract C6 froze, and this is an
  /// extra a driver can reach for through the concrete type.
  func rearmHeartbeat() {
    heartbeatPlayer.rearm()
    ear.rearmHeartbeat()
  }

  // MARK: - Patterns

  private func play(_ pattern: HapticPattern) {
    guard let engine = startedEngine() else { return }
    do {
      let player = try engine.makePlayer(with: CHPatterns.pattern(pattern))
      try player.start(atTime: CHHapticTimeImmediate)
    } catch {
      Self.log.error("pattern did not play: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Engine lifecycle

  /// A started engine, or `nil` — the single gate the rest of the file goes through.
  ///
  /// `isAutoShutdownEnabled` means the engine stops itself when idle and has to be
  /// restarted before the next play; `isRunning` tracks that, kept honest by
  /// `stoppedHandler`, so the common path is one boolean rather than a `start()`
  /// call per cue.
  private func startedEngine() -> CHHapticEngine? {
    guard Self.supportsHaptics, !isUnavailable else { return nil }

    let engine: CHHapticEngine
    if let existing = self.engine {
      engine = existing
    } else {
      do {
        engine = try CHHapticEngine()
      } catch {
        noteFailure("engine could not be created: \(error.localizedDescription)")
        return nil
      }
      // Haptics only. This used to read "no audio in v1"; F2a gave the game a sound
      // bank, and the flag matters MORE now rather than less — the audio belongs to
      // `SoundService`'s `AVAudioEngine` on an `.ambient` session, and a Core
      // Haptics engine that also claims audio would be a second client fighting it
      // for the same session.
      engine.playsHapticsOnly = true
      engine.isAutoShutdownEnabled = true
      engine.resetHandler = { [weak self] in
        Task { @MainActor in self?.engineWasReset() }
      }
      engine.stoppedHandler = { [weak self] reason in
        Task { @MainActor in self?.engineStopped(reason) }
      }
      self.engine = engine
      isRunning = false
    }

    if !isRunning {
      do {
        try engine.start()
        isRunning = true
        consecutiveFailures = 0
      } catch {
        noteFailure("engine could not start: \(error.localizedDescription)")
        return nil
      }
    }
    return engine
  }

  /// The server restarted and every player built from this engine is now invalid —
  /// Apple's documented contract for `resetHandler`. Rebuilding the loop is the
  /// whole response.
  private func engineWasReset() {
    isRunning = false
    trace.note("engine reset")
    heartbeatPlayer.engineDidStop()
  }

  private func engineStopped(_ reason: CHHapticEngine.StoppedReason) {
    isRunning = false
    trace.note("engine stopped (\(reason.rawValue))")
    // Backgrounding is not a fault: `GameModel.scenePhaseChanged` is already sending
    // `setHeartbeat(nil)`, and restarting here would race it into beating a
    // suspended app.
    guard reason != .applicationSuspended else { return }
    heartbeatPlayer.engineDidStop()
  }

  private func noteFailure(_ message: String) {
    engine = nil
    isRunning = false
    consecutiveFailures += 1
    Self.log.error("\(message, privacy: .public)")
    if consecutiveFailures >= Self.failureLimit {
      isUnavailable = true
      Self.log.error("haptics disabled for this launch after \(Self.failureLimit) failures")
      trace.note("haptics unavailable")
    }
  }
}

/// `-hapticTrace`: every cue, with a timestamp (§10 C10 #6).
///
/// The Simulator has no actuator, so "did that cue fire, once, at the right moment?"
/// is otherwise unanswerable before a device. The trace answers it. It writes to
/// both `stdout` (visible under `simctl launch --console`) and the unified log
/// (readable with `log stream` during the founder's device pass, §7 step 5).
///
/// Off unless the launch argument is present, so it costs one `Bool` in a normal run.
struct HapticTrace: Sendable {

  static let launchArgument = "-hapticTrace"

  let isEnabled: Bool
  private let launchedAt: Date

  private static let log = Logger(subsystem: "pl.oumm.sentry.soc", category: "HapticTrace")

  init(arguments: [String] = ProcessInfo.processInfo.arguments, launchedAt: Date = Date()) {
    self.isEnabled = arguments.contains(Self.launchArgument)
    self.launchedAt = launchedAt
  }

  func cue(_ cue: SocCue, route: String) {
    emit("cue \(cue.name) via \(route)")
  }

  func heartbeat(_ plan: HeartbeatPlan?, note: String) {
    guard let plan else { return emit("heartbeat \(note)") }
    emit(
      "heartbeat \(note) \(plan.status.rawValue) period=\(plan.periodMs)ms "
        + "suspend=\(plan.autoSuspendMs)ms")
  }

  /// What the driver saw and what it decided. The line that answers "the heartbeat
  /// never fired on my phone" without a debugger: it separates "the band never got
  /// there" from "the band got there and the player stayed silent".
  func decision(status: TraceStatus, phase: Phase, pulls: Int, enabled: Bool, plan: HeartbeatPlan?) {
    emit(
      "heartbeat driver \(status.rawValue) \(phase.name) pulls=\(pulls) "
        + "enabled=\(enabled) → \(plan.map { "\($0.status.rawValue) \($0.periodMs)ms" } ?? "silent")")
  }

  func note(_ message: String) {
    emit(message)
  }

  private func emit(_ message: String) {
    guard isEnabled else { return }
    let line = "[haptic] \(String(format: "%9.3f", Date().timeIntervalSince(launchedAt)))s \(message)"
    print(line)
    Self.log.notice("\(line, privacy: .public)")
  }
}
