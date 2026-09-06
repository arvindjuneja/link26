import Foundation
import OSLog
import SwiftUI
import SentryCore

/// The state container (§4.1). One per app, held by `SentrySOCApp`.
///
/// **`send(_:)` is the single entry point.** A view expresses an intent; the pure
/// reducer in `SentryCore` decides what the session becomes and what has to happen;
/// `EffectRunner` makes it happen. Views never construct a `CallGrade` (D8 makes it
/// a compile error), never touch a meter, never touch storage and never touch Core
/// Haptics.
///
/// **Hydration is synchronous, here, before the first frame** (§4.3). The save is a
/// ~4 KB read, so there is nothing to gain by deferring it — and deferring it is
/// exactly how the web build lost saves (R6). Natively there is no race to lose.
@Observable @MainActor final class GameModel {

  // MARK: - Content and rules

  let content: ContentPack
  /// C3's grader and shift arithmetic. Every meter value and every grade in this app
  /// comes out of here — nothing in `Sources/` does arithmetic on `breachRisk`,
  /// `noise`, `cash` or `standing` (D8).
  let engine: SOCEngine
  /// C4's ladder, wallet and unlock gate.
  let rules: CareerRules
  /// C4's handler. Builds the hub's inbox from career state plus what just happened.
  let voice: HandlerVoice

  // MARK: - State

  private(set) var session: SessionState
  private(set) var career: CareerState
  private(set) var inbox: [HandlerMessage] = []
  private(set) var settings: SettingsState

  /// Which half of the case screen is showing (`PlayFocus`). Presentation, not game
  /// state — the reducer owns what the game is doing, and a tab is not that — but it
  /// belongs to *a model* rather than to the process (P1-6).
  let play = PlayFocus()

  /// **The feel pass** (F2b, `FEEL.md`). Plays §1/§2/§4/§8, runs §5's live board and
  /// holds §6's and §7's once-per-shift state.
  ///
  /// It hangs off the model rather than off a screen for the same reason `PlayFocus`
  /// does: a sequence outlives the view that started it (an arrival survives a sheet
  /// opening over it) and a once-per-shift rule outlives the case that fired it.
  /// Nothing it holds is game state — none of it reaches `scoreShift`, and a save
  /// carries none of it.
  let director = Director()

  /// The Shift-1 coach has been through once. Mirrored out of `UserDefaults` into
  /// observed state so a view redraws when the flag flips mid-session; `Flags` stays
  /// the storage.
  private(set) var hasSeenOnboarding: Bool

  /// The save found on disk but not yet entered — the hub's Resume card (§2.1).
  /// A snapshot is offered, never auto-entered.
  private(set) var resumable: SessionSnapshot?

  /// One-shot notice for Settings: the career file could not be read and has been
  /// set aside. Shown once, then acknowledged.
  private(set) var saveWasCorrupt: Bool

  // MARK: - Services

  private let save: SaveStore
  private let flags: Flags
  /// The ear (F2a). Its three gates — the replay mute and the two Settings switches
  /// — are `Feel`'s; this model only says *when*.
  let sound: SoundService
  /// The two sound switches, and the replay mute (F2a, `FEEL.md` §9). Exposed so
  /// `SettingsView` binds to the same instance the service reads.
  let feelSettings: Feel
  /// Where the screens and the haptics sink are bound (B6). Exposed because
  /// `PhaseHost` resolves screens through *this model's* registry rather than
  /// reaching for the singleton — which is what lets a test or a preview install its
  /// own factories without touching global state.
  let registry: ScreenRegistry
  /// Implicitly unwrapped for two-phase init and nothing else: the runner's `Context`
  /// closures capture `self` weakly, so it cannot be built until every stored
  /// property above it is. It is assigned before `init` returns and is never `nil`
  /// again for the life of the model.
  private var runner: EffectRunner!

  private static let log = Logger(subsystem: "pl.oumm.sentry.soc", category: "GameModel")

