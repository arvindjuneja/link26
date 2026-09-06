import AVFoundation
import Foundation
import OSLog
import SentryCore

/// **Where every sound in the game comes out** (`FEEL.md` §9).
///
/// One `AVAudioEngine`, a pool of player nodes for polyphony, and a single looping
/// node for the room tone. Buffers are decoded once at start-up and scheduled
/// thereafter, so firing a cue costs a `scheduleBuffer` and never a file read — a
/// `tick` that arrives 280 ms after the last one cannot afford to touch the disk.
///
/// **Category `.ambient`** (§9). Three consequences, all of them wanted: the ringer
/// switch silences the game, the player's own music keeps playing underneath, and
/// nothing here can duck a podcast. This is a reading game and **the haptics carry
/// the tension when it is muted** — which is why the sound layer is allowed to be
/// this quiet about failing.
///
/// **Failure is silence, never a crash.** The Simulator, a device with a broken
/// session, a bundle missing a file: every path below ends in a log line and a
/// `return`. `isAvailable` latches false after the engine refuses to start, so a
/// broken session costs one failed `start()` and not one per cue.
///
/// **Three gates**, checked in this order: `Feel.replayMuted` (a QA jump is a
/// fast-forward, not a performance — the same rule `GameModel.cuesAreLive` applies to
/// haptics), the **Sound** toggle, and, for the heartbeat alone, the **Heartbeat
/// sound** toggle. Reduce Motion is deliberately not one of them (D18): it is a
/// vestibular setting and sound is not motion.
@MainActor final class SoundService {

  /// The app's one engine. A second `AVAudioEngine` is a second audio-session client.
  static let shared = SoundService()

  /// −30 dB, the room tone's resting level (§9).
  static let roomToneGain: Float = 0.031_623
  /// −42 dB: the resting level ducked by 12 dB for 600 ms on `file` (§9).
  static let roomToneDuckedGain: Float = 0.007_943
  /// −24 dB, the optional heartbeat sound (§9's `beat-lub` / `beat-dub` row).
  static let heartbeatGain: Float = 0.063_096
  /// How many one-shots can overlap. Six covers the worst moment in the game — three
  /// cards landing over a results chord while the ECG pings — with headroom.
  private static let voiceCount = 6

  private let engine = AVAudioEngine()
  private var voices: [AVAudioPlayerNode] = []
  private var nextVoice = 0
  private let roomTonePlayer = AVAudioPlayerNode()
  private var buffers: [String: AVAudioPCMBuffer] = [:]

  /// False once the engine has refused to come up. One failure, not one per cue.
  private var isAvailable = true
  private var isStarted = false
  /// Whether a shift is open. Kept across a backgrounding so the tone can come back.
  private var wantsRoomTone = false
  /// Bumped by every duck, so a second `file` inside 600 ms does not let the first
  /// one's restore un-duck it early.
  private var duckGeneration = 0

  /// The band the ear is beating, or `nil` for silence. Kept across a suspend for
  /// the same reason `HeartbeatPlayer` keeps its own: a suspend is the run going
  /// quiet, not the plan going away, and `rearmHeartbeat()` needs it back.
  private var heartbeatPlan: HeartbeatPlan?
  /// The one task walking the current run's schedule. **Not** a timer and not one
  /// task per beat: it is a single walk down a pre-computed list.
  private var heartbeatRun: Task<Void, Never>?
  /// The 40-second wall was reached. Distinguishes "quiet because the run ended"
  /// from "quiet because a switch is off", so moving a switch cannot resurrect a run
  /// the player already stopped working through.
  private var heartbeatIsSuspended = false

  private let feel: Feel
  private let dubOffset: Duration
  /// `-hapticTrace` also traces the ear (F2a).
  ///
  /// The Simulator has no haptics and a reviewer cannot hear a screenshot, so
  /// "did that sound fire, once, at the right moment?" is exactly as unanswerable
  /// as the haptics question `HapticTrace` was written for — and it is the same
  /// question. One flag, both channels, one interleaved timeline to read.
  private let trace: HapticTrace

  private static let log = Logger(subsystem: "pl.oumm.sentry.soc", category: "Sound")

  init(
    feel: Feel = .shared,
    tuning: Tuning = ContentPack.bundled.tuning,
    trace: HapticTrace = HapticTrace()
  ) {
    self.feel = feel
    self.dubOffset = .milliseconds(tuning.heartbeat.dubOffsetMs)
    self.trace = trace
  }

  // MARK: - Firing a cue

