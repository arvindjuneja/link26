import Foundation
import Testing
import SentryCore

@testable import SentrySOC

/// **P1-2 · Reset career resets the career.**
///
/// The reset used to be half a reset: a view sent `.abandon` and then built a second
/// `SaveStore` to write `CareerState.initial`. The file went to zero and the model
/// did not, so the hub kept drawing the old wallet and the next `persistCareer`
/// wrote the old career back over the reset.
///
/// The acceptance is the kill-and-relaunch check of `SPEC.md` §7: seed a career,
/// reset, "kill", relaunch — a second `GameModel` over the **same** directory and
/// the same defaults suite — and the desk is Trainee at ⬢ 0.
@MainActor
@Suite("Career reset")
struct CareerResetTests {

  private static func temporaryDirectory() -> URL {
    let url = URL.temporaryDirectory
      .appending(path: "ResetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// Everything a launch is: a save directory and a defaults suite, both survivable.
  private struct Device {
    let directory: URL
    let defaults: UserDefaults
    let suiteName: String

    var flags: Flags { Flags(defaults: defaults) }

    /// A cold launch on this device.
    func launch() -> GameModel {
      GameModel(
        save: SaveStore(directory: directory), flags: flags, registry: ScreenRegistry())
    }
  }

  private static func device() -> Device {
    let name = "ResetTests-\(UUID().uuidString)"
    return Device(
      directory: temporaryDirectory(), defaults: UserDefaults(suiteName: name)!, suiteName: name)
  }

  /// Play the first board to its summary, which is the only way a career gains
  /// anything — there is no setter, by design (D8).
  private static func playFirstShift(_ model: GameModel) {
    guard let shift = model.content.shifts.first else { return }
    model.send(.startShift(shift.id))
    model.send(.begin)
    model.send(.closeView)
    while let current = model.session.currentCase(model.content) {
      if let source = current.sourceIds.first { model.send(.pullSource(source)) }
      model.send(.makeCall(current.correctDisposition))
      model.send(.nextCase)
    }
  }

  // MARK: - The acceptance

  @Test("seed a career, reset, relaunch — the desk is Trainee at zero")
  func resetSurvivesARelaunch() async throws {
    let device = Self.device()
    defer { device.defaults.removePersistentDomain(forName: device.suiteName) }

    let played = device.launch()
    Self.playFirstShift(played)
    try await Task.sleep(for: .milliseconds(200))

    // A career worth resetting, and a save on disk that says so.
    #expect(played.career.standing > 0)
    #expect(played.career.cash > 0)
    #expect(played.career.clearedShiftIDs.isEmpty == false)
    let seeded = SaveStore(directory: device.directory).hydrate().career
    #expect(seeded == played.career, "the played career reached the disk")

    played.resetCareer()

    // 1. The model the player is looking at, immediately.
    #expect(played.career == .initial, "the hub still shows the old wallet")
    #expect(played.session.phase == .hub)
    #expect(played.resumable == nil)
    #expect(played.rules.rankFor(played.career.standing).id == played.content.ranks.first?.id)

    try await Task.sleep(for: .milliseconds(200))

    // 2. The kill-and-relaunch: a fresh model over the same device.
    let relaunched = device.launch()
    #expect(relaunched.career == .initial, "the save came back with the old career")
    #expect(relaunched.career.standing == 0)
    #expect(relaunched.career.cash == 0)
    #expect(relaunched.career.clearedShiftIDs.isEmpty)
    #expect(relaunched.resumable == nil, "a reset left a resumable board behind")
    #expect(
      relaunched.rules.rankFor(relaunched.career.standing).id == relaunched.content.ranks.first?.id,
      "the relaunched desk is not at the bottom rung")
  }

  /// The reset must not be undoable by simply playing on: the next `persistCareer`
  /// has to write the reset career, not the one the model was still holding.
  @Test("a write after the reset writes the reset career")
  func theResetCannotBeWrittenBackOver() async throws {
    let device = Self.device()
    defer { device.defaults.removePersistentDomain(forName: device.suiteName) }

    let model = device.launch()
    Self.playFirstShift(model)
    try await Task.sleep(for: .milliseconds(200))
    model.resetCareer()
    try await Task.sleep(for: .milliseconds(200))

    // Any later career write — here the refusal path of a purchase, which persists
    // nothing, followed by a real board — must build on `.initial`.
    Self.playFirstShift(model)
    try await Task.sleep(for: .milliseconds(200))

    let disk = SaveStore(directory: device.directory).hydrate().career
    #expect(disk == model.career)
    #expect(disk.shiftsCleaned <= 1, "the pre-reset career was written back over the reset")
  }

  // MARK: - The launch flags

  @Test("the reset re-arms the coach and leaves the disclaimer acknowledged")
  func resetClearsTheRightFlags() async throws {
    let device = Self.device()
    defer { device.defaults.removePersistentDomain(forName: device.suiteName) }

    let model = device.launch()
    // A player who has been through the gate, been through the coach, and switched
    // coaching off.
    model.send(.ackFirstRun)
    Self.playFirstShift(model)
    model.send(.setSetting(.coaching, false))
    try await Task.sleep(for: .milliseconds(200))

    #expect(device.flags.hasSeenFirstRun)
    #expect(device.flags.hasSeenOnboarding, "the first filed call closes the coach")
    #expect(model.settings.coaching == false)

    model.resetCareer()
    try await Task.sleep(for: .milliseconds(200))

    // The disclaimer was acknowledged by a person and this is still that person.
    #expect(device.flags.hasSeenFirstRun, "the reset re-gated the disclaimer")
    // The coach belongs to the career, and there is a new one.
    #expect(device.flags.hasSeenOnboarding == false, "the coach was not re-armed")
    #expect(model.hasSeenOnboarding == false, "the model did not mirror the flag")
    #expect(device.flags.bool(.coaching), "coaching did not return to its default")
    #expect(model.settings.coaching)

    // And a relaunch agrees with the flags, not with this process.
    let relaunched = device.launch()
    #expect(relaunched.session.view != .firstRun, "the gate came back")
    #expect(relaunched.hasSeenOnboarding == false)
    #expect(relaunched.settings.coaching)
  }
}