  // MARK: - Init

  init(
    content: ContentPack = .bundled,
    save: SaveStore = SaveStore(),
    flags: Flags = Flags(),
    registry: ScreenRegistry = .shared,
    sound: SoundService = .shared,
    feelSettings: Feel = .shared
  ) {
    self.content = content
    self.engine = SOCEngine(content: content)
    self.rules = CareerRules(content: content)
    self.voice = HandlerVoice(content: content)
    self.save = save
    self.flags = flags
    self.registry = registry
    self.sound = sound
    self.feelSettings = feelSettings

    let hydration = save.hydrate()            // synchronous, nonisolated, ~4 KB
    self.career = hydration.career
    self.resumable = hydration.session
    self.saveWasCorrupt = hydration.careerWasCorrupt
    self.settings = flags.settings
    self.hasSeenOnboarding = flags.hasSeenOnboarding

    // The one piece of session the reducer cannot decide, because it cannot read
    // `UserDefaults`: whether the disclaimer gate is still closed (§2.1's HYDRATE
    // row). It is *constructed* here, not mutated — `send(_:)` owns every move after
    // this line.
    var start = SessionState()
    if !flags.hasSeenFirstRun { start.view = .firstRun }
    self.session = start

    self.runner = EffectRunner(
      save: save, flags: flags, registry: registry, sound: sound,
      context: EffectRunner.Context(
        snapshot: { [weak self] in self.flatMap { SessionSnapshot($0.session) } },
        career: { [weak self] in self?.career ?? .initial },
        hapticsEnabled: { [weak self] in self?.cuesAreLive ?? false },
        settle: { [weak self] in self?.settleShift() },
        markDailyDone: { [weak self] day in self?.career.dailyDoneOn = day },
        applyFlag: { [weak self] key, value in self?.applyFlag(key, value) }))

    // The Director's two channels are this model's one call site, so a sequence beat
    // and a reducer effect reach the ear and the hand through exactly the same gate
    // (F2b). Weak, because the model owns the director and not the other way round.
    director.cue = { [weak self] haptic, sound, variant in
      self?.feel(haptic: haptic, sound: sound, variant: variant)
    }

    refreshInbox()                            // the hub has an inbox on a cold launch
    send(.hydrate)
  }

  // MARK: - The single entry point

  /// A view's intent, in. The session out, animated once, and the effects run once.
  ///
  /// The order is load-bearing: reduce (pure) → adopt the session → apply the one
  /// career mutation the reducer is not allowed to make → run the effects. A
  /// `.persistCareer` therefore writes the career *after* the purchase it is paying
  /// for, and never the one before it.
  func send(_ action: SocAction) {
    let (next, effects) = reduce(session, action, content: content, career: career)
    let wasOpen = session.phase != .hub
    let wasBoard = session.shift?.shiftId
    let wasInvestigating = session.phase == .investigating
    withAnimation(Motion.gated(Motion.screenPush)) { session = next }
    applyCareerMutation(for: action)
    directorFollow(
      wasBoard: wasBoard, wasInvestigating: wasInvestigating, action: action)
    // The room tone is a **state**, not a cue (`FEEL.md` §9): it runs while a shift
    // is open and stops at the desk. Driven from here rather than from a screen
    // because a sheet, a debrief and a summary are all "the shift is still open" and
    // no one of them owns the answer.
    if wasOpen != (next.phase != .hub) { sound.setShiftOpen(next.phase != .hub) }
    runner.run(effects)
  }

