import CoreHaptics
import Foundation
import Observation
import OSLog
import UIKit
import SentryCore

/// The looping lub-dub, on **one** `CHHapticAdvancedPatternPlayer` (§4.4, D17, X8).
///
/// The whole point of the advanced player is that the OS schedules every beat:
/// `loopEnabled` plus `loopEnd = period` means one pattern is handed over once and
/// the system repeats it forever, with no per-beat main-thread wake-up and no drift.
/// **There is no `Timer` here and no repeating task** — the single `Task.sleep`
/// below is the 40-second auto-suspend wall (§2.15 guard 2), which fires once per
/// armed run and never per beat.
///
/// A status change does **not** rebuild anything (§10 C10 #2): the period moves by
/// assigning `loopEnd`, and the band moves by `sendParameters`. Rebuilding would
/// tear the loop down mid-beat, and the transition from HUNT to LOCKDOWN is the one
/// moment in the game where a gap would be felt as a bug rather than as dread.
///
/// `HeartbeatDriver`, at the bottom of this file, is what decides *whether* it should
/// be beating; this class only ever sees the answer.
@MainActor final class HeartbeatPlayer {

  private let tuning: Tuning
  /// A started engine, or `nil` when the hardware has none — the whole file no-ops
  /// on the Simulator through this one closure.
  private let startedEngine: () -> CHHapticEngine?
  private let trace: HapticTrace

  private var player: CHHapticAdvancedPatternPlayer?
  /// The band the **current player's pattern was authored at**.
  ///
  /// The band lives in the pattern's own event intensities and not in a dynamic
  /// parameter, because the lub carries a `CHHapticParameterCurve` on
  /// `.hapticIntensityControl` (the 0 → 1.0 @18 ms → 0 @90 ms swell) and Core Haptics
  /// gives a running parameter curve precedence over a dynamic parameter of the same
  /// ID for the span it covers — which is the whole 90 ms lub. Authoring at the plan's
  /// own band means every armed run is exactly the §4.4 row it should be (HUNT
  /// 0.75/0.30, LOCKDOWN 1.00/0.55) with no dynamic parameter needed at all, instead
  /// of every run playing at the reference band's weight.
  ///
  /// A band change *while the loop is live* still modulates rather than rebuilds
  /// (§10 C10 #2), and there the intensity half may be swallowed by that same
  /// precedence rule: period and sharpness move for certain, weight only if the OS
  /// composes the two. See `modulate(to:)` and the request to the lead in C10's
  /// report — an escalation lands on the correct weight the moment the run re-arms.
  private var authoredBand: TraceStatus?
  /// The band that *should* be beating. Kept across a suspend, because a suspend is
  /// the loop going quiet, not the plan going away — `rearm()` needs it back.
  private var plan: HeartbeatPlan?
  private var suspendWall: Task<Void, Never>?
  private var isSuspended = false
  /// How many times the engine has died and been rebuilt under *this* armed run.
  ///
  /// An engine that starts and then immediately stops would otherwise turn
  /// `engineDidStop()` into a restart loop, which is the battery risk X8 names.
  /// Reset by `arm(_:)`, so a real re-arm always gets a fresh set of attempts.
  private var restartsThisRun = 0
  private static let restartLimit = 3

  private static let log = Logger(subsystem: "pl.oumm.sentry.soc", category: "Heartbeat")

  init(
    tuning: Tuning, trace: HapticTrace,
    startedEngine: @escaping () -> CHHapticEngine?
  ) {
    self.tuning = tuning
    self.trace = trace
    self.startedEngine = startedEngine
  }

  // MARK: - The one entry point

  /// `nil` is silence — CALM, ALERT, a phase that is not `.investigating`, haptics
  /// switched off, or the app leaving the foreground. Every one of those guards
  /// lives in `SentryCore`'s pure `heartbeatPlan` / `HeartbeatDirector`, which is
  /// why this method only ever sees the answer.
  func set(_ next: HeartbeatPlan?) {
    guard let next else {
      guard plan != nil else { return }
      trace.heartbeat(nil, note: "stop")
      stop()
      return
    }

    let previous = plan
    plan = next

    // The same band, already beating: leave the loop exactly where it is. Restarting
    // it here would also re-arm the 40-second wall on every redundant call, and the
    // wall is the guard that stops a player reading a long `why` from being buzzed
    // for minutes.
    if let previous, previous == next, player != nil, !isSuspended { return }

    if player != nil, !isSuspended {
      modulate(to: next)
    } else {
      start(next)
    }
    // Only a loop that is actually running needs a wall around it. A `start` that
    // failed (no actuator, no engine) leaves `player == nil`, and arming there would
    // spawn a 40-second `Task` to suspend nothing.
    guard player != nil else { return }
    arm(next)
  }