  /// Play a cue's sound. `variant` picks the pitch for the cues that have several —
  /// the card's index, the alert's slot (§1, §4).
  ///
  /// Called from `EffectRunner`'s `.haptic` arm and from `GameModel.feel(_:)`, so a
  /// cue reaches the hand and the ear from **one** call site (F2a). The two channels
  /// have separate switches, which is why the haptics gate is not checked here: a
  /// player who turned haptics off did not ask for silence.
  func play(_ cue: SocCue, variant: Int = 0) {
    guard isAudible else {
      trace.note("sound \(cue.name) muted (replay=\(feel.replayMuted) sound=\(feel.sound))")
      return
    }
    if case .heartbeat(let status) = cue {
      playHeartbeat(status)
      return
    }
    guard let name = SoundBank.file(for: cue, variant: variant) else { return }
    play(named: name)
  }

  /// **One** lub, then its dub `tuning.heartbeat.dubOffsetMs` later — the one-shot
  /// path, exactly as `CHPatternSpec.heartbeat` shapes a single beat for the hand.
  ///
  /// This is the *`SocCue`* route: a QA cue list, a preview, anything that fires
  /// `heartbeat` as an event. The looping heartbeat a player actually hears during a
  /// shift does **not** come through here — it is `setHeartbeat(_:)` below, armed by
  /// the same call that hands the loop to Core Haptics, because the loop is a state
  /// and not a cue.
  ///
  /// Behind its own toggle and **off by default** (§9): the heartbeat is a haptic
  /// channel first, and a low thump under every beat is a different game.
  private func playHeartbeat(_ status: TraceStatus) {
    guard feel.heartbeatSound else { return }
    playBeat(HeartbeatSoundHit(atMs: 0, beatIndex: 0), status: status)
    Task { [weak self] in
      try? await Task.sleep(for: self?.dubOffset ?? .milliseconds(120))
      self?.playBeat(HeartbeatSoundHit(atMs: 0, beatIndex: 1), status: status)
    }
  }

  // MARK: - The audible heartbeat

  /// **The loop, for the ear** (§9's `beat-lub` / `beat-dub` row).
  ///
  /// Called by `HapticsEngine.setHeartbeat(_:)` — the same call that hands the
  /// pattern to `CHHapticAdvancedPatternPlayer` — so the two channels are armed by
  /// the one thing in the app that knows which band is beating, and can never
  /// disagree about it. Everything that decides *whether* there should be a
  /// heartbeat at all (HUNT/LOCKDOWN only, `phase == .investigating`, the Haptics
  /// switch, the background) already happened in `SentryCore.HeartbeatDirector`;
  /// this method only ever sees the answer.
  ///
  /// The **Heartbeat sound** switch is this side's own gate, on top of the two the
  /// rest of the service uses — which is what makes that Settings row do something.
  func setHeartbeat(_ plan: HeartbeatPlan?) {
    guard let plan else {
      guard heartbeatPlan != nil else { return }
      heartbeatPlan = nil
      cancelHeartbeatRun()
      heartbeatIsSuspended = false
      trace.note("heartbeat sound stop")
      return
    }
    // The same band, already beating: leave the run where it is. Restarting here
    // would reset the schedule on every redundant call and slide the thump off the
    // buzz it belongs under.
    if heartbeatPlan == plan, heartbeatRun != nil { return }
    heartbeatPlan = plan
    startHeartbeatRun(plan, note: "start")
  }

  /// A pull re-arms the run (§2.15 guard 2), alongside `HeartbeatPlayer.rearm()`.
  func rearmHeartbeat() {
    guard let heartbeatPlan else { return }
    startHeartbeatRun(heartbeatPlan, note: "rearm")
  }

  /// Generate the run's schedule once and walk it. A cancelled task is the only way
  /// a run stops early, and the wall is the only way it stops on its own.
  private func startHeartbeatRun(_ plan: HeartbeatPlan, note: String) {
    cancelHeartbeatRun()
    heartbeatIsSuspended = false
    guard isAudible, feel.heartbeatSound else {
      trace.note(
        "heartbeat sound \(note) muted (replay=\(feel.replayMuted) sound=\(feel.sound) "
          + "heartbeatSound=\(feel.heartbeatSound))")
      return
    }
    let schedule = heartbeatSoundSchedule(plan)
    guard !schedule.isEmpty else { return }
    let status = plan.status
    trace.note(
      "heartbeat sound \(note) \(status.rawValue) period=\(plan.periodMs)ms "
        + "\(schedule.count) beats over \(plan.autoSuspendMs)ms")
    // Every beat is timed from the run's **origin**, never from the previous beat.
    // `Task.sleep` guarantees a floor and not a deadline, so relative gaps compound:
    // measured on the Simulator, `sleep(for: 536 ms)` per beat drifted the loop to a
    // 565 ms period — 5 % slow, which over a 40-second run is two seconds of lag
    // between the thump and the buzz the OS is scheduling exactly. Sleeping *until*
    // an absolute instant on the continuous clock makes a late beat cost only itself.
    let origin = ContinuousClock.now
    heartbeatRun = Task { [weak self] in
      for hit in schedule {
        try? await Task.sleep(until: origin.advanced(by: .milliseconds(hit.atMs)), clock: .continuous)
        guard !Task.isCancelled, let self else { return }
        self.playBeat(hit, status: status)
      }
      guard !Task.isCancelled, let self else { return }
      self.heartbeatRunDidReachTheWall()
    }
  }

