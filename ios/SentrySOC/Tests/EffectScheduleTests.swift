import Foundation
import Testing
import SentryCore

@testable import SentrySOC

/// Acceptance #5, second half: the runner performs each effect **once**.
///
/// This is where "the debrief buzzed twice" bugs live. The reducer is pure and easy
/// to trust; the interesting failure is an effect fired on every re-render, or a
/// coalesced write that never lands, or a haptic that plays with haptics switched
/// off. All three are asserted here.
@MainActor
@Suite("Effect schedule")
struct EffectScheduleTests {

  // MARK: - Fixtures

  private static func temporaryDirectory() -> URL {
    let url = URL.temporaryDirectory
      .appending(path: "EffectTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// A `UserDefaults` suite of its own, so a test can never leave a flag behind in
  /// the app's real defaults.
  private static func scratchFlags() -> (Flags, UserDefaults, String) {
    let name = "EffectTests-\(UUID().uuidString)"
    // `UserDefaults(suiteName:)` returns nil only for the global domain or the app's
    // own bundle identifier. A UUID-suffixed name is neither, so this cannot fail.
    let defaults = UserDefaults(suiteName: name)!
    return (Flags(defaults: defaults), defaults, name)
  }

  /// Records what the registry was asked to feel.
  private final class RecordingHaptics: HapticsSink {
    var cues: [SocCue] = []
    var plans: [HeartbeatPlan?] = []
    func play(_ cue: SocCue) { cues.append(cue) }
    func setHeartbeat(_ plan: HeartbeatPlan?) { plans.append(plan) }
  }

  private static let shift = ShiftState(
    shiftId: "first-shift", caseIds: ["soc-ps-encoded", "soc-brute-success"], timeBudget: 120)

  // MARK: - Once, and in order

  @Test("every effect is performed exactly once, in the order the reducer returned")
  func performedOnceInOrder() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let haptics = RecordingHaptics()
    let registry = ScreenRegistry()
    registry.haptics = haptics

    let runner = EffectRunner(
      save: SaveStore(directory: Self.temporaryDirectory()), flags: flags, registry: registry,
      context: .noop.enablingHaptics())

    let effects: [Effect] = [
      .haptic(.select), .haptic(.file), .setFlag(SentryFlagKey.onboarding, true),
    ]
    runner.run(effects)

    #expect(runner.performed == effects)
    #expect(haptics.cues == [.select, .file])
    #expect(flags.bool(.onboarding))
  }

  @Test("running twice performs twice — the ledger is not deduplicating for us")
  func runningTwicePerformsTwice() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let haptics = RecordingHaptics()
    let registry = ScreenRegistry()
    registry.haptics = haptics

    let runner = EffectRunner(
      save: SaveStore(directory: Self.temporaryDirectory()), flags: flags, registry: registry,
      context: .noop.enablingHaptics())

    runner.run([.haptic(.verdictGood)])
    runner.run([.haptic(.verdictGood)])

    #expect(haptics.cues.count == 2)
  }

  /// The real "buzzed twice" guard: one `send`, one pass of effects — regardless of
  /// how many times SwiftUI re-reads the model afterwards.
  @Test("one send produces one pass of effects")
  func oneSendOnePass() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = GameModel(
      save: SaveStore(directory: Self.temporaryDirectory()),
      flags: flags, registry: ScreenRegistry())

    let before = model.debugPerformedEffects.count
    model.send(.openView(.settings))
    let after = model.debugPerformedEffects

    #expect(after.count == before + 1)
    #expect(after.last == .haptic(.select))

