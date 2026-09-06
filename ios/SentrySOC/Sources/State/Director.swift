import Foundation
import OSLog
import SwiftUI
import SentryCore

/// **The thing that makes the desk happen** (F2b, `docs/ios/FEEL.md`).
///
/// F2a wrote the four timelines of §1/§2/§4/§8 as pure `[Beat]` and unit-tested every
/// number in them. Nothing played them. This is what plays them: one object, owned by
/// `GameModel`, that walks a sequence on a monotonic clock, marks each beat as it
/// arrives, and fires the beat's two channels through the model's single `feel(_:)`
/// call site. A screen therefore never holds a timer and never decides *when* — it
/// asks `director.shows(.trigger, of: id)` and draws.
///
/// Four rules hold, and they are the reason this is a `Director` and not four
/// `Task`s scattered across four screens:
///
/// 1. **One sequence at a time.** The handover, an arrival, a pull and the call are
///    never on screen together, and a `runID` guards a stale read: a view that asks
///    about a beat of a sequence that is no longer running is told `false` rather
///    than shown the last one's end state.
/// 2. **Absolute deadlines, not relative sleeps, and `tolerance: .zero`.** A
///    `Task.sleep` between beats accumulates the scheduler's slop — F2a measured 5 %
///    on the heartbeat walk, which over §1's seven alerts is a beat and a half of
///    drift. Every beat sleeps to `start + at` on a `ContinuousClock`, so beat seven
///    lands 2460 ms after beat one however late beat three was. The explicit zero
///    tolerance is the second half: the default lets the runtime coalesce a wake-up
///    with whatever else is due, and the measured cost of leaving it was 140 ms on a
///    500 ms wait — §1's line landed at 3760 ms against a specified 3620.
/// 3. **Reduce Motion collapses, sound and haptics stay** (D18, §1–§8's last line).
///    `collapsed()` puts every beat at zero; this arrives them all on one frame and
///    still fires the cues — deduplicated, see `fire(_:)`.
/// 4. **A tap skips.** `skip()` arrives everything that has not arrived and drops the
///    cues it passed. A player who taps through has asked to stop being performed at.
///
/// The rest of the class is §5's pressure, §6's Vale and §7's leads-to: the small
/// pieces of shift-scoped state that are *felt* rather than scored, kept here rather
/// than in `SessionState` precisely because none of them may reach `scoreShift`.
@Observable @MainActor final class Director {

  // MARK: - The running sequence

  /// Which sequence is on screen. `""` when none is.
  private(set) var runID = ""
  /// The beats of `runID` that have arrived.
  private(set) var arrived: Set<BeatKind> = []
  /// True between the first beat and the `.end` beat.
  private(set) var isPlaying = false

  /// Sequences that have already run in this shift, so a view that rebuilds — a
  /// `.onAppear` after a sheet dismissal, a Dynamic Type change — does not replay the
  /// alert it already delivered. Cleared by `resetForShift()`.
  private var played: Set<String> = []

  /// The **end state** of every sequence that has finished this shift: its id, and
  /// the exact set of beats it contained.
  ///
  /// Two bugs live here, both found on the glass:
  ///
  /// 1. Without an end-state memory at all, the case screen went blank the moment a
  ///    pull started — only one sequence runs at a time, so `runID` had moved to
  ///    `pull:…` and `shows(.sources, of: "arrival:…")` went `false` under an open
  ///    sheet. Caught by the Shift-1 replay, which could not find the second source.
  /// 2. Remembering only the *id* was worse: `shows(_:of:)` then answered `true` for
  ///    every kind, including beats the sequence never had. The debrief of a **good**
  ///    call therefore drew §8's rose breach edge — a `breachDelta` of 0 emits no
  ///    `.breach` beat, but a finished run claimed one. Visible in
  ///    `docs/screenshots/ios/feel/call`, frames 37–40, as a rose border that should
  ///    not exist.
  ///
  /// So the memory is the *set*: a finished sequence shows exactly what it contained,
  /// for as long as the shift lasts.
  private var endStates: [String: Set<BeatKind>] = [:]
  /// The kinds of the sequence currently on the clock — what a skip arrives, and what
  /// gets filed in `endStates` when it finishes.
  private var currentKinds: Set<BeatKind> = []
  private var task: Task<Void, Never>?

