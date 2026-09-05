import Foundation
import Testing
import SentryCore

@testable import SentrySOC

/// Acceptance #5. The save is the only thing in this app a player can actually
/// lose, so every one of its policies is asserted: the round trip, the two
/// leniencies, the backup rotation, the corruption quarantine, and the one that
/// matters most — losing the app mid-shift puts you back on the same alert.
@Suite("SaveStore")
struct SaveStoreTests {

  // MARK: - Fixtures

  private static func temporaryDirectory() -> URL {
    let url = URL.temporaryDirectory
      .appending(path: "SaveStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static let career = CareerState(
    cash: 1_240, standing: 95, shiftsCleaned: 4, redRunsDone: 0,
    gear: ["kit-triage-macro", "kit-second-monitor"], dailyDoneOn: "2026-09-05")

  private static let midShift = ShiftState(
    shiftId: "first-shift",
    caseIds: ["soc-ps-encoded", "soc-brute-success", "soc-phish-harvest"],
    timeBudget: 120,
    index: 1,
    results: [
      CaseResult(
        caseId: "soc-ps-encoded", chosen: .escalateIRIsolate, verdictCorrect: true,
        dispositionCorrect: true, queriedSourceIds: ["edr-process-tree", "proxy-logs"],
        keySourcesPulled: 2, timeSpent: 14)
    ],
    breachRisk: 0, noise: 12, timeUsed: 14)

  private static func writeRaw(_ json: String, to url: URL) throws {
    // `Data(_:)` over the UTF-8 view instead of the failable `data(using:)`:
    // a Swift `String` is always encodable as UTF-8, so there is nothing to unwrap.
    try Data(json.utf8).write(to: url)
  }

  // MARK: - Round trip

  @Test("a career round-trips every field")
  func careerRoundTrips() async {
    let directory = Self.temporaryDirectory()
    let store = SaveStore(directory: directory)

    await store.saveCareer(Self.career)
    let hydration = store.hydrate()

    #expect(hydration.career == Self.career)
    #expect(hydration.careerWasCorrupt == false)
    #expect(hydration.session == nil)
  }

  @Test("a mid-shift snapshot round-trips every field")
  func snapshotRoundTrips() async {
    let directory = Self.temporaryDirectory()
    let store = SaveStore(directory: directory)
    let snapshot = SessionSnapshot(
      phase: .investigating, shift: Self.midShift,
      queried: ["edr-process-tree"], status: .alert)

    await store.saveSession(snapshot)
    let hydration = store.hydrate()

    #expect(hydration.session == snapshot)
  }

  /// The one that matters. The phone gives up on alert 2 of 3, with one call already
  /// filed and 12 points of noise on the board — and it all comes back, exactly.
  @Test("a cold relaunch mid-shift restores the exact ShiftState")
  func coldRelaunchRestoresTheShift() async throws {
    let directory = Self.temporaryDirectory()

    // Session one: play into the second alert, then lose the process.
    let live = SessionState(
      phase: .investigating, view: .source("proxy-logs"), shift: Self.midShift,
      queried: ["edr-process-tree", "proxy-logs"], pendingDisposition: .escalateTier2,
      status: .alert)
    let interrupted = SaveStore(directory: directory)
    await interrupted.saveSession(try #require(SessionSnapshot(live)))

    // Session two: a cold launch, hydrating from disk.
    let relaunched = SaveStore(directory: directory).hydrate()
    let restored = try #require(relaunched.session).session

    #expect(restored.shift == Self.midShift)
    #expect(restored.shift?.index == 1)
    #expect(restored.shift?.results.count == 1)
    #expect(restored.shift?.noise == 12)
    #expect(restored.queried == ["edr-process-tree", "proxy-logs"])
    #expect(restored.phase == .investigating)
    // Deliberately NOT restored: the open sheet and the half-picked disposition.
    // Coming back from a cold launch into a modal, mid-decision, is disorienting.
    #expect(restored.view == nil)
    #expect(restored.pendingDisposition == nil)
  }

  // MARK: - Leniency

  @Test("missing fields default from CareerState.initial")
  func missingFieldsDefault() throws {
    let directory = Self.temporaryDirectory()
    // A save written before `redRunsDone`, `gear` and `dailyDoneOn` existed.
    try Self.writeRaw(
      #"{"schemaVersion":1,"savedAt":"2026-09-05T08:00:00Z","payload":{"cash":300,"standing":15}}"#,
      to: directory.appending(path: "career.json"))

    let hydration = SaveStore(directory: directory).hydrate()

    #expect(hydration.careerWasCorrupt == false)
    #expect(hydration.career.cash == 300)
    #expect(hydration.career.standing == 15)
    #expect(hydration.career.shiftsCleaned == CareerState.initial.shiftsCleaned)
    #expect(hydration.career.redRunsDone == CareerState.initial.redRunsDone)
    #expect(hydration.career.gear == CareerState.initial.gear)
    #expect(hydration.career.dailyDoneOn == nil)
  }

  @Test("unknown fields survive a load-and-save round trip")
  func unknownFieldsSurvive() async throws {
    let directory = Self.temporaryDirectory()
    let url = directory.appending(path: "career.json")
    // A save written by a LATER build, opened by this one.
    try Self.writeRaw(
      """
      {"schemaVersion":1,"savedAt":"2026-09-05T08:00:00Z","payload":{\
      "cash":300,"standing":15,"shiftsCleaned":1,"redRunsDone":0,"gear":[],\
      "prestige":3,"loadout":{"slot":"alpha"},"seenCases":["soc-ps-encoded"]}}
      """,
      to: url)

    // Decode, then write back out through this build.
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = try decoder.decode(
      SaveStore.Envelope<CareerRecord>.self, from: Data(contentsOf: url)).payload
    #expect(record.extras["prestige"] == .int(3))
    #expect(record.extras["seenCases"] == .array([.string("soc-ps-encoded")]))

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let reencoded = try encoder.encode(record)
    let object = try #require(
      JSONSerialization.jsonObject(with: reencoded) as? [String: Any])

    // An older build must not silently strip a newer build's data from the file.
    #expect(object["prestige"] as? Int == 3)
    #expect((object["loadout"] as? [String: Any])?["slot"] as? String == "alpha")
    #expect(object["seenCases"] as? [String] == ["soc-ps-encoded"])
    #expect(object["cash"] as? Int == 300)
  }

  // MARK: - Durability

  @Test("a corrupt career is renamed, never overwritten")
  func corruptCareerIsQuarantined() throws {
    let directory = Self.temporaryDirectory()
    let url = directory.appending(path: "career.json")
    try Self.writeRaw("{ this is not json", to: url)

    let hydration = SaveStore(directory: directory).hydrate()

    #expect(hydration.careerWasCorrupt)
    #expect(hydration.career == .initial)
    #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == false)

    let salvaged = try FileManager.default
      .contentsOfDirectory(atPath: directory.path(percentEncoded: false))
      .filter { $0.hasPrefix("career.corrupt-") }
    #expect(salvaged.count == 1)
    // The bytes are still there — a bad parse must not become a wiped save.
    let recovered = try String(
      contentsOf: directory.appending(path: salvaged[0]), encoding: .utf8)
    #expect(recovered == "{ this is not json")
  }

  @Test("a corrupt career falls back to the rotated backup")
  func corruptCareerRecoversFromBackup() async throws {
    let directory = Self.temporaryDirectory()
    let store = SaveStore(directory: directory)

    await store.saveCareer(Self.career)                  // writes career.json
    await store.saveCareer(CareerState(cash: 9, standing: 9))  // rotates the good one into .bak
    try Self.writeRaw("garbage", to: directory.appending(path: "career.json"))

    let hydration = store.hydrate()

    #expect(hydration.careerWasCorrupt == false)
    #expect(hydration.career == Self.career)
  }

  @Test("clearSession deletes the snapshot")
  func clearSessionDeletes() async {
    let directory = Self.temporaryDirectory()
    let store = SaveStore(directory: directory)

    await store.saveSession(
      SessionSnapshot(phase: .investigating, shift: Self.midShift, queried: [], status: .calm))
    #expect(store.hydrate().session != nil)

    await store.clearSession()
    #expect(store.hydrate().session == nil)
  }

  @Test("saved files carry the schema version")
  func savesAreVersioned() async throws {
    let directory = Self.temporaryDirectory()
    await SaveStore(directory: directory).saveCareer(Self.career)

    let object = try #require(
      JSONSerialization.jsonObject(
        with: Data(contentsOf: directory.appending(path: "career.json"))) as? [String: Any])
    #expect(object["schemaVersion"] as? Int == SaveStore.schemaVersion)
    #expect(object["payload"] != nil)
  }
}
