import Foundation
import Testing

@testable import SentryCore

/// The hardcoded table D7 asks for: nothing in `SentryCore` spells a tuning number,
/// so a designer retune is a re-export and zero Swift — and this suite is what makes
/// a *silent* retune loud in review. It is deliberately a transcription: if a number
/// here disagrees with the export, one of the two was changed without the other, and
/// the diff says which.
///
/// There are exactly **31** tuning numbers (S8, amended by R6): trace 5 · bpm 4 ·
/// timeBudgetDefault 1 · grade 8 · shift 2 · career 6 · heartbeat 3 · handler 2.
///
/// The structural half walks the EXPORTED `content.json` rather than a re-encode of
/// the Swift `Tuning`, because a mirror can only ever show the leaves it declares:
/// re-encoding could not see a number added to the export and dropped on decode,
/// which is precisely the failure this test exists to catch. `swiftMirror` then
/// checks the mirror against the same table, and names anything the mirror does not
/// carry yet.
@Suite("Tuning expectations")
struct TuningExpectationTests {

  /// One pinned number: where it lives in `content.json` and what the founder signed
  /// off. `Double` throughout — every value here is exactly representable, so `==` is
  /// exact (D13).
  struct Pin: Sendable, CustomTestStringConvertible {
    let path: String
    let expected: Double
    var testDescription: String { path }
  }

  static let pins: [Pin] = [
    // trace · 5
    Pin(path: "trace.min", expected: 0),
    Pin(path: "trace.max", expected: 100),
    Pin(path: "trace.alert", expected: 25),
    Pin(path: "trace.hunt", expected: 50),
    Pin(path: "trace.lockdown", expected: 80),
    // bpm · 4
    Pin(path: "bpm.CALM", expected: 50),
    Pin(path: "bpm.ALERT", expected: 76),
    Pin(path: "bpm.HUNT", expected: 112),
    Pin(path: "bpm.LOCKDOWN", expected: 150),
    // timeBudgetDefault · 1
    Pin(path: "timeBudgetDefault", expected: 90),
    // grade · 8
    Pin(path: "grade.tpMissedBreach", expected: 30),
    Pin(path: "grade.tpUnderContainBreach", expected: 10),
    Pin(path: "grade.tpOverContainNoise", expected: 12),
    Pin(path: "grade.fpEscalateT2Noise", expected: 12),
    Pin(path: "grade.fpEscalateIsolateNoise", expected: 20),
    Pin(path: "grade.btpClosedAsFpNoise", expected: 4),
    Pin(path: "grade.btpEscalateT2Noise", expected: 14),
    Pin(path: "grade.btpIsolateNoise", expected: 24),
    // shift · 2
    Pin(path: "shift.cleanAccuracy", expected: 0.8),
    Pin(path: "shift.breachedMissedDetections", expected: 2),
    // career · 6
    Pin(path: "career.cashPerCorrect", expected: 50),
    Pin(path: "career.cleanBonus", expected: 150),
    Pin(path: "career.standingClean", expected: 40),
    Pin(path: "career.standingRough", expected: 15),
    Pin(path: "career.standingBreached", expected: 5),
    Pin(path: "career.redRunCut", expected: 150),
    // heartbeat · 3
    Pin(path: "heartbeat.minPeriodMs", expected: 400),
    Pin(path: "heartbeat.autoSuspendMs", expected: 40000),
    Pin(path: "heartbeat.dubOffsetMs", expected: 120),
    // handler · 2 (R6) — the wall and the cross-seat nudge gate, read by `Inbox.swift`
    Pin(path: "handler.inboxCapacity", expected: 4),
    Pin(path: "handler.redRunNudgeStanding", expected: 90),
  ]

  @Test(
    "the exported tuning still holds its pinned value",
    arguments: TuningExpectationTests.pins)
  func pinnedValue(_ pin: Pin) throws {
    let leaves = try Self.exportedLeaves()
    #expect(leaves[pin.path] == pin.expected, "\(pin.path)")
  }

  @Test("there are exactly 31 pinned numbers")
  func pinCount() {
    #expect(Self.pins.count == 31)
    #expect(Set(Self.pins.map(\.path)).count == 31)
  }