  /// **What the feel pass does after a transition** (F2b).
  ///
  /// Three rules, and all three are about *scope* rather than about the game:
  ///
  /// 1. A new board resets everything the Director holds — §6's interjections and
  ///    §7's nudges are "at most once per **shift**", and a shift is what changed.
  /// 2. §5's live board runs only while the player is investigating; leaving the
  ///    phase stops it, because a ping on the debrief is a lie about where the
  ///    pressure is.
  /// 3. A pull is what §7 hangs off, and the case in hand is the only thing that
  ///    knows which of its key sources are still unread.
  ///
  /// It is called from `send(_:)` and nowhere else, so a sequence can never be armed
  /// by a view that happens to redraw.
  private func directorFollow(wasBoard: String?, wasInvestigating: Bool, action: SocAction) {
    let board = session.shift?.shiftId
    if board != wasBoard { director.resetForShift() }

    let investigating = session.phase == .investigating
    if let shift = session.shift {
      // §5's fear captions. The reveal is a *delta*, so the first call seeds the
      // baseline and reveals nothing; every move after that types its caption in.
      director.noteMeters(breach: shift.breachRisk, noise: shift.noise)
      if investigating {
        director.startLiveBoard(
          from: shift.index, count: shift.caseIds.count,
          seed: Director.boardSeed(shiftID: shift.shiftId))
      }
    }
    if !investigating, wasInvestigating { director.stopLiveBoard() }

    switch action {
    case .pullSource(let sourceID):
      guard let socCase = session.currentCase(content) else { return }
      // §7 — the pull that just landed, and the key sources it has not answered.
      director.nudge(
        Director.leadsTo(socCase, justPulled: sourceID, queried: session.queried))
      // §6 — Vale's first-pull line, shift 1 only, once.
      if isFirstShift, session.queried.count == 1 {
        director.interject(
          key: FeelCopyKey.valeFirstPull,
          text: content.copy.chromeText(FeelCopyKey.valeFirstPull))
      }

    case .openView(.call):
      // §6's second interjection: the call sheet opened on one card, and that card is
      // noise. It is an *opinion*, not a block — the sheet is already open and the
      // hold-to-file works — which is the whole difference between a shift lead and a
      // validation rule.
      let board = session.revealedEvidence(content)
      if board.count == 1, board.allSatisfy({ $0.weight == .noise }) {
        director.interject(
          key: FeelCopyKey.valeThinCall,
          text: content.copy.chromeText(FeelCopyKey.valeThinCall))
      }

    default: break
    }
  }

  /// **The band the desk feels like** (`FEEL.md` §5): the worse of the engine's status
  /// and the clock's.
  ///
  /// `Sequences.timeStatus` maps shift-minutes spent against the budget; `feltStatus`
  /// is `max` of that and what the meters say. It drives the ECG, the band word and
  /// the heartbeat — and **nothing else**. `scoreShift` never sees it: the founder's
  /// ruling is no hard timer, so the pressure is felt and not scored, and this
  /// property is the whole of "felt".
  var feltStatus: TraceStatus {
    guard session.phase == .investigating, let shift = session.shift else {
      return session.status
    }
    let used = shift.timeUsed + session.timeSpentOnCurrentCase(content)
    return Sequences.feltStatus(
      engine: session.status,
      time: Sequences.timeStatus(used: used, budget: shift.timeBudget))
  }

  /// Whether the board in hand is the first on the ladder — the one shift the coach
  /// and §6's first-pull line belong to. Derived from the content's own order, never
  /// from an id spelled in Swift.
  var isFirstShift: Bool {
    session.shift?.shiftId == content.shifts.first?.id
  }

  /// The wallet moves in exactly one place outside the settlement, and this is it.
  ///
  /// `CareerRules.buyKit` is the debit **and** the affordability guard: it returns
  /// the career untouched when the item is owned or unaffordable, so comparing
  /// before with after is the whole decision (R9). The reducer made the same
  /// comparison on the same career one line earlier, which is how the cue and the
  /// write agree without either side being told.
  private func applyCareerMutation(for action: SocAction) {
    guard case .buy(let itemID) = action,
          let item = content.kit.first(where: { $0.id == itemID })
    else { return }
    let purchased = rules.buyKit(career, item)
    guard purchased != career else {
      Self.log.notice("refused kit \(itemID, privacy: .public) — owned or unaffordable")
      return
    }
    career = purchased
  }