  /// One beat. The gates are re-read here rather than once at the top of the run: a
  /// forty-second run is long enough for a player to move a switch inside it, and a
  /// switch that only takes effect at the next band change is not a switch.
  private func playBeat(_ hit: HeartbeatSoundHit, status: TraceStatus) {
    guard isAudible, feel.heartbeatSound else { return }
    // Through `SoundBank`, so `beat-lub` / `beat-dub` are named in exactly one place
    // in the app — the same rule every other cue follows.
    guard let name = SoundBank.file(for: .heartbeat(status), variant: hit.beatIndex) else { return }
    play(named: name, gain: Self.heartbeatGain)
  }

  /// The 40-second wall. The plan survives, so the next pull brings the same band
  /// straight back — `HeartbeatPlayer.suspendNow()`, for the ear.
  private func heartbeatRunDidReachTheWall() {
    heartbeatRun = nil
    heartbeatIsSuspended = true
    trace.note("heartbeat sound suspend")
  }

  private func cancelHeartbeatRun() {
    heartbeatRun?.cancel()
    heartbeatRun = nil
  }

  private func play(named name: String, gain: Float = 1) {
    // `takeVoice()` **first**, and the order is load-bearing: it is what brings the
    // engine up, and bringing the engine up is what decodes `buffers`. Written the
    // other way round — buffer, then voice — the very first cue of a launch is
    // always dropped, because the map it looks in has not been filled yet. Caught by
    // `-hapticTrace` on a QA jump to the debrief, where the verdict chord is the
    // first sound the process ever asks for.
    guard let voice = takeVoice(), let buffer = buffers[name] else {
      trace.note("sound \(name) dropped (engine unavailable or not decoded)")
      return
    }
    trace.note("sound \(name)")
    voice.volume = gain
    // `.interrupts` rather than queueing: a voice taken back mid-tail is a voice that
    // was needed more by the cue arriving now than by the one already fading.
    voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    if !voice.isPlaying { voice.play() }
  }

  /// Round-robin over the pool. `nil` only when the engine never came up.
  private func takeVoice() -> AVAudioPlayerNode? {
    guard start(), !voices.isEmpty else { return nil }
    let voice = voices[nextVoice % voices.count]
    nextVoice = (nextVoice + 1) % voices.count
    return voice
  }

  // MARK: - Room tone

  /// A shift opened or closed (§9: "while a shift is open").
  func setShiftOpen(_ isOpen: Bool) {
    wantsRoomTone = isOpen
    isOpen ? startRoomTone() : stopRoomTone()
  }

  /// Duck the room tone by 12 dB for 600 ms — the breath the cut to black takes
  /// (§8's `file` row, §9's room-tone row).
  func duckRoomTone(for duration: Duration = .milliseconds(600)) {
    guard roomTonePlayer.isPlaying else { return }
    duckGeneration &+= 1
    let generation = duckGeneration
    trace.note("room tone ducked for \(duration)")
    roomTonePlayer.volume = Self.roomToneDuckedGain
    Task { [weak self] in
      try? await Task.sleep(for: duration)
      guard let self, self.duckGeneration == generation else { return }
      self.roomTonePlayer.volume = Self.roomToneGain
    }
  }

  private func startRoomTone() {
    guard isAudible, start(), let buffer = buffers[SoundBank.roomTone] else { return }
    guard !roomTonePlayer.isPlaying else { return }
    trace.note("room tone on (-30 dB)")
    roomTonePlayer.volume = Self.roomToneGain
    roomTonePlayer.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
    roomTonePlayer.play()
  }

  private func stopRoomTone() {
    guard roomTonePlayer.engine != nil, roomTonePlayer.isPlaying else { return }
    trace.note("room tone off")
    roomTonePlayer.stop()
  }

  // MARK: - Toggles

  /// The Sound switch was moved. Turning it off silences the tone at once rather
  /// than at the next phase change, which is what a player expects of a switch.
  func soundSettingChanged() {
    if isAudible {
      if wantsRoomTone { startRoomTone() }
      resumeHeartbeatIfArmed(note: "sound on")
    } else {
      stopRoomTone()
      for voice in voices { voice.stop() }
      cancelHeartbeatRun()
    }
  }