  /// The structural half: walk the exported tuning tree, so a number added to
  /// `tuning.ts` without a pin here fails rather than shipping unread.
  @Test("the exported tuning tree is exactly the pinned set")
  func exportedLeavesMatchThePins() throws {
    let leaves = try Self.exportedLeaves()
    #expect(Set(leaves.keys) == Set(Self.pins.map(\.path)))
    #expect(leaves.count == 31)
  }

  /// The Swift mirror, against the same table. Every number `Tuning` declares must
  /// hold its pinned value; anything the mirror does not carry is named, and may only
  /// ever be the `handler` block — see the note on `HandlerVoice.tuning`, which reads
  /// those two straight from the bundle until C2's `Tuning` gains them.
  @Test("the Swift mirror agrees with every number it carries")
  func swiftMirrorAgrees() throws {
    let data = try JSONEncoder().encode(ContentPack.bundled.tuning)
    var mirrored: [String: Double] = [:]
    Self.flatten(try JSONSerialization.jsonObject(with: data), prefix: "", into: &mirrored)

    let expected = Dictionary(uniqueKeysWithValues: Self.pins.map { ($0.path, $0.expected) })
    for (path, value) in mirrored {
      #expect(expected[path] != nil, "the mirror carries \(path), which is not pinned")
      #expect(value == expected[path], "\(path) as the Swift mirror decodes it")
    }

    let unmirrored = Set(expected.keys).subtracting(mirrored.keys).sorted()
    #expect(
      unmirrored.allSatisfy { $0.hasPrefix("handler.") },
      "the Swift Tuning silently drops \(unmirrored.joined(separator: ", "))")
  }

  /// R6 — the two handler numbers are not decoration: `Inbox.swift` reads them, so
  /// the wall and the nudge gate move with a re-export.
  @Test("the handler numbers are the ones the inbox actually uses")
  func theInboxReadsTheHandlerBlock() throws {
    let leaves = try Self.exportedLeaves()
    #expect(Double(HandlerVoice.capacity) == leaves["handler.inboxCapacity"])
    #expect(Double(HandlerVoice.redRunNudgeStanding) == leaves["handler.redRunNudgeStanding"])
  }

  /// The one non-integer, called out on its own because it is the only tuning
  /// number a `Double` round-trip could damage — and the grade rule compares
  /// against it with `>=`, so the board that lands exactly on it must read clean.
  @Test("the clean-accuracy threshold survives the round trip exactly")
  func cleanAccuracyIsExact() {
    let threshold = ContentPack.bundled.tuning.shift.cleanAccuracy
    #expect(threshold == 0.8)
    #expect(threshold == 4.0 / 5.0)
    #expect(!(threshold < 4.0 / 5.0))
  }

  // ── the exported artefact, read as JSON ────────────────────────────────────

  /// `…/Sources/SentryContent/Resources/content.json`, located from this file rather
  /// than from the working directory, so it survives being run from anywhere — the
  /// same trick `TuningLiteralGuardTests` uses to find the engine sources.
  static var contentJSON: URL {
    URL(fileURLWithPath: #filePath)  // …/Tests/EngineTests/<this file>
      .deletingLastPathComponent()  // …/Tests/EngineTests
      .deletingLastPathComponent()  // …/Tests
      .deletingLastPathComponent()  // …/SentryCore (package root)
      .appendingPathComponent("Sources")
      .appendingPathComponent("SentryContent")
      .appendingPathComponent("Resources")
      .appendingPathComponent("content.json")
  }

  static func exportedLeaves() throws -> [String: Double] {
    let root = try JSONSerialization.jsonObject(with: try Data(contentsOf: contentJSON))
    guard let object = root as? [String: Any], let tuning = object["tuning"] else {
      throw ExportShape.noTuningBlock
    }
    var leaves: [String: Double] = [:]
    flatten(tuning, prefix: "", into: &leaves)
    return leaves
  }

  enum ExportShape: Error { case noTuningBlock }

  private static func flatten(_ node: Any, prefix: String, into out: inout [String: Double]) {
    if let object = node as? [String: Any] {
      for (key, value) in object {
        flatten(value, prefix: prefix.isEmpty ? key : "\(prefix).\(key)", into: &out)
      }
    } else if let number = node as? NSNumber {
      out[prefix] = number.doubleValue
    }
  }
}
