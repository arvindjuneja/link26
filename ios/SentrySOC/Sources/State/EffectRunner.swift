import Foundation
import OSLog
import SentryCore

/// **The only interpreter of `Effect`** (§4.1).
///
/// The reducer is pure and returns a list of things to do; this is the one place
/// they get done. Views never touch storage, never fire a haptic and never write a
/// flag — which is what makes "the debrief buzzed twice" a testable property
/// instead of a bug report, and why `EffectScheduleTests` exists.
///
/// Everything it needs from the model arrives through `Context` closures rather
/// than a reference, so the runner can be exercised against a temporary directory
/// and a recording context with no `GameModel` in sight.
@MainActor final class EffectRunner {

  /// What the runner needs from whoever owns the state.
  struct Context {
    /// The current shift, if there is one worth writing down.
    var snapshot: () -> SessionSnapshot?
    var career: () -> CareerState
    /// The Settings toggle. Reduce Motion is deliberately NOT consulted (D18).
    var hapticsEnabled: () -> Bool
    /// Adopt `session.settlement` — the career it computed, and the inbox event it
    /// carries. The arithmetic already happened, in the reducer.
    var settle: () -> Void
    /// Stamp `career.dailyDoneOn` (Appendix A G7).
    var markDailyDone: (String) -> Void
    /// Mirror a flag write back into the in-memory `SettingsState`.
    var applyFlag: (String, Bool) -> Void

    static let noop = Context(
      snapshot: { nil }, career: { .initial }, hapticsEnabled: { false },
      settle: {}, markDailyDone: { _ in }, applyFlag: { _, _ in })
  }

  private let save: SaveStore
  private let flags: Flags
  private let registry: ScreenRegistry
  private let context: Context
  /// §4.3: session writes coalesce to ≤1 per 250 ms. Injectable so a test does not
  /// have to sleep a quarter of a second to see a file.
  private let coalesceWindow: Duration
  private var pendingSessionWrite: Task<Void, Never>?

  /// Monotonic, bumped by every `.clearSession` (R9).
  ///
  /// The hole it closes: a session write is two hops — the coalescing sleep, then
  /// the actor call — and a shift can settle in between. Without a generation, the
  /// write that was already in the air lands *after* the delete and resurrects a
  /// board the player has finished, which the hub then offers to resume. A write
  /// carries the generation it was scheduled under and abandons itself if the world
  /// moved on.
  private var generation = 0
  /// Every store operation, in the order it was asked for. Writes and deletes must
  /// not race each other across their suspension points, and `SaveStore` is not this
  /// ticket's file to serialise, so they are serialised here.
  private var storeChain: Task<Void, Never>?

  private static let log = Logger(subsystem: "pl.oumm.sentry.soc", category: "EffectRunner")

  #if DEBUG
    /// Every effect this runner has performed, newest last, capped. The direct
    /// evidence for "performed once" — and for the QA overlay.
    private(set) var performed: [Effect] = []
    private static let performedCap = 256
  #endif

  init(
    save: SaveStore,
    flags: Flags = Flags(),
    registry: ScreenRegistry = .shared,
    context: Context = .noop,
    coalesceWindow: Duration = .milliseconds(250)
  ) {
    self.save = save
    self.flags = flags
    self.registry = registry
    self.context = context
    self.coalesceWindow = coalesceWindow
  }

  /// Perform each effect exactly once, in the order the reducer returned them.
  func run(_ effects: [Effect]) {
    for effect in effects { perform(effect) }
  }

  private func perform(_ effect: Effect) {
    #if DEBUG
      performed.append(effect)
      if performed.count > Self.performedCap {
        performed.removeFirst(performed.count - Self.performedCap)
      }
    #endif

    switch effect {
    case .haptic(let cue):
      guard context.hapticsEnabled() else { return }
      registry.haptics.play(cue)

    case .persistSession:
      scheduleSessionWrite()

    case .clearSession:
      pendingSessionWrite?.cancel()
      pendingSessionWrite = nil
      generation += 1
      enqueueStoreWork { store in await store.clearSession() }

    case .settleShift:
      context.settle()

    case .persistCareer:
      let career = context.career()
      enqueueStoreWork { store in await store.saveCareer(career) }

    case .setFlag(let key, let value):
      flags.set(rawKey: key, value)
      context.applyFlag(key, value)

    case .markDailyDone(let isoDay):
      context.markDailyDone(isoDay)
    }
  }

  /// Trailing-edge coalescing: a burst of pulls writes once, and the write that
  /// lands is the newest state, not the first.
  private func scheduleSessionWrite() {
    pendingSessionWrite?.cancel()
    let window = coalesceWindow
    pendingSessionWrite = Task { [weak self] in
      try? await Task.sleep(for: window)
      guard !Task.isCancelled, let self else { return }
      self.pendingSessionWrite = nil
      self.writeSessionNow()
    }
  }

  /// Called on `scenePhase == .background`, where "in 250 ms" is too late: the app
  /// may not be alive in 250 ms.
  func flushPendingWrites() {
    pendingSessionWrite?.cancel()
    pendingSessionWrite = nil
    writeSessionNow()
  }

  /// **Deleting the save is `.clearSession`'s job and nothing else's.** A write that
  /// finds no snapshot does nothing: the state that produces no snapshot is "sitting
  /// on the hub", and the hub is exactly where a player looks at the Resume card and
  /// then backgrounds the app. Clearing here would eat that save.
  private func writeSessionNow() {
    let scheduled = generation
    enqueueStoreWork { [weak self] store in
      guard let self, scheduled == self.generation, let snapshot = self.context.snapshot()
      else { return }
      await store.saveSession(snapshot)
    }
  }

  /// Append to the store's serial chain. The work runs on the main actor after
  /// everything asked for before it has finished, so a generation check inside it is
  /// a decision about a settled world rather than a guess about a racing one.
  private func enqueueStoreWork(_ work: @escaping @MainActor (SaveStore) async -> Void) {
    let previous = storeChain
    let store = save
    storeChain = Task { @MainActor in
      await previous?.value
      await work(store)
    }
  }
}
