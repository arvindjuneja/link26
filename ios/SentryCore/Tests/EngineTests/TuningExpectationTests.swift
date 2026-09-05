import Foundation
import Testing

@testable import SentryCore

/// The hardcoded table D7 asks for: `Engine/` reads every number from
/// `content.tuning`, so a designer retune is a re-export and zero Swift — and this
/// suite is what makes a *silent* retune loud in review. It is deliberately a
/// transcription: if a number here disagrees with the export, one of the two was
/// changed without the other, and the diff says which.
///
/// There are exactly **29** tuning numbers (S8): trace 5 · bpm 4 ·
/// timeBudgetDefault 1 · grade 8 · shift 2 · career 6 · heartbeat 3. The second
/// test walks the encoded tuning tree and asserts the set of leaves is exactly
/// these 29 paths, so a thirtieth number cannot be added without a pin.
@Suite("Tuning expectations")
struct TuningExpectationTests {

  /// One pinned number: where it lives in `content.json`, what the Swift property
  /// says, and what the founder signed off. `Double` throughout — every value here
  /// is exactly representable, so `==` is exact (D13).
  struct Pin: Sendable, CustomTestStringConvertible {
    let path: String
    let actual: Double
    let expected: Double
    var testDescription: String { path }
  }

  static let pins: [Pin] = {
    let t = ContentPack.bundled.tuning
    func pin(_ path: String, _ actual: Int, _ expected: Double) -> Pin {
      Pin(path: path, actual: Double(actual), expected: expected)
    }
    return [
      // trace · 5
      pin("trace.min", t.trace.min, 0),
      pin("trace.max", t.trace.max, 100),
      pin("trace.alert", t.trace.alert, 25),
      pin("trace.hunt", t.trace.hunt, 50),
      pin("trace.lockdown", t.trace.lockdown, 80),
      // bpm · 4
      pin("bpm.CALM", t.bpm.CALM, 50),
      pin("bpm.ALERT", t.bpm.ALERT, 76),
      pin("bpm.HUNT", t.bpm.HUNT, 112),
      pin("bpm.LOCKDOWN", t.bpm.LOCKDOWN, 150),
      // timeBudgetDefault · 1
      pin("timeBudgetDefault", t.timeBudgetDefault, 90),
      // grade · 8
      pin("grade.tpMissedBreach", t.grade.tpMissedBreach, 30),
      pin("grade.tpUnderContainBreach", t.grade.tpUnderContainBreach, 10),
      pin("grade.tpOverContainNoise", t.grade.tpOverContainNoise, 12),
      pin("grade.fpEscalateT2Noise", t.grade.fpEscalateT2Noise, 12),
      pin("grade.fpEscalateIsolateNoise", t.grade.fpEscalateIsolateNoise, 20),
      pin("grade.btpClosedAsFpNoise", t.grade.btpClosedAsFpNoise, 4),
      pin("grade.btpEscalateT2Noise", t.grade.btpEscalateT2Noise, 14),
      pin("grade.btpIsolateNoise", t.grade.btpIsolateNoise, 24),
      // shift · 2
      Pin(path: "shift.cleanAccuracy", actual: t.shift.cleanAccuracy, expected: 0.8),
      pin("shift.breachedMissedDetections", t.shift.breachedMissedDetections, 2),
      // career · 6
      pin("career.cashPerCorrect", t.career.cashPerCorrect, 50),
      pin("career.cleanBonus", t.career.cleanBonus, 150),
      pin("career.standingClean", t.career.standingClean, 40),
      pin("career.standingRough", t.career.standingRough, 15),
      pin("career.standingBreached", t.career.standingBreached, 5),
      pin("career.redRunCut", t.career.redRunCut, 150),
      // heartbeat · 3
      pin("heartbeat.minPeriodMs", t.heartbeat.minPeriodMs, 400),
      pin("heartbeat.autoSuspendMs", t.heartbeat.autoSuspendMs, 40000),
      pin("heartbeat.dubOffsetMs", t.heartbeat.dubOffsetMs, 120),
    ]
  }()

  @Test(
    "the exported tuning still holds its pinned value",
    arguments: TuningExpectationTests.pins)
  func pinnedValue(_ pin: Pin) {
    #expect(pin.actual == pin.expected, "\(pin.path)")
  }

  @Test("there are exactly 29 pinned numbers")
  func pinCount() {
    #expect(Self.pins.count == 29)
    #expect(Set(Self.pins.map(\.path)).count == 29)
  }

  /// The structural half: encode the tuning and walk it, so a number added to
  /// `ExportedTuning` without a pin here fails rather than shipping unread.
  @Test("the encoded tuning tree is exactly the pinned set")
  func encodedLeavesMatchThePins() throws {
    let data = try JSONEncoder().encode(ContentPack.bundled.tuning)
    let root = try JSONSerialization.jsonObject(with: data)
    var leaves: [String: Double] = [:]
    Self.flatten(root, prefix: "", into: &leaves)

    #expect(Set(leaves.keys) == Set(Self.pins.map(\.path)))
    #expect(leaves.count == 29)
    for pin in Self.pins {
      #expect(leaves[pin.path] == pin.expected, "\(pin.path) as encoded")
    }
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