  /// Where a beat's two channels go: `(haptic, sound, variant)`. Wired once by
  /// `GameModel.init` to `feel(haptic:sound:variant:)`, which is the app's single cue
  /// call site — the Director therefore knows *when* a cue fires and nothing at all
  /// about how. The channels stay **separate** because a beat names them separately:
  /// §1's alert is a `select` under a `ping`, and §4's log line is a `tick` the hand
  /// never feels.
  var cue: (SocCue?, SocCue?, Int) -> Void = { _, _, _ in }

  private static let log = Logger(subsystem: "pl.oumm.sentry.soc", category: "Director")

  // MARK: - Playing one

  /// Play `beats` under `id`, or collapse them if the player asked for less motion.
  ///
  /// Idempotent per `id` within a shift: calling it again from a second `.onAppear`
  /// is a no-op, which is what lets a screen arm its sequence from the lifecycle hook
  /// that is actually reliable rather than from the one that fires exactly once.
  /// - Parameter silencing: cues this run must **not** fire, because something else
  ///   already did. There is exactly one caller: §8's `.cut` beat carries `file`, and
  ///   the reducer already emitted `Effect.haptic(.file)` on `MAKE_CALL` — the thud
  ///   belongs to the *action*, and the sequence is only drawing what the action did.
  ///   Without this the call would slam twice, half a frame apart.
  func play(
    _ beats: [Beat], id: String, reduceMotion: Bool, silencing: Set<SocCue> = []
  ) {
    guard !played.contains(id) else { return }
    played.insert(id)
    task?.cancel()
    silenced = silencing

    runID = id
    arrived = []
    currentKinds = Set(beats.map(\.kind))

    guard !beats.isEmpty else {
      isPlaying = false
      return
    }

    guard !reduceMotion else {
      endStates[id] = currentKinds
      // D18's visual half: every beat on the first frame. The cues are unchanged and
      // still fire — a sequence is not a decoration a player loses by asking the
      // system for less motion — but they fire **deduplicated**, because seven
      // identical pings inside one millisecond is a blurt rather than the rising line
      // §1 asks for, and the six-voice pool would drop most of them anyway.
      isPlaying = false
      arrived = Set(beats.map(\.kind))
      var heard: Set<String> = []
      for beat in beats.sorted(by: { $0.at < $1.at }) {
        guard let sound = beat.cue ?? beat.sound, heard.insert(sound.name).inserted else {
          continue
        }
        fire(beat)
      }
      // Nothing to wait for: a collapsed sequence has already happened.
      flushNudge()
      return
    }

    isPlaying = true
    let ordered = beats.sorted { $0.at < $1.at }
    let start = ContinuousClock.now
    startedAt = start
    task = Task { @MainActor [weak self] in
      for beat in ordered {
        let due = start.advanced(by: .milliseconds(beat.at))
        if ContinuousClock.now < due {
          try? await Task.sleep(until: due, tolerance: .zero, clock: ContinuousClock())
        }
        guard !Task.isCancelled, let self, self.runID == id else { return }
        self.deliver(beat)
      }
      self?.isPlaying = false
    }
  }

  /// Mark a beat arrived and spend its two channels.
  private func deliver(_ beat: Beat) {
    withAnimation(Motion.gated(Motion.beatArrive)) {
      _ = arrived.insert(beat.kind)
    }
    // The two beats the SystemBar answers to: §2's arrival spike and §4's extra beat
    // after a decisive finding. Both are the trace, so both go through one counter.
    if beat.kind == .ecgSpike || beat.kind == .decisive { pulse += 1 }
    fire(beat)
    if beat.kind == .end {
      isPlaying = false
      endStates[runID] = currentKinds
      // §7's nudge rides on the findings, not on the action that bought them.
      flushNudge()
    }
  }