  /// The Heartbeat-sound switch was moved. Off silences the thump **now**; on starts
  /// it under the beat that is already buzzing, rather than at the next band change.
  /// Same promise, same shape as the Sound switch above.
  func heartbeatSoundSettingChanged() {
    if feel.heartbeatSound {
      resumeHeartbeatIfArmed(note: "switch on")
    } else {
      cancelHeartbeatRun()
      trace.note("heartbeat sound off (switch)")
    }
  }

  /// Start beating again only if there is a band to beat and its run has not already
  /// hit the wall — a switch is not a re-arm, and a player who stopped working
  /// should not be buzzed back to life by moving one.
  private func resumeHeartbeatIfArmed(note: String) {
    guard let heartbeatPlan, !heartbeatIsSuspended, heartbeatRun == nil else { return }
    startHeartbeatRun(heartbeatPlan, note: note)
  }

  /// The three gates, in order. Read by every path that makes a noise.
  private var isAudible: Bool { !feel.replayMuted && feel.sound }

  // MARK: - Lifecycle

  /// The app left or re-entered the foreground.
  ///
  /// `.ambient` sessions are deactivated on the way out and the engine stops with
  /// them; nothing is gained by fighting that. What matters is that the tone comes
  /// back with the shift it belongs to, and that a suspended app is never left with a
  /// looping node it thinks is playing.
  func setForeground(_ isForeground: Bool) {
    guard isForeground else {
      stopRoomTone()
      // `GameModel.scenePhaseChanged` already sent `setHeartbeat(nil)` down the
      // haptics sink, which clears the plan here too; cancelling is the belt to that
      // brace, so a suspended app can never be left with a task scheduling thumps
      // into a paused engine.
      cancelHeartbeatRun()
      engine.pause()
      return
    }
    guard isStarted else { return }
    isStarted = false            // force a re-`start()`; the session was deactivated
    if wantsRoomTone { startRoomTone() }
  }

  /// Bring the engine up, once. Returns whether there is anything to play into.
  @discardableResult private func start() -> Bool {
    guard isAvailable else { return false }
    if isStarted, engine.isRunning { return true }
    // `isStarted` without `isRunning` is a restart, not a first start: an `.ambient`
    // engine stops itself when the session goes away under it, and the trace should
    // say which of the two happened rather than printing "started" twice.
    let isRestart = isStarted

    if buffers.isEmpty { loadBuffers() }

    do {
      let session = AVAudioSession.sharedInstance()
      // `.ambient` + `.mixWithOthers`: the ringer switch wins, and the player's own
      // music keeps playing. `.ambient` already mixes, but saying so survives a
      // future category change that would not.
      try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
    } catch {
      // Not fatal: a session that will not activate still lets the engine render to
      // nowhere, and the game is playable in silence by design.
      Self.log.notice("audio session: \(error.localizedDescription, privacy: .public)")
    }

    if voices.isEmpty { attachNodes() }

    do {
      engine.prepare()
      try engine.start()
      isStarted = true
      trace.note(
        "sound engine \(isRestart ? "restarted" : "started") · \(buffers.count) buffers "
          + "· \(voices.count) voices")
      return true
    } catch {
      isAvailable = false
      Self.log.error(
        "audio engine did not start — the game is silent: \(error.localizedDescription, privacy: .public)")
      trace.note("sound engine did not start: \(error.localizedDescription)")
      return false
    }
  }

  /// Decode every asset once. A missing file is a bundling mistake, loud in DEBUG and
  /// silent in Release — never a crash in a player's hand over a sound effect.
  private func loadBuffers() {
    for name in SoundBank.allFiles {
      guard
        let url = Bundle.main.url(forResource: name, withExtension: SoundBank.fileExtension)
      else {
        assertionFailure("\(name).\(SoundBank.fileExtension) is not in the bundle")
        continue
      }
      do {
        let file = try AVAudioFile(forReading: url)
        guard
          let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { continue }
        try file.read(into: buffer)
        buffers[name] = buffer
      } catch {
        Self.log.error("\(name) did not decode: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Attach the pool and the room-tone node, all at the same format.
  ///
  /// Every asset is rendered by `ios/scripts/render-sfx.swift` at one sample rate and
  /// one channel count, so one format connects the whole graph — which is what lets a
  /// voice be reused for any cue instead of being reconnected per sound.
  private func attachNodes() {
    let format = buffers.values.first?.format
    for _ in 0..<Self.voiceCount {
      let voice = AVAudioPlayerNode()
      engine.attach(voice)
      engine.connect(voice, to: engine.mainMixerNode, format: format)
      voices.append(voice)
    }
    engine.attach(roomTonePlayer)
    engine.connect(roomTonePlayer, to: engine.mainMixerNode, format: format)
  }
}