  // MARK: - Intent

  /// The hub's Resume card. Entering the snapshot is always the player's choice.
  ///
  /// The snapshot travels **inside the action**: nothing here assigns `session`, so
  /// `send(_:)` really is the only thing that moves it.
  func resume() {
    guard let resumable else { return }
    self.resumable = nil
    send(.resume(resumable.session))
  }

  /// Throw the snapshot away without entering it. `.abandon` is exactly this
  /// transition — hub, no board, snapshot deleted — so it goes through the reducer
  /// rather than reaching for the store.
  func discardResumable() {
    guard resumable != nil else { return }
    resumable = nil
    send(.abandon)
  }

  /// Buy a kit item (C9's Kit sheet). One intent, one action: the reducer decides
  /// whether it takes, `applyCareerMutation(for:)` performs the debit, and a refusal
  /// costs a `denied` cue and writes nothing at all.
  func buy(_ item: KitItem) {
    send(.buy(item.id))
  }

  /// **Reset career** (§5.11) — all of it, in one place, through this model (P1-2).
  ///
  /// What shipped before did half the job from a view: it sent `.abandon` and then
  /// built a **second** `SaveStore` to write `CareerState.initial`. Two defects, one
  /// cause — nothing outside the model can reach the model's career or its store:
  ///
  /// 1. The file on disk went to zero while `GameModel.career` kept the old wallet.
  ///    The hub still read `⬢ 40 ¢ 650` until the next cold launch, and the next
  ///    `persistCareer` (a purchase, a settled board) wrote the *old* career straight
  ///    back over the reset — so the reset could be silently undone by playing on.
  /// 2. The second store pointed at the default directory whatever directory this
  ///    model was given, so a test or a preview wiped the player's real save, and its
  ///    writes raced the ones going through `EffectRunner`'s serial chain.
  ///
  /// The order below is the whole of it: adopt the fresh career **first** so the
  /// `.persistCareer` that follows writes the reset one, drop the snapshot the hub is
  /// offering, then let the machine do the rest — `.abandon` is already exactly "hub,
  /// no board, snapshot deleted" and already fires the `destructive` cue §2.15 files
  /// under "Reset career confirmed".
  ///
  /// **The flags.** `sentry.firstRun.v1` is deliberately left alone: the fiction
  /// disclaimer was acknowledged by a *person*, and this device is still that person —
  /// re-gating them behind it would be a nag, not a reset. The two that describe the
  /// *career* are cleared: the Shift-1 coach has not run for this career
  /// (`sentry.onboarding.v1` → false), and coaching goes back to its registered
  /// default so a player who switched it off and then asked for a fresh desk gets the
  /// fresh desk they asked for.
  func resetCareer() {
    career = .initial
    resumable = nil
    saveWasCorrupt = false
    refreshInbox()
    send(.abandon)
    // `EffectRunner` is still the only interpreter — this is the model handing it a
    // list, exactly as `send(_:)` does, and `.persistCareer` reads the career through
    // the same `Context` closure and writes through the same actor and the same serial
    // chain as every other write in the app.
    runner.run([
      .persistCareer,
      .setFlag(SentryFlagKey.onboarding, false),
      .setFlag(SettingKey.coaching.rawValue, true),
    ])
    Self.log.notice("career reset — save rewritten, snapshot cleared, coach re-armed")
  }

  /// A SwiftUI `Toggle` binds to this, so even a switch goes through `send(_:)`.
  func settingBinding(_ key: SettingKey) -> Binding<Bool> {
    Binding(
      get: { [weak self] in self?.settings[key] ?? false },
      set: { [weak self] value in self?.send(.setSetting(key, value)) })
  }

  func acknowledgeSaveNotice() { saveWasCorrupt = false }