  /// **The ECG blip**, as a monotonic counter (`FEEL.md` §2, §4, §5). Bumped by the
  /// arrival spike, by a decisive finding landing, and by every live-board reveal.
  /// `SystemBar` watches it and spikes the trace once per change — a counter rather
  /// than a flag because two blips in a row are two events.
  private(set) var pulse = 0

  /// Cues this run leaves to somebody else. See `play(_:id:reduceMotion:silencing:)`.
  private var silenced: Set<SocCue> = []

  /// When the running sequence started, for the QA timestamp overlay and for nothing
  /// else. `FEEL.md` §11 asks a reviewer to check the beats off a frame strip to
  /// ±60 ms, and a 100 ms grid cannot be read that finely without the frames saying
  /// what time it is — so under `SENTRY_QA` the app prints the elapsed milliseconds
  /// of the current run in the corner, and the strip becomes a measurement rather
  /// than an impression.
  private(set) var startedAt: ContinuousClock.Instant?

  /// Milliseconds since the running sequence began, or `nil` when none is.
  var elapsedMs: Milliseconds? {
    guard let startedAt else { return nil }
    let delta = ContinuousClock.now - startedAt
    return Int(delta.components.seconds) * 1000
      + Int(delta.components.attoseconds / 1_000_000_000_000_000)
  }

  /// The ear and the hand, in that order — `GameModel.feel(_:variant:)` decides which
  /// of them is switched on, and the pitch comes off the beat's own index so a
  /// filling queue rises and four cards in a row are a phrase (§1, §4, §9).
  private func fire(_ beat: Beat) {
    let haptic = beat.cue.flatMap { silenced.contains($0) ? nil : $0 }
    let sound = beat.sound.flatMap { silenced.contains($0) ? nil : $0 }
    guard haptic != nil || sound != nil else { return }
    cue(haptic, sound, Director.variant(of: beat.kind))
  }

  /// A beat's pitch slot: which alert, which card. `SoundBank` wraps an index it did
  /// not expect, so this never has to be clamped.
  static func variant(of kind: BeatKind) -> Int {
    switch kind {
    case .alertLand(let index): index
    case .card(let index): index
    case .logLine(let index): index
    default: 0
    }
  }

  /// **A tap anywhere.** Everything arrives; the cues the sequence had not reached
  /// are dropped, because a skip is a request to stop being performed at.
  func skip() {
    guard isPlaying else { return }
    task?.cancel()
    task = nil
    isPlaying = false
    endStates[runID] = currentKinds
    withAnimation(Motion.gated(Motion.beatArrive)) {
      arrived = currentKinds
    }
  }

  /// Whether `kind` has arrived in the sequence a view believes is running.
  ///
  /// The `of:` guard is the whole point: `CaseView` asks about `.trigger` and gets
  /// `false` while the *pull* sequence is the one on the clock, so a case rebuilt
  /// under a sheet never flashes the previous alert's end state.
  func shows(_ kind: BeatKind, of id: String) -> Bool {
    if let end = endStates[id] { return end.contains(kind) }
    return runID == id && arrived.contains(kind)
  }

  /// True once the named sequence has reached its end state — by playing out, by
  /// being skipped, or by being collapsed under Reduce Motion.
  func isFinished(_ id: String) -> Bool { endStates[id] != nil }

  /// True while the named sequence is still delivering — what a screen wires its
  /// tap-to-skip to, so a finished screen is not covered by an invisible eater of
  /// taps.
  func isRunning(_ id: String) -> Bool {
    runID == id && isPlaying
  }

  func cancel() {
    task?.cancel()
    task = nil
    isPlaying = false
    runID = ""
    arrived = []
    currentKinds = []
    startedAt = nil
  }

  // MARK: - §4 · the clock counting the cost

  /// Shift-minutes the clock has **not yet counted up** (§4: "the shift clock in the
  /// SystemBar counts up the cost … in sync").
  ///
  /// `PULL_SOURCE` spends the minutes the instant it is dispatched — the session must
  /// be truthful, because a player who dismisses the sheet mid-query has still paid —
  /// so the honesty and the ceremony are separated here: the session says 26 m, this
  /// says "10 of those have not been counted out loud yet", and the strip draws the
  /// difference. It reaches zero when the log pane stops, and it is never anything
  /// but a subtraction on a number the engine already wrote.
  private(set) var clockHeld = 0
  private var clockTask: Task<Void, Never>?

