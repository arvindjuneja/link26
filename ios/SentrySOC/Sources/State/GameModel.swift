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
    registry: ScreenRegistry = .shared
  ) {
    self.content = content
    self.engine = SOCEngine(content: content)
    self.rules = CareerRules(content: content)
    self.voice = HandlerVoice(content: content)
    self.save = save
    self.flags = flags
    self.registry = registry

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
      save: save, flags: flags, registry: registry,
      context: EffectRunner.Context(
        snapshot: { [weak self] in self.flatMap { SessionSnapshot($0.session) } },
        career: { [weak self] in self?.career ?? .initial },
        hapticsEnabled: { [weak self] in self?.settings.haptics ?? false },
        settle: { [weak self] in self?.settleShift() },
        markDailyDone: { [weak self] day in self?.career.dailyDoneOn = day },
        applyFlag: { [weak self] key, value in self?.applyFlag(key, value) }))

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
    withAnimation(Motion.gated(Motion.screenPush)) { session = next }
    applyCareerMutation(for: action)
    runner.run(effects)
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
  func feel(_ cue: SocCue) {
    guard settings.haptics else { return }
    registry.haptics.play(cue)
  }

  /// Whether the Shift-1 coach marks draw (C8's `CoachBubble`, S4): the switch is on
  /// and the player has not yet filed a call. The flag is written by the reducer at
  /// the first `MAKE_CALL` — never by a view (G19). *Which* step is showing is
  /// `session.currentCoachStep(content)`.
  var coachIsActive: Bool { settings.coaching && !hasSeenOnboarding }

  /// `scenePhase` moved. Backgrounding flushes the coalesced session write, because
  /// "in 250 ms" assumes the app is still alive in 250 ms.
  func scenePhaseChanged(to phase: ScenePhase) {
    guard phase != .active else { return }
    runner.flushPendingWrites()
    registry.haptics.setHeartbeat(nil)          // never beat in the background (§4.4)
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