  /// The cues a **screen** owns, because only the screen knows when its animation
  /// reaches them: the debrief's verdict on mount, `breachThud` as the meter sweeps,
  /// each finding as it lands, the payout's `commitSoft` at the end of the count-up
  /// (§4.4, §5.5, §5.8, §5.9).
  ///
  /// It is still not the view firing a haptic: the gate and the sink are here, so
  /// "haptics off" is honoured in one place and Core Haptics is never imported by a
  /// screen.
  /// `variant` picks the pitch for the cues that have several — the card's index,
  /// the alert's slot (`FEEL.md` §1, §4). It reaches the ear only; a haptic has no
  /// pitch.
  func feel(_ cue: SocCue, variant: Int = 0) {
    feel(haptic: cue, sound: cue, variant: variant)
  }

  /// **The two channels, addressed separately** (F2b).
  ///
  /// A `Beat` names both — `cue` is what the hand feels and `sound` is what the ear
  /// hears — and they are frequently *different*: §1's alert landing is a `select`
  /// tap under a `ping`, and §4's log line is a `tick` nobody feels. Collapsing them
  /// into one cue, which is what a single-`SocCue` entry point forces, replaced the
  /// tap with a second copy of the ping and lost the row §9 writes as `—`.
  ///
  /// The ear is fired first and **not** behind `cuesAreLive` — that gate is the
  /// *Haptics* switch, and Sound is a switch of its own (F2a). `SoundService` carries
  /// the replay mute and both sound toggles itself, so each channel is silenced by
  /// the thing a player actually asked to silence.
  func feel(haptic: SocCue?, sound heard: SocCue?, variant: Int = 0) {
    if let heard {
      sound.play(heard, variant: variant)
      if heard == .file { sound.duckRoomTone(for: .milliseconds(Sequences.fileDuckMs)) }
    }
    guard cuesAreLive, let haptic else { return }
    registry.haptics.play(haptic)
  }

  /// **Whether a cue may be felt right now** — the one gate, read by all three
  /// callers: `feel(_:)` above, `EffectRunner`'s `.haptic` arm, and the heartbeat
  /// driver.
  ///
  /// Two conditions. The Settings switch is the player's. `isReplaying` is the QA
  /// jump's (P1-8): a jump reaches its screen by *playing* the board through the
  /// reducer — start, begin, pull, call, next — and every one of those transitions
  /// emits its cue, so a single `-SentryQAScreen summary` fired a dozen taps and a
  /// file-stamp into the player's hand in under a second, and pushed a real HUNT
  /// heartbeat through a phase the player never saw. A replay is a fast-forward, not
  /// a performance.
  var cuesAreLive: Bool { settings.haptics && !isReplaying }

  /// True only while `applyQAJump` is replaying its action list. Not `#if SENTRY_QA`:
  /// the gate above should have one shape in every build, and in a build with no QA
  /// jumps this is a `let false` the optimiser folds away.
  private(set) var isReplaying = false

  /// Whether the Shift-1 coach marks draw (C8's `CoachBubble`, S4): the switch is on
  /// and the player has not yet filed a call. The flag is written by the reducer at
  /// the first `MAKE_CALL` — never by a view (G19). *Which* step is showing is
  /// `session.currentCoachStep(content)`.
  var coachIsActive: Bool { settings.coaching && !hasSeenOnboarding }

  /// `scenePhase` moved. Backgrounding flushes the coalesced session write, because
  /// "in 250 ms" assumes the app is still alive in 250 ms.
  func scenePhaseChanged(to phase: ScenePhase) {
    guard phase != .active else {
      // Back on the glass: the `.ambient` session was deactivated on the way out and
      // took the engine with it, so the tone has to be asked for again — and only if
      // the shift it belongs to is still open (F2a).
      sound.setForeground(true)
      return
    }
    runner.flushPendingWrites()
    registry.haptics.setHeartbeat(nil)          // never beat in the background (§4.4)
    sound.setForeground(false)                  // and never a room tone either
  }