  /// Count `cost` shift-minutes up over `overMs`, one minute at a time.
  func countUpClock(cost: Int, overMs: Milliseconds, reduceMotion: Bool) {
    clockTask?.cancel()
    guard cost > 0, overMs > 0, !reduceMotion else {
      clockHeld = 0
      return
    }
    clockHeld = cost
    let step = Duration.milliseconds(max(1, overMs / cost))
    clockTask = Task { @MainActor [weak self] in
      let start = ContinuousClock.now
      for minute in 1...cost {
        let due = start.advanced(by: step * minute)
        if ContinuousClock.now < due {
          try? await Task.sleep(until: due, tolerance: .zero, clock: ContinuousClock())
        }
        guard !Task.isCancelled, let self else { return }
        self.clockHeld = max(0, cost - minute)
      }
    }
  }

  /// The shift clock as the strip should draw it: what the session has spent, minus
  /// the minutes the count-up has not reached yet. One place, so the bar above the
  /// sheet and the `USED` line inside it can never disagree.
  func clockReading(_ spent: Int) -> Int { max(0, spent - clockHeld) }

  /// Finish the count-up now — the pull was skipped, or the sheet went away.
  func settleClock() {
    clockTask?.cancel()
    clockTask = nil
    clockHeld = 0
  }

  // MARK: - §5 · the live board

  /// Which *upcoming* alerts have shown their severity. Indices into the shift's
  /// queue, never into the remaining queue — a reveal survives the queue advancing.
  private(set) var revealedAlerts: Set<Int> = []
  private var boardTask: Task<Void, Never>?
  private var boardSeed: UInt64 = 0

  /// **The desk feels live** (§5). Every 25–40 s of real time, one alert the player
  /// has not reached yet shows what the tool made of it, with a ping and an ECG blip.
  ///
  /// Seeded by the shift, capped at the remaining queue, and started only while the
  /// player is investigating. Nothing about the queue's order or content moves —
  /// `boardRevealSchedule` shuffles *which* row lights up, not which alert is next.
  func startLiveBoard(from index: Int, count: Int, seed: UInt64) {
    let remaining = max(0, count - index - 1)
    guard remaining > 0 else { return stopLiveBoard() }
    guard boardTask == nil || boardSeed != seed else { return }
    stopLiveBoard()
    boardSeed = seed

    let schedule = Sequences.boardRevealSchedule(remaining: remaining, seed: seed)
    guard !schedule.isEmpty else { return }
    let start = ContinuousClock.now
    boardTask = Task { @MainActor [weak self] in
      for reveal in schedule {
        let due = start.advanced(by: .milliseconds(reveal.atMs))
        if ContinuousClock.now < due {
          try? await Task.sleep(until: due, tolerance: .zero, clock: ContinuousClock())
        }
        guard !Task.isCancelled, let self else { return }
        // `alertIndex` counts from the first *unworked* alert, so it is offset by the
        // queue position the schedule was built at.
        let slot = index + 1 + reveal.alertIndex
        guard slot < count else { continue }
        withAnimation(Motion.gated(Motion.beatArrive)) {
          _ = self.revealedAlerts.insert(slot)
        }
        self.pulse += 1
        // §5's reveal is §1's alert landing, one at a time: a ping in the ear and a
        // tap on the shoulder.
        self.cue(.select, .ping, reveal.alertIndex)
      }
    }
  }

  func stopLiveBoard() {
    boardTask?.cancel()
    boardTask = nil
  }

  // MARK: - §6 · Vale

  /// The interjection currently in the player's ear, or `nil`. One line, one card.
  private(set) var valeLine: String?
  private var valeFired: Set<String> = []
  private var valeTask: Task<Void, Never>?

