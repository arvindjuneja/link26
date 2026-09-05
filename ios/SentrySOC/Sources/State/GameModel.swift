import Foundation
import OSLog
import SwiftUI
import SentryCore

/// The state container (§4.1). One per app, held by `SentrySOCApp`.
///
/// **`send(_:)` is the single entry point.** A view expresses an intent; the pure
/// reducer decides what the session becomes and what has to happen; `EffectRunner`
/// makes it happen. Views never construct a `CallGrade` (D8 makes it a compile
/// error), never touch a meter, never touch storage and never touch Core Haptics.
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
  private let registry: ScreenRegistry
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
  func send(_ action: SocAction) {
    let (next, effects) = reduce(session, action, content: content, career: career)
    withAnimation(Motion.gated(Motion.screenPush)) { session = next }
    runner.run(effects)
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

  /// Buy a kit item (C9's Kit sheet). The debit is `CareerRules.buyKit` — a pure
  /// function of the current career — and cannot live in the reducer, which only
  /// ever *reads* the career. `.buy` then schedules the write and the cue.
  ///
  /// `buyKit` is itself the affordability guard: it returns the career unchanged
  /// when the item is owned or unaffordable.
  func buy(_ item: KitItem) {
    career = rules.buyKit(career, item)
    send(.buy(item.id))
  }

  /// A SwiftUI `Toggle` binds to this, so even a switch goes through `send(_:)`.
  func settingBinding(_ key: SettingKey) -> Binding<Bool> {
    Binding(
      get: { [weak self] in self?.settings[key] ?? false },
      set: { [weak self] value in self?.send(.setSetting(key, value)) })
  }

  func acknowledgeSaveNotice() { saveWasCorrupt = false }

  /// Whether the Shift-1 coach marks draw (C8's `CoachBubble`, S4): the switch is on
  /// and the player has not yet filed a call. The flag is written by the reducer at
  /// the first `MAKE_CALL` — never by a view (G19).
  var coachIsActive: Bool { settings.coaching && !hasSeenOnboarding }

  /// `scenePhase` moved. Backgrounding flushes the coalesced session write, because
  /// "in 250 ms" assumes the app is still alive in 250 ms.
  func scenePhaseChanged(to phase: ScenePhase) {
    guard phase != .active else { return }
    runner.flushPendingWrites()
    registry.haptics.setHeartbeat(nil)          // never beat in the background (§4.4)
  }

  // MARK: - Settlement

  /// The 16:00 chain, lifted from `SocConsole.tsx:251-270`: `scoreShift →
  /// awardForShift → unlock diff → HandlerEvent → persistCareer → clearSession`,
  /// plus the Appendix A G7 daily stamp.
  ///
  /// Every computation is a `SentryCore` call. What this method owns is the *order*
  /// and the one policy the engine cannot know: whether today's daily board has
  /// already paid its standing.
  ///
  /// `persistCareer` and `clearSession` are the reducer's next two effects, and the
  /// runner performs them in order — so the career this writes is the settled one.
  private func settleShift() {
    // The reducer emits `.settleShift` on the transition into `.complete` and
    // nowhere else, so a shift settles exactly once. If that ever stops being true,
    // this is where the double award would appear.
    guard session.phase == .complete, let shift = session.shift else {
      Self.log.error("settleShift with no completed board — nothing was awarded")
      return
    }

    let score = engine.scoreShift(shift)
    let today = DailyCalendar.isoDay(Date())
    let isDaily = definition(of: shift.shiftId)?.kind == .daily
    // G7: the daily board pays cash every run and standing once a calendar day.
    let standingAlreadyPaid = isDaily && career.dailyDoneOn == today

    let reward = rules.awardForShift(career, score)
    var settled = reward.state
    var rankUp = reward.rankUp
    if standingAlreadyPaid {
      settled.standing = career.standing
      rankUp = nil
    }

    // The diff is taken across the award, so a shift that opened on this payout is
    // announced exactly once.
    let unlocked = content.shifts
      .filter { !rules.isUnlocked(career, $0) && rules.isUnlocked(settled, $0) }
      .map { UnlockedShift(id: $0.id, label: $0.label) }

    let type: HandlerEventType =
      switch score.grade {
      case .clean: .shiftClean
      case .rough: .shiftRough
      case .breached: .shiftBreached
      }

    career = settled
    if isDaily { career.dailyDoneOn = today }
    refreshInbox(HandlerEvent(type: type, rankUp: rankUp, unlocked: unlocked))

    Self.log.notice(
      "settled \(shift.shiftId, privacy: .public): grade \(score.grade.rawValue, privacy: .public)")
  }

  /// The hub's inbox (§2.3). Rebuilt rather than appended to: it is a pure function
  /// of the career and the last thing that happened, so there is no list to keep.
  ///
  /// `.iOS` drops the cross-seat nudge **after** the four-message cap (B1/S3), which
  /// is why a blue-only inbox is sometimes shorter than four.
  private func refreshInbox(_ event: HandlerEvent = HandlerEvent()) {
    inbox = voice.inboxFor(career, event, features: .iOS)
  }

  /// A campaign board comes from `shiftsByID`; the daily board is built on demand
  /// and is not in it (S9).
  private func definition(of shiftID: String) -> ShiftDef? {
    if let campaign = content.shift(shiftID) { return campaign }
    let today = content.dailyShift(on: Date())
    return today.id == shiftID ? today : nil
  }

  private func applyFlag(_ key: String, _ value: Bool) {
    if let setting = SettingKey(rawValue: key) { settings[setting] = value }
    if key == SentryFlagKey.onboarding { hasSeenOnboarding = value }
  }

  // MARK: - QA and DEBUG entry points

  #if DEBUG
    /// Acceptance #8 — the entry that makes the loop reachable before C9's hub
    /// exists. Shift 1 unlocks at standing 0, so it always starts.
    func debugStartFirstShift() {
      guard let first = content.shifts.first else { return }
      send(.startShift(first.id))
    }

    var debugPerformedEffects: [Effect] { runner.performed }
  #endif

  #if SENTRY_QA
    /// `-SentryQAScreen <name>` (D19). Applied once, after hydration.
    func applyQAJump(_ destination: QAJump.Destination) {
      if let shiftID = destination.shiftID { send(.startShift(shiftID)) }
      session.phase = destination.phase
      session.view = destination.view
    }
  #endif
}