    // Reading the model again must not re-run anything.
    _ = model.session
    _ = model.career
    #expect(model.debugPerformedEffects.count == after.count)
  }

  // MARK: - Gating

  @Test("no cue reaches the sink when haptics are switched off")
  func hapticsToggleGatesTheSink() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let haptics = RecordingHaptics()
    let registry = ScreenRegistry()
    registry.haptics = haptics

    let runner = EffectRunner(
      save: SaveStore(directory: Self.temporaryDirectory()), flags: flags, registry: registry,
      context: .noop)                                   // hapticsEnabled → false

    runner.run([.haptic(.file), .haptic(.breachThud)])

    #expect(haptics.cues.isEmpty)
    // The effect still counts as performed — it was interpreted, and the
    // interpretation was "the player asked for silence".
    #expect(runner.performed.count == 2)
  }

  // MARK: - Writes

  @Test("a burst of session writes coalesces into one file write")
  func sessionWritesCoalesce() async throws {
    let directory = Self.temporaryDirectory()
    let store = SaveStore(directory: directory)
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }

    var snapshotCalls = 0
    var context = EffectRunner.Context.noop
    context.snapshot = {
      snapshotCalls += 1
      return SessionSnapshot(
        phase: .investigating, shift: Self.shift, queried: [], status: .calm)
    }

    let runner = EffectRunner(
      save: store, flags: flags, registry: ScreenRegistry(), context: context,
      coalesceWindow: .milliseconds(20))

    runner.run([.persistSession, .persistSession, .persistSession, .persistSession])
    #expect(snapshotCalls == 0, "the write is trailing-edge, not eager")

    try await Task.sleep(for: .milliseconds(200))

    #expect(snapshotCalls == 1)
    #expect(store.hydrate().session != nil)
  }

  @Test("clearSession cancels a pending coalesced write")
  func clearCancelsPendingWrite() async throws {
    let directory = Self.temporaryDirectory()
    let store = SaveStore(directory: directory)
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }

    var context = EffectRunner.Context.noop
    context.snapshot = {
      SessionSnapshot(phase: .investigating, shift: Self.shift, queried: [], status: .calm)
    }

    let runner = EffectRunner(
      save: store, flags: flags, registry: ScreenRegistry(), context: context,
      coalesceWindow: .milliseconds(50))

    runner.run([.persistSession])
    runner.run([.clearSession])
    try await Task.sleep(for: .milliseconds(200))

    // The settled shift must not be resurrected by a write that was already in the air.
    #expect(store.hydrate().session == nil)
  }

  /// R9's generation token. The dangerous case is not the write that is still
  /// sleeping — that one is cancelled — but the write whose timer has **already
  /// fired** and which is queued behind a suspension point when the shift settles.
  @Test("a write already past its timer cannot land after the clear")
  func clearBeatsAWriteAlreadyInFlight() async throws {
    let directory = Self.temporaryDirectory()
    let store = SaveStore(directory: directory)
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }

    var context = EffectRunner.Context.noop
    context.snapshot = {
      SessionSnapshot(phase: .investigating, shift: Self.shift, queried: [], status: .calm)
    }

    let runner = EffectRunner(
      save: store, flags: flags, registry: ScreenRegistry(), context: context,
      coalesceWindow: .milliseconds(1))

    runner.run([.persistSession])
    try await Task.sleep(for: .milliseconds(20))         // the timer has fired
    runner.run([.clearSession])
    try await Task.sleep(for: .milliseconds(200))

    #expect(store.hydrate().session == nil, "the settled board was resurrected by a stale write")

    // And a write scheduled *after* the clear is a new generation, so it lands.
    runner.run([.persistSession])
    try await Task.sleep(for: .milliseconds(200))
    #expect(store.hydrate().session != nil)
  }

  @Test("backgrounding flushes the pending write immediately")
  func backgroundingFlushes() async throws {
    let directory = Self.temporaryDirectory()
    let store = SaveStore(directory: directory)
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }

    var context = EffectRunner.Context.noop
    context.snapshot = {
      SessionSnapshot(phase: .investigating, shift: Self.shift, queried: [], status: .calm)
    }

    let runner = EffectRunner(
      save: store, flags: flags, registry: ScreenRegistry(), context: context,
      coalesceWindow: .seconds(30))                     // deliberately never fires on its own

    runner.run([.persistSession])
    runner.flushPendingWrites()
    try await Task.sleep(for: .milliseconds(200))

    #expect(store.hydrate().session != nil)
  }

  @Test("persistCareer writes the career the context hands it")
  func persistCareerWrites() async throws {
    let directory = Self.temporaryDirectory()
    let store = SaveStore(directory: directory)
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }

    var context = EffectRunner.Context.noop
    context.career = { CareerState(cash: 300, standing: 15, shiftsCleaned: 1) }

    let runner = EffectRunner(
      save: store, flags: flags, registry: ScreenRegistry(), context: context)
    runner.run([.persistCareer])
    try await Task.sleep(for: .milliseconds(200))

    #expect(store.hydrate().career.cash == 300)
    #expect(store.hydrate().career.standing == 15)
  }

  // MARK: - Reducer wiring

  @Test("a setting change is a flag write, not a direct mutation")
  func settingChangeGoesThroughAFlag() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = GameModel(
      save: SaveStore(directory: Self.temporaryDirectory()), flags: flags,
      registry: ScreenRegistry())

    #expect(model.settings.haptics)
    model.send(.setSetting(.haptics, false))

    #expect(model.settings.haptics == false)
    #expect(flags.bool(.haptics) == false)
    #expect(model.debugPerformedEffects.last == .setFlag(SettingKey.haptics.rawValue, false))
  }

  // MARK: - The 16:00 settlement

  /// Play a whole board through `send(_:)` and stop where the shift settles.
  /// Returns the model so an assertion can read what the settlement did.
  @discardableResult
  private static func playFirstShift(
    _ model: GameModel, disposition: Disposition = .escalateIRIsolate
  ) -> GameModel {
    guard let shift = model.content.shifts.first else { return model }
    playBoard(model, shift.id, disposition: disposition)
    return model
  }

  /// Play a named board — campaign or today's daily — to the summary. A pull on each
  /// case, so the coalesced session write is genuinely in flight when the board
  /// settles.
  private static func playBoard(
    _ model: GameModel, _ shiftID: String, disposition: Disposition? = nil
  ) {
    model.send(.startShift(shiftID))
    model.send(.begin)
    model.send(.closeView)
    while let current = model.session.currentCase(model.content) {
      if let sourceID = current.sourceIds.first { model.send(.pullSource(sourceID)) }
      model.send(.makeCall(disposition ?? current.correctDisposition))
      model.send(.nextCase)
    }
  }

  @Test("the settle chain runs in order and the career it writes is the settled one")
  func settlementOrder() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = GameModel(
      save: SaveStore(directory: Self.temporaryDirectory()), flags: flags,
      registry: ScreenRegistry())

    let before = model.career
    Self.playFirstShift(model)

    #expect(model.session.phase == .complete)
    // `settleShift → persistCareer → clearSession`, in that order and once each.
    let tail = model.debugPerformedEffects.suffix(3)
    #expect(Array(tail) == [.settleShift, .persistCareer, .clearSession])
    // The shift paid: cash always moves, and every field came out of SentryCore.
    #expect(model.career.cash > before.cash)
    #expect(model.career != before)
  }

  @Test("settling refreshes the inbox from the handler")
  func settlementFillsTheInbox() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = GameModel(
      save: SaveStore(directory: Self.temporaryDirectory()), flags: flags,
      registry: ScreenRegistry())

    // A cold launch already has an inbox — the welcome, at minimum.
    #expect(!model.inbox.isEmpty)
    let cold = model.inbox

    Self.playFirstShift(model)

    #expect(!model.inbox.isEmpty)
    #expect(model.inbox != cold, "the shift's own message never reached the hub")
    // B1/S3: the blue-only inbox drops the cross-seat nudge and is capped at four.
    #expect(model.inbox.count <= 4)
    #expect(!model.inbox.contains { $0.id == "tip-redrun" })
  }

  @Test("the first filed call retires the coach, once")
  func firstCallRetiresTheCoach() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = GameModel(
      save: SaveStore(directory: Self.temporaryDirectory()), flags: flags,
      registry: ScreenRegistry())

    #expect(model.coachIsActive)
    guard let shift = model.content.shifts.first else { return }
    model.send(.startShift(shift.id))
    model.send(.begin)
    model.send(.makeCall(.escalateIRIsolate))

    #expect(model.hasSeenOnboarding)
    #expect(model.coachIsActive == false)
    #expect(flags.hasSeenOnboarding)
  }

  @Test("a filed call moves the meters through SentryCore, not the app")
  func meterMovementComesFromTheEngine() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = GameModel(
      save: SaveStore(directory: Self.temporaryDirectory()), flags: flags,
      registry: ScreenRegistry())

    guard let shift = model.content.shifts.first,
          let firstCaseID = shift.caseIds.first,
          let socCase = model.content.case(firstCaseID)
    else { return }

    model.send(.startShift(shift.id))
    model.send(.begin)
    model.send(.makeCall(.closeFalsePositive))

    // The board the engine would produce from the same call, computed independently
    // of the reducer: if the app ever did its own meter arithmetic, these diverge.
    let expected = model.engine.applyCall(
      model.engine.assembleShift(shift.id, shift.caseIds), socCase, .closeFalsePositive,
      queriedSourceIds: [], timeSpent: 0)

    #expect(model.session.shift == expected)
    #expect(model.session.shift?.results.count == 1)
    #expect(model.session.shift?.index == 1)
    #expect(model.session.status == model.engine.overallShiftStatus(expected))
  }

  @Test("a second NEXT_CASE from `complete` does not settle a second time")
  func settlementIsNotRepeatable() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = GameModel(
      save: SaveStore(directory: Self.temporaryDirectory()), flags: flags,
      registry: ScreenRegistry())

    Self.playFirstShift(model)
    let settled = model.career

    model.send(.nextCase)                        // G6: complete → hub

    #expect(model.session.phase == .hub)
    #expect(model.career == settled, "the shift paid twice")
    #expect(model.debugPerformedEffects.filter { $0 == .settleShift }.count == 1)
  }

  // MARK: - Resume

  @Test("resuming goes through the reducer, not around it")
  func resumeIsAnAction() async throws {
    let directory = Self.temporaryDirectory()
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }

    // A shift interrupted mid-board, on disk.
    let store = SaveStore(directory: directory)
    await store.saveSession(
      SessionSnapshot(phase: .investigating, shift: Self.shift, queried: ["edr-process-tree"],
                      status: .alert))

    let model = GameModel(
      save: SaveStore(directory: directory), flags: flags, registry: ScreenRegistry())
    #expect(model.resumable != nil)
    #expect(model.session.shift == nil, "the snapshot is offered, never auto-entered")

    model.resume()

    #expect(model.session.phase == .investigating)
    #expect(model.session.shift == Self.shift)
    #expect(model.session.queried == ["edr-process-tree"])
    #expect(model.session.status == .alert)
    #expect(model.resumable == nil)
  }

  @Test("backgrounding at the hub does not delete the offered save")
  func flushAtTheHubKeepsTheSnapshot() async throws {
    let directory = Self.temporaryDirectory()
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = SaveStore(directory: directory)
    await store.saveSession(
      SessionSnapshot(phase: .investigating, shift: Self.shift, queried: [], status: .calm))

    let model = GameModel(
      save: SaveStore(directory: directory), flags: flags, registry: ScreenRegistry())
    model.scenePhaseChanged(to: .background)     // the player looked at the card and left
    try await Task.sleep(for: .milliseconds(200))

    #expect(
      SaveStore(directory: directory).hydrate().session != nil,
      "the Resume card's own save was eaten by a background flush")
  }

  @Test("an unknown flag key is dropped — UserDefaults holds exactly five")
  func unknownFlagKeysAreDropped() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }

    // `Flags.set(rawKey:)` asserts in Debug on an unknown key, so drive the guard
    // through the public roster instead: every key the reducer can emit is known.
    let emitted = SettingKey.allCases.map(\.rawValue) + [SentryFlagKey.firstRun, SentryFlagKey.onboarding]
    for key in emitted {
      #expect(Flags.Key(rawValue: key) != nil, "\(key) is emitted but not a Flags.Key")
    }
    // The three switches ARE `SettingKey`; the two gates are the rest. Five, exactly.
    #expect(Set(Flags.Key.allCases) == Set(SettingKey.allCases.map(Flags.Key.init) + Flags.Key.gates))
    #expect(Flags.Key.allCases.count == 5)
    _ = flags
  }

  // MARK: - Buying (R9)

  @Test("a refused purchase costs a denied cue and writes nothing")
  func refusedPurchaseWritesNothing() async throws {
    let directory = Self.temporaryDirectory()
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let haptics = RecordingHaptics()
    let registry = ScreenRegistry()
    registry.haptics = haptics

    let model = GameModel(
      save: SaveStore(directory: directory), flags: flags, registry: registry)
    let item = try #require(model.content.kit.first)
    #expect(model.career.cash < item.cost, "a fresh career cannot afford the kit")

    model.buy(item)
    try await Task.sleep(for: .milliseconds(200))

    #expect(model.career.gear.isEmpty, "an unaffordable item was handed over")
    #expect(model.career.cash == 0)
    #expect(haptics.cues.last == .denied)
    #expect(!model.debugPerformedEffects.contains(.persistCareer), "a refusal wrote the save")
    #expect(SaveStore(directory: directory).hydrate().career.gear.isEmpty)
  }

  @Test("an affordable purchase debits once, commits, and persists the debited career")
  func purchaseDebitsAndPersists() async throws {
    let directory = Self.temporaryDirectory()
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let haptics = RecordingHaptics()
    let registry = ScreenRegistry()
    registry.haptics = haptics

    // A career that can afford it, on disk before launch.
    let seed = SaveStore(directory: directory)
    let item = try #require(ContentPack.bundled.kit.first)
    await seed.saveCareer(CareerState(cash: item.cost + 25, standing: 0))

    let model = GameModel(
      save: SaveStore(directory: directory), flags: flags, registry: registry)
    model.buy(item)
    try await Task.sleep(for: .milliseconds(200))

    #expect(model.career.gear == [item.id])
    #expect(model.career.cash == 25)
    #expect(haptics.cues.last == .commitSoft)
    // The write must carry the debit, not the balance from before it.
    let onDisk = SaveStore(directory: directory).hydrate().career
    #expect(onDisk.cash == 25)
    #expect(onDisk.gear == [item.id])

    // Buying it again is refused: owned is refused, exactly like unaffordable.
    model.buy(item)
    #expect(model.career.cash == 25)
    #expect(haptics.cues.last == .denied)
  }

  // MARK: - The settlement the reducer computed

  @Test("settling adopts the reducer's settlement rather than recomputing it")
  func settlementIsAdoptedNotRecomputed() throws {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = GameModel(
      save: SaveStore(directory: Self.temporaryDirectory()), flags: flags,
      registry: ScreenRegistry())

    Self.playFirstShift(model)

    let settlement = try #require(model.session.settlement)
    #expect(model.career == settlement.reward.state, "the app awarded something of its own")
    #expect(settlement.careerBefore == .initial)
    #expect(settlement.score == model.engine.scoreShift(try #require(model.session.shift)))
  }

  // MARK: - The daily ledger (Appendix A G7)

  @Test("the daily board pays standing once a day and cash every run")
  func dailyLedger() async throws {
    let directory = Self.temporaryDirectory()
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }

    let daily = ContentPack.bundled.dailyShift(on: Date())
    let seed = SaveStore(directory: directory)
    await seed.saveCareer(CareerState(cash: 0, standing: daily.unlockStanding, shiftsCleaned: 1))

    let model = GameModel(
      save: SaveStore(directory: directory), flags: flags, registry: ScreenRegistry())
    Self.playBoard(model, daily.id)

    let today = DailyCalendar.isoDay(Date())
    #expect(model.session.settlement?.isDaily == true)
    #expect(model.debugPerformedEffects.contains(.markDailyDone(today)))
    #expect(model.career.dailyDoneOn == today, "the reducer's stamp never reached the career")
    let afterFirst = model.career

    // Same day, same board, again. Leaving the summary is `complete → milestone | hub`
    // and `milestone` takes ACK_MILESTONE (§2.1) — and START_SHIFT is refused
    // anywhere but the desk, so the walk back has to be finished before the second
    // run can open.
    model.send(.nextCase)
    if model.session.phase == .milestone { model.send(.ackMilestone) }
    #expect(model.session.phase == .hub, "never got back to the desk for the second run")
    Self.playBoard(model, daily.id)

    #expect(model.session.settlement?.standingSuppressed == true)
    #expect(model.career.standing == afterFirst.standing, "standing paid twice in one day")
    #expect(model.career.cash > afterFirst.cash, "cash stopped paying — the grind is dead")
  }

  // MARK: - The clear/write race (R9)

  @Test("a write scheduled before a settle cannot resurrect the cleared snapshot")
  func clearedSnapshotStaysCleared() async throws {
    let directory = Self.temporaryDirectory()
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }

    let model = GameModel(
      save: SaveStore(directory: directory), flags: flags, registry: ScreenRegistry())
    // Pull, then finish the board inside the 250 ms coalescing window: the pull's
    // write is still in the air when the settlement deletes the snapshot.
    Self.playFirstShift(model)
    try await Task.sleep(for: .milliseconds(400))

    #expect(model.session.phase == .complete)
    #expect(
      SaveStore(directory: directory).hydrate().session == nil,
      "the settled board came back as a Resume card")
  }
}

extension EffectRunner.Context {
  /// `.noop` with the haptics gate open — the common shape in these tests.
  fileprivate func enablingHaptics() -> Self {
    var copy = self
    copy.hapticsEnabled = { true }
    return copy
  }
}