  /// Fire an interjection **at most once per shift** (§6). `key` is the chrome key,
  /// which is also the once-per-shift identity — so a rule that would fire twice is
  /// silently the same line, not two.
  func interject(key: String, text: String) {
    guard valeFired.insert(key).inserted else { return }
    valeTask?.cancel()
    withAnimation(Motion.gated(Motion.messageCard)) { valeLine = text }
    valeTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(Motion.valeDwellSeconds))
      guard !Task.isCancelled else { return }
      self?.dismissVale()
    }
  }

  func dismissVale() {
    valeTask?.cancel()
    valeTask = nil
    withAnimation(Motion.gated(Motion.messageCard)) { valeLine = nil }
  }

  // MARK: - §7 · leads-to

  /// The unpulled key sources glowing right now.
  private(set) var worthALook: Set<String> = []
  private var nudged: Set<String> = []
  private var nudgeTask: Task<Void, Never>?
  /// A nudge waiting for the pull that earned it to finish streaming.
  private var pendingNudge: [String] = []

  /// **The board points at the next question** (§7).
  ///
  /// Called after a pull that landed a decisive or supporting finding, with the
  /// case's not-yet-pulled `keySourceIds`. Each row is nudged at most once per shift,
  /// so a player who pulls four sources is not walked through the case.
  ///
  /// It nudges without answering: the rule fires on **any** key source, including the
  /// ones that would refute the hunch the player is forming.
  /// **The nudge waits for the findings.**
  ///
  /// `PULL_SOURCE` is dispatched before the first log line — the session has to be
  /// truthful the moment the minutes are spent — so a nudge applied there glows and
  /// fades while the player is still watching a query pane two seconds from its
  /// results. Measured: by the time the sheet was dismissed the caption was long
  /// gone. So the rule is *decided* at the pull and *delivered* when the sequence
  /// that pull started reaches its end.
  func nudge(_ sourceIDs: [String]) {
    let fresh = sourceIDs.filter { nudged.insert($0).inserted }
    guard !fresh.isEmpty else { return }
    pendingNudge = fresh
    nudgeTask?.cancel()
    // If no sequence takes the clock in the next turn — a pre-pulled kit source, a
    // Reduce-Motion pull that collapsed instantly — deliver it anyway.
    nudgeTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(200), tolerance: .zero)
      guard !Task.isCancelled, let self, !self.isPlaying else { return }
      self.flushNudge()
    }
  }

  /// Light the rows the pull pointed at.
  private func flushNudge() {
    let ids = pendingNudge
    pendingNudge = []
    guard !ids.isEmpty else { return }
    nudgeTask?.cancel()
    withAnimation(Motion.gated(Motion.worthALookGlow)) { worthALook = Set(ids) }
    nudgeTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(Motion.worthALookLifeMs), tolerance: .zero)
      guard !Task.isCancelled else { return }
      self?.clearNudge()
    }
  }

  /// The player touched a row: the nudge has been answered, whichever way.
  func clearNudge() {
    nudgeTask?.cancel()
    nudgeTask = nil
    pendingNudge = []
    guard !worthALook.isEmpty else { return }
    withAnimation(Motion.gated(Motion.worthALookGlow)) { worthALook = [] }
  }

  // MARK: - §5 · fear text arrives with the first delta

  /// Meter keys whose caption has been typed in. A caption arrives the first time
  /// that meter moves and then stays, which is what makes it a consequence rather
  /// than a label (§5, §10).
  private(set) var fearRevealed: Set<String> = []

  /// Record the meter levels a screen is about to draw and reveal the caption of any
  /// that moved since the last look. Returns the keys that arrived *now*, so a screen
  /// can type them in rather than fading them.
  @discardableResult
  func noteMeters(breach: Int, noise: Int) -> Set<String> {
    var arrivedNow: Set<String> = []
    if let last = lastBreach, last != breach, fearRevealed.insert(Director.breachKey).inserted {
      arrivedNow.insert(Director.breachKey)
    }
    if let last = lastNoise, last != noise, fearRevealed.insert(Director.noiseKey).inserted {
      arrivedNow.insert(Director.noiseKey)
    }
    lastBreach = breach
    lastNoise = noise
    return arrivedNow
  }

  static let breachKey = "breach"
  static let noiseKey = "noise"
  private var lastBreach: Int?
  private var lastNoise: Int?

  // MARK: - Shift scope

  /// A new board: everything above is per-shift, and none of it survives one.
  func resetForShift() {
    cancel()
    stopLiveBoard()
    valeTask?.cancel()
    valeTask = nil
    played = []
    endStates = [:]
    revealedAlerts = []
    pulse = 0
    boardSeed = 0
    settleClock()
    valeLine = nil
    valeFired = []
    worthALook = []
    nudged = []
    pendingNudge = []
    nudgeTask?.cancel()
    nudgeTask = nil
    fearRevealed = []
    lastBreach = nil
    lastNoise = nil
  }

  // MARK: - The names of the four sequences

  /// **Run ids live here, not in the screens.**
  ///
  /// A run id is an address — it is never drawn — but S1 cannot tell an address from
  /// a sentence, and `"arrival:\(case.id)"` written inside `Screens/` is a string
  /// literal containing letters, which the release guard rightly refuses. Building
  /// them here keeps the guard honest *and* puts the vocabulary of the feel pass in
  /// one file: four sequences, four names, and a compiler error if a screen invents a
  /// fifth.
  static func handoverID(shift: String) -> String { "handover:" + shift }
  static func arrivalID(case caseID: String) -> String { "arrival:" + caseID }
  static func pullID(case caseID: String, source: String) -> String {
    "pull:" + caseID + "/" + source
  }
  static func callID(case caseID: String) -> String { "call:" + caseID }

  // MARK: - Pure policy (the parts a test can hold still)

  /// **The pull's seed** (§4): the case and the source, so two sources never stream
  /// in step and the same pull reads the same every time it is replayed.
  static func pullSeed(caseID: String, sourceID: String) -> UInt64 {
    Sequences.seed("\(caseID)/\(sourceID)")
  }

  /// The board's seed. One per shift, so re-entering a case does not re-roll it —
  /// and a daily board's id already carries its date (DV-6), so two days of dailies
  /// are two different boards without a second field.
  static func boardSeed(shiftID: String) -> UInt64 {
    Sequences.seed(shiftID)
  }

  /// The `{n}` a log line quotes — deterministic, four digits, and different on every
  /// line of the same pane.
  static func logNumber(caseID: String, sourceID: String, line: Int) -> Int {
    Int(Sequences.seed("\(caseID)/\(sourceID)/n\(line)") % 8000) + 1000
  }

  /// **§7's rule, as a function.** The unpulled key sources of a case, after a pull
  /// that landed something that matters.
  ///
  /// `nil` — no nudge at all — when the pull surfaced only neutral or noise weight:
  /// §7 fires on a *decisive or supporting* finding, and a pane of noise has not
  /// earned the right to point anywhere.
  static func leadsTo(
    _ socCase: SocCase, justPulled sourceID: String, queried: [String]
  ) -> [String] {
    let landed = socCase.findings(from: sourceID)
    let matters = landed.contains { $0.weight == .decisive || $0.weight == .supporting }
    guard matters else { return [] }
    return socCase.keySourceIds.filter { !queried.contains($0) }
  }

  /// **§4's decisive tell.** Whether a pull's findings include one that decides the
  /// case — the extra ECG beat, and nothing the player can read as a weight badge.
  static func hasDecisive(_ socCase: SocCase, from sourceID: String) -> Bool {
    socCase.findings(from: sourceID).contains { $0.weight == .decisive }
  }

  /// The asset as a log line addresses it: `FIN-WS-04`, not
  /// `FIN-WS-04 · user jdoe (Finance)`.
  ///
  /// The first whitespace-delimited token, which is the host every exported asset
  /// leads with — and for `soc-phish-harvest`, whose asset is one unbroken 33-character
  /// sender token, it is the whole string, which is correct: there is nothing to trim.
  /// Splitting on the middle dot instead would work today and break on the first asset
  /// authored without one.
  static func host(of asset: String) -> String {
    asset.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? asset
  }
}