  // MARK: - Settlement

  /// The 16:00 chain — **applied**, not computed.
  ///
  /// `scoreShift → awardForShift → unlock diff` all happened inside the reducer, on
  /// the career it was handed, and arrived as `session.settlement` (`ShiftSettlement`).
  /// What is left here is the part that is not arithmetic: adopting the settled
  /// career and telling the handler what happened. A second award is therefore not a
  /// bug this method can have — there is nothing here to award twice.
  ///
  /// `persistCareer` and `clearSession` are the reducer's next two effects, and the
  /// runner performs them in order — so the career this adopts is the one written.
  private func settleShift() {
    guard session.phase == .complete, let settlement = session.settlement else {
      Self.log.error("settleShift with no settled board — nothing was awarded")
      return
    }

    career = settlement.reward.state
    refreshInbox(settlement.event)

    Self.log.notice(
      """
      settled \(settlement.shiftId, privacy: .public): \
      grade \(settlement.score.grade.rawValue, privacy: .public), \
      +\(settlement.reward.cashGain, privacy: .public)¢ \
      +\(settlement.reward.standingGain, privacy: .public)⬢
      """)
  }

  /// The hub's inbox (§2.3). Rebuilt rather than appended to: it is a pure function
  /// of the career and the last thing that happened, so there is no list to keep.
  ///
  /// `.iOS` is the blue-only selection (R1): the cross-seat nudge is never emitted
  /// and the two cross-seat beats are re-voiced as Vale, before the four-message cap.
  private func refreshInbox(_ event: HandlerEvent = HandlerEvent()) {
    inbox = voice.inboxFor(career, event, features: .iOS)
  }

  private func applyFlag(_ key: String, _ value: Bool) {
    if let setting = SettingKey(rawValue: key) { settings[setting] = value }
    if key == SentryFlagKey.onboarding { hasSeenOnboarding = value }
  }

  // MARK: - QA and DEBUG entry points

  #if DEBUG
    /// C6 acceptance #8 — the entry that makes the loop reachable before C9's hub
    /// exists. Shift 1 unlocks at standing 0, so it always starts.
    func debugStartFirstShift() {
      guard let first = content.shifts.first else { return }
      send(.startShift(first.id))
    }

    var debugPerformedEffects: [Effect] { runner.performed }
  #endif

  #if SENTRY_QA
    /// `-SentryQAScreen <name>` (D19), **played rather than posed**.
    ///
    /// Every jump is a list of the seventeen actions, so a QA screenshot is of a
    /// session the reducer actually produced: a debrief jump has a real graded call,
    /// a summary jump has a real settlement, and a screen that reads a field the
    /// machine never fills fails here rather than on a reviewer's device.
    func applyQAJump(_ destination: QAJump.Destination) {
      // Muted for the replay (P1-8) — see `cuesAreLive`. `defer` rather than a flag
      // reset at the bottom: `send(_:)` can trap in DEBUG on a corrupt bundle, and a
      // jump that fails must not leave the app permanently silent.
      isReplaying = true
      // The same mute on the sound side (F2a): `SoundService` reads `Feel`, not this
      // model, so the flag has to be set where the replay is — otherwise a jump
      // fires a dozen ticks, a file thud and a verdict chord into a screenshot run.
      feelSettings.replayMuted = true
      defer {
        isReplaying = false
        feelSettings.replayMuted = false
      }
      for action in destination.actions { send(action) }
      if session.phase != destination.phase || session.view != destination.view {
        // Not an assertion failure: `milestone` legitimately lands on the hub when
        // the played board earned no rank-up, and that is worth a log line, not a trap.
        Self.log.notice(
          """
          QA jump \(destination.name, privacy: .public) asked for \
          \(destination.phase.name, privacy: .public) and reached \
          \(self.session.phase.name, privacy: .public)
          """)
      }
    }
  #endif
}