  /// A pull re-arms the loop (§2.15 guard 2) — the player is working again, so the
  /// 40-second wall starts over and a suspended loop comes back.
  func rearm() {
    guard let plan else { return }
    if player == nil || isSuspended {
      trace.heartbeat(plan, note: "rearm")
      start(plan)
    }
    guard player != nil else { return }
    arm(plan)
  }

  /// The engine died under us (auto-shutdown, a reset, an audio-session hiccup). The
  /// player object is gone with it, so drop it and beat again from a fresh one.
  func engineDidStop() {
    player = nil
    authoredBand = nil
    guard let plan, !isSuspended else { return }
    guard restartsThisRun < Self.restartLimit else {
      trace.heartbeat(plan, note: "restart limit reached")
      return
    }
    restartsThisRun += 1
    start(plan)
  }

  // MARK: - The player

  /// Build the loop **at the plan's own band** and hand it to the OS once.
  ///
  /// No `sendParameters` here: the pattern already carries the band's intensity and
  /// sharpness, so the dynamic parameters would be neutral (×1.0 and +0.0) and
  /// sending them would only invite the curve-precedence collision described on
  /// `authoredBand`.
  private func start(_ plan: HeartbeatPlan) {
    guard let engine = startedEngine() else {
      // The Simulator's path, and every device without a Taptic Engine. Traced rather
      // than silent, so `-hapticTrace` distinguishes "the driver never decided to
      // beat" from "it decided, and there is no actuator to beat with".
      trace.heartbeat(plan, note: "start skipped — no haptics engine")
      return
    }
    guard let base = CHPatternSpec.heartbeat(plan.status, tuning) else {
      Self.log.error("CHPatternSpec has no heartbeat for \(plan.status.rawValue, privacy: .public)")
      return
    }
    do {
      let player = try engine.makeAdvancedPlayer(with: CHPatterns.pattern(base))
      player.loopEnabled = true
      player.loopEnd = periodSeconds(plan)
      self.player = player
      try player.start(atTime: CHHapticTimeImmediate)
      authoredBand = plan.status
      isSuspended = false
      trace.heartbeat(plan, note: "start")
    } catch {
      self.player = nil
      authoredBand = nil
      Self.log.error("heartbeat could not start: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// A band change on a live loop: the period is a property, the feel is a pair of
  /// dynamic parameters relative to the band the pattern was authored at, and the
  /// pattern itself is never touched (§10 C10 #2).
  ///
  /// **Device-pass note (X7, §7 step 5).** The sharpness offset and the new period
  /// take effect for certain. The intensity multiplier is the one that shares a
  /// parameter ID with the lub's envelope curve, so on a *live* escalation the weight
  /// may not move until the run re-arms and `start(_:)` re-authors at the new band —
  /// which a status change does within one pull. If the founder's device pass finds
  /// a HUNT → LOCKDOWN escalation that never gains weight, that is why, and the fix
  /// is in `CHPatternSpec` (C5), not here.
  private func modulate(to plan: HeartbeatPlan) {
    guard let player, let authored = authoredBand else { return start(plan) }
    do {
      player.loopEnd = periodSeconds(plan)
      try player.sendParameters(band(plan, authoredAt: authored), atTime: CHHapticTimeImmediate)
      trace.heartbeat(plan, note: "modulate")
    } catch {
      Self.log.error(
        "heartbeat could not modulate: \(error.localizedDescription, privacy: .public)")
      // `stopPlayer()` and **not** `stop()`: this is a rebuild, and `stop()` would
      // clear `plan` — after which a later `setHeartbeat(nil)` takes its "already
      // silent" early return and the loop below would beat on forever.
      stopPlayer()
      start(plan)
    }
  }

  /// Silence the loop, keep the plan. The only difference between this and `stop()`
  /// is who is expected to beat again.
  private func stopPlayer() {
    if let player {
      try? player.stop(atTime: CHHapticTimeImmediate)
    }
    player = nil
    authoredBand = nil
  }

  private func stop() {
    suspendWall?.cancel()
    suspendWall = nil
    stopPlayer()
    plan = nil
    isSuspended = false
  }

  /// Only the loop goes quiet. `plan` survives so `rearm()` can bring the same band
  /// straight back without the caller having to remember it.
  private func suspendNow() {
    guard player != nil else { return }
    stopPlayer()
    isSuspended = true
    trace.heartbeat(plan, note: "suspend")
  }

  // MARK: - The 40-second wall

  /// One sleep per armed run — not a scheduler. Cancelled and replaced by the next
  /// band change or the next pull, which is exactly the re-arm rule of §2.15.
  private func arm(_ plan: HeartbeatPlan) {
    suspendWall?.cancel()
    isSuspended = false
    restartsThisRun = 0
    guard plan.autoSuspendMs > 0 else { return }
    let wall = plan.autoSuspendMs
    suspendWall = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(wall))
      guard !Task.isCancelled else { return }
      self?.suspendNow()
    }
  }

  // MARK: - Numbers, from the plan

  private func periodSeconds(_ plan: HeartbeatPlan) -> TimeInterval {
    TimeInterval(plan.periodMs) / 1000
  }

  /// The target band as a scale off the band the running pattern was authored at.
  /// Both values are clamped to the ranges Core Haptics documents: intensity control
  /// is a 0…1 multiplier, sharpness control a -1…1 offset. Identical bands give a
  /// neutral pair.
  private func band(
    _ plan: HeartbeatPlan, authoredAt authored: TraceStatus
  ) -> [CHHapticDynamicParameter] {
    guard let target = plan.lub, let base = HeartbeatFeel.lub(for: authored), base.intensity > 0
    else { return [] }
    let intensity = min(max(target.intensity / base.intensity, 0), 1)
    let sharpness = min(max(target.sharpness - base.sharpness, -1), 1)
    return [
      CHHapticDynamicParameter(
        parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
      CHHapticDynamicParameter(
        parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0),
    ]
  }
}

// MARK: - What should be beating

/// Session in, `HeartbeatPlan?` out — the half of the heartbeat that has an opinion.
///
/// **Every rule lives in `SentryCore.HeartbeatDirector`** — HUNT/LOCKDOWN only,
/// `phase == .investigating` only, the 400 ms floor, the Settings toggle, and which
/// events re-arm the 40-second window. This driver owns no policy at all; it notices
/// that something moved and asks the pure director what should be beating. The
/// director owns the *rules*, `HeartbeatPlayer` owns the *clock*, and neither owns
/// both — which is why the rules are unit-tested in `swift test` on a machine with no
/// actuator (`SessionTests/HeartbeatTests`).
///
/// **Why an observer and not a view modifier.** The loop has to survive a phase
/// change, a sheet and a screen swapping under it; anything anchored to a view is
/// torn down at exactly those moments, and a modifier also needs someone to mount it
/// — which in this app would mean an edit to `App/RootView.swift`, a file C10 does
/// not own. `withObservationTracking` gives the same signal with no view at all: read
/// what matters, get told once when any of it changes, re-register.
///
/// **Scene phase.** Stopping on background is `GameModel.scenePhaseChanged`, which
/// sends `setHeartbeat(nil)` (§4.4: never beat backgrounded); a second stop here would
/// only race it. **Coming back** is this driver's job, because nothing else re-asks
/// the question and a player who took a call mid-LOCKDOWN would otherwise return to
/// silence until the meter happened to move again.
@MainActor final class HeartbeatDriver {

  /// Everything that can change what should be beating. A pull is in here as a count
  /// rather than a flag because `queried` growing *is* the `PULL_SOURCE` the re-arm
  /// rule refers to (§2.15 guard 2).
  private struct Signal: Equatable {
    let status: TraceStatus
    let phase: Phase
    let pulls: Int
    let hapticsEnabled: Bool
  }

  private let tuning: Tuning
  private let trace: HapticTrace
  private let setPlan: (HeartbeatPlan?) -> Void
  private let rearmPlayer: () -> Void

  /// Weak: the model owns the app, not the other way round. A model that goes away
  /// (a preview, a test) simply stops the loop.
  private weak var model: GameModel?
  private var director: HeartbeatDirector?
  private var last: Signal?
  /// Invalidates the observation registered by a previous `attach`, so re-attaching
  /// cannot leave two tracking loops answering for the same engine.
  private var generation = 0
  /// `nonisolated(unsafe)` for one reason: `deinit` is nonisolated and handing the
  /// token back is the only thing it does. The token is written once, on the main
  /// actor, before anything else can reach this object, and read once at the end of
  /// its life — there is no moment when two isolations can see it.
  private nonisolated(unsafe) var foregroundObserver: (any NSObjectProtocol)?

  init(
    tuning: Tuning, trace: HapticTrace,
    setPlan: @escaping (HeartbeatPlan?) -> Void,
    rearmPlayer: @escaping () -> Void
  ) {
    self.tuning = tuning
    self.trace = trace
    self.setPlan = setPlan
    self.rearmPlayer = rearmPlayer
  }

  deinit {
    if let foregroundObserver {
      NotificationCenter.default.removeObserver(foregroundObserver)
    }
  }

  /// Start watching this model. Called on every screen build (`sentryHaptics`), so it
  /// has to be cheap and idempotent — the same model twice is a pointer compare.
  ///
  /// The first evaluation is deferred by one hop on purpose: `attach` runs inside a
  /// view's body, and nothing that runs there may reach back into the state SwiftUI
  /// is in the middle of reading.
  func attach(_ model: GameModel) {
    guard self.model !== model else { return }
    self.model = model
    self.director = nil
    self.last = nil
    observeForeground()
    let token = bumpGeneration()
    Task { @MainActor [weak self] in
      guard let self, self.generation == token else { return }
      self.observe(token)
    }
  }

  // MARK: - Observation

  private func bumpGeneration() -> Int {
    generation &+= 1
    return generation
  }

  /// Read the signal inside `withObservationTracking`, act on it, and re-register.
  ///
  /// `onChange` fires *before* the value is written, which is why the re-read hops
  /// through a `Task`: by the time it runs, the mutation is done and the fresh signal
  /// is the one the director should be asked about.
  private func observe(_ token: Int) {
    guard let model else { return setPlan(nil) }
    let signal = withObservationTracking {
      Signal(
        status: model.session.status, phase: model.session.phase,
        pulls: model.session.queried.count, hapticsEnabled: model.settings.haptics)
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self, self.generation == token else { return }
        self.observe(token)
      }
    }
    apply(signal)
  }

  /// Re-ask the question when the app comes back to the foreground. The director
  /// decides whether the 40-second window is still open, exactly as it does for a
  /// status change.
  private func observeForeground() {
    guard foregroundObserver == nil else { return }
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self, let model = self.model else { return }
        self.apply(
          Signal(
            status: model.session.status, phase: model.session.phase,
            pulls: model.session.queried.count, hapticsEnabled: model.settings.haptics),
          force: true)
      }
    }
  }

  /// `force` is the foreground path: coming back from the background is the one
  /// moment the answer can differ without the signal differing, because
  /// `GameModel.scenePhaseChanged` stopped the loop on the way out.
  ///
  /// Otherwise an unchanged signal is skipped. `session` carries far more than the
  /// four fields watched here — opening a sheet is a session change — and re-deciding
  /// on each of them would put a duplicate line in every trace and re-ask the
  /// director a question it has already answered. Nothing is lost by waiting: the
  /// only decision that turns on time alone is the 40-second wall, and that one is
  /// the player's own `Task`, not a poll.
  private func apply(_ signal: Signal, force: Bool = false) {
    if !force, let last, last == signal { return }
    let now = Self.nowMs()
    var director = self.director ?? HeartbeatDirector(tuning: tuning, nowMs: now)

    // The pull re-arms **first**, so the update below is asked about a window that
    // has just been reset rather than one that expired 20 seconds ago.
    if let last, signal.pulls != last.pulls {
      director.pulledSource(nowMs: now)
      rearmPlayer()
    }
    let plan = director.update(
      status: signal.status, phase: signal.phase,
      hapticsEnabled: signal.hapticsEnabled, nowMs: now)
    self.director = director
    self.last = signal
    trace.decision(
      status: signal.status, phase: signal.phase, pulls: signal.pulls,
      enabled: signal.hapticsEnabled, plan: plan)
    setPlan(plan)
  }

  /// Monotonic, and unaffected by the clock moving — the director measures a window,
  /// not a date.
  private static func nowMs() -> Int {
    Int(ProcessInfo.processInfo.systemUptime * 1000)
  }
}
