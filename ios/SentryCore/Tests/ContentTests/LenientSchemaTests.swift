import Foundation
import Testing

@testable import SentryCore

/// D10 — closed enums exactly where logic lives, lenient raw values everywhere
/// content grows, unknown keys ignored.
///
/// The promise being tested: authoring a 25th case with a new archetype costs zero
/// Swift, while adding an engine branch fails to decode and names the key.
@Suite("Lenient schema")
struct LenientSchemaTests {

  // ── the synthetic bundle ───────────────────────────────────────────────────

  /// A one-case `content.json` carrying three raw values this build has never seen,
  /// an unknown top-level key and an unknown per-case key.
  static let futureBundleJSON = """
    {
      "schemaVersion": 1,
      "contentHash": "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      "futureTopLevelKey": { "authored": "after this build shipped" },
      "dispositions": ["close-false-positive", "close-benign", "escalate-tier2", "escalate-ir-isolate"],
      "sources": [
        { "id": "edr-process-tree", "label": "EDR · process tree", "question": "what spawned this?", "cost": 8 }
      ],
      "cases": [
        {
          "id": "syn-future",
          "futurePerCaseKey": 42,
          "archetype": "lateral-movement",
          "alertTitle": "Service account authenticating to a host it has never touched",
          "detectionRule": "SIEM · first-seen account/host pair",
          "toolSeverity": "Informational",
          "trigger": "svc-report signed in to HR-FS-01 for the first time.",
          "asset": "HR-FS-01 · service account svc-report",
          "sourceIds": ["edr-process-tree"],
          "keySourceIds": ["edr-process-tree"],
          "evidence": [
            {
              "id": "syn-future-tree",
              "sourceId": "edr-process-tree",
              "label": "No interactive parent",
              "detail": "The session has no interactive parent and no console token.",
              "weight": "circumstantial"
            }
          ],
          "truth": "true-positive",
          "correctDisposition": "escalate-tier2",
          "acceptableDispositions": ["escalate-ir-isolate"],
          "why": "Fixture-only case. It exists to prove that content can grow without a Swift change.",
          "learn": { "concept": "First-seen pairs are a hunt, not a verdict.", "mitreId": null, "mitreName": null, "pointer": null },
          "handoff": null
        }
      ],
      "shifts": [
        {
          "id": "syn-future-shift",
          "label": "Fixture shift",
          "caseIds": ["syn-future"],
          "unlockStanding": 0,
          "requiresRedRun": false,
          "note": null,
          "kind": "campaign"
        }
      ],
      "ranks": [{ "id": "trainee", "label": "Trainee", "min": 0 }],
      "kit": [],
      "tuning": {
        "trace": { "min": 0, "max": 100, "alert": 25, "hunt": 50, "lockdown": 80 },
        "bpm": { "CALM": 50, "ALERT": 76, "HUNT": 112, "LOCKDOWN": 150 },
        "timeBudgetDefault": 90,
        "grade": {
          "tpMissedBreach": 30, "tpUnderContainBreach": 10, "tpOverContainNoise": 12,
          "fpEscalateT2Noise": 12, "fpEscalateIsolateNoise": 20,
          "btpClosedAsFpNoise": 4, "btpEscalateT2Noise": 14, "btpIsolateNoise": 24
        },
        "shift": { "cleanAccuracy": 0.8, "breachedMissedDetections": 2 },
        "career": {
          "cashPerCorrect": 50, "cleanBonus": 150, "standingClean": 40,
          "standingRough": 15, "standingBreached": 5, "redRunCut": 150
        },
        "heartbeat": { "minPeriodMs": 400, "autoSuspendMs": 40000, "dubOffsetMs": 120 },
        "handler": { "inboxCapacity": 4, "redRunNudgeStanding": 90 }
      }
    }
    """

  static func decodeFutureBundle(replacing pairs: [String: String] = [:]) throws -> ContentBundle {
    var json = futureBundleJSON
    for (from, to) in pairs { json = json.replacingOccurrences(of: from, with: to) }
    return try JSONDecoder().decode(ContentBundle.self, from: Data(json.utf8))
  }

  @Test("an unseen archetype, severity and weight decode, and unknown keys are ignored")
  func futureContentLoads() throws {
    let bundle = try Self.decodeFutureBundle()
    let socCase = try #require(bundle.cases.first)

    #expect(socCase.archetype == SocArchetype(rawValue: "lateral-movement"))
    #expect(socCase.toolSeverity == ToolSeverity(rawValue: "Informational"))
    #expect(socCase.evidence.first?.weight == EvidenceWeight(rawValue: "circumstantial"))
    #expect(socCase.archetype.isKnown == false)
    #expect(socCase.toolSeverity.isKnown == false)
    #expect(socCase.evidence.first?.weight.isKnown == false)

    // The closed half still decoded into real cases, so the engine can grade it.
    #expect(socCase.truth == .truePositive)
    #expect(socCase.correctDisposition == .escalateTier2)
    #expect(socCase.correctDisposition.verdict == socCase.truth)
    #expect(socCase.acceptableDispositions == [.escalateIRIsolate])
    #expect(bundle.shifts.first?.kind == .campaign)

    // And the pack builds on it — the same expansion the bundled content gets.
    let pack = ContentPack(bundle: bundle, copy: Bundled.copy, daily: Bundled.daily)
    #expect(pack.case("syn-future")?.sources.map(\.id) == ["edr-process-tree"])
  }

  @Test("an unknown raw value round-trips byte-for-byte")
  func unknownRawValuesRoundTrip() throws {
    let bundle = try Self.decodeFutureBundle()
    let reencoded = try JSONEncoder().encode(bundle)
    let again = try JSONDecoder().decode(ContentBundle.self, from: reencoded)
    #expect(again.cases.first?.archetype.rawValue == "lateral-movement")
    #expect(again.cases.first?.toolSeverity.rawValue == "Informational")
    #expect(again.cases.first?.evidence.first?.weight.rawValue == "circumstantial")
    #expect(again == bundle)
  }

  // ── the closed half fails loudly ───────────────────────────────────────────

  @Test("an unknown verdict fails to decode")
  func unknownVerdictFails() {
    #expect(throws: DecodingError.self) {
      _ = try Self.decodeFutureBundle(replacing: ["\"truth\": \"true-positive\"": "\"truth\": \"maybe-positive\""])
    }
  }

  @Test("an unknown disposition fails to decode")
  func unknownDispositionFails() {
    #expect(throws: DecodingError.self) {
      _ = try Self.decodeFutureBundle(
        replacing: ["\"correctDisposition\": \"escalate-tier2\"": "\"correctDisposition\": \"close-and-hope\""])
    }
  }

  @Test("an unknown shift kind fails to decode")
  func unknownShiftKindFails() {
    #expect(throws: DecodingError.self) {
      _ = try Self.decodeFutureBundle(replacing: ["\"kind\": \"campaign\"": "\"kind\": \"weekly\""])
    }
  }

  /// The companion to the lenient case, and the whole reason `OutcomeKey` is closed:
  /// a twelfth grading branch must stop the build, not render blank prose.
  @Test("an unknown outcomeKey fails to decode")
  func unknownOutcomeKeyFails() {
    let row = """
      {
        "caseId": "soc-ps-cradle", "disposition": "close-false-positive",
        "verdictCorrect": false, "dispositionCorrect": false, "exact": false,
        "breachDelta": 30, "noiseDelta": 0,
        "outcomeKey": "tp.swallowed-whole",
        "outcome": "MISSED DETECTION — a live threat was closed and is now dwelling undetected."
      }
      """
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(GradeRow.self, from: Data(row.utf8))
    }
    // The same row with a real key decodes, so the failure above is the key alone.
    let good = row.replacingOccurrences(of: "tp.swallowed-whole", with: "tp.missed")
    #expect(throws: Never.self) {
      _ = try JSONDecoder().decode(GradeRow.self, from: Data(good.utf8))
    }
  }

  @Test("an unknown outcome key in the copy table fails to decode")
  func unknownOutcomeCopyKeyFails() {
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        [OutcomeKey: String].self,
        from: Data(#"{"tp.missed":"a","tp.swallowed-whole":"b"}"#.utf8))
    }
  }

  @Test("an unknown trace status fails to decode")
  func unknownTraceStatusFails() {
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        TraceStatusRow.self, from: Data(#"{"level":10,"status":"SIMMER"}"#.utf8))
    }
  }

  // ── S5: an unknown severity still renders ──────────────────────────────────

  @Test("an unknown severity renders with the fallback tone")
  func unknownSeverityRenders() throws {
    let copy = Bundled.copy
    let future = ToolSeverity(rawValue: "Informational")
    let chip = copy.severity(future)
    #expect(chip.tone == copy.severityMeta.fallback)
    #expect(chip.label == "Informational")

    // An authored severity keeps its own chip, so the fallback is a fallback.
    let high = try #require(copy.severityMeta.entries["High"])
    #expect(copy.severity(.high) == high)
    #expect(high.tone != copy.severityMeta.fallback)
  }

  @Test("an unknown handler tone renders with the fallback tone")
  func unknownHandlerToneRenders() throws {
    let copy = Bundled.copy
    let chip = copy.handlerTone(HandlerTone(rawValue: "conspiratorial"))
    #expect(chip.tone == copy.handlerToneMeta.fallback)
    #expect(chip.label == "conspiratorial")

    let warm = try #require(copy.handlerToneMeta.entries["warm"])
    #expect(copy.handlerTone(.warm) == warm)
  }

  /// Lenient does not mean untyped: the known statics still compare equal to the
  /// raw values the exporter writes.
  @Test("known statics match their exported raw values")
  func knownStatics() {
    #expect(SocArchetype.encodedPowerShell.rawValue == "encoded-powershell")
    #expect(ToolSeverity.critical.rawValue == "Critical")
    #expect(EvidenceWeight.decisive.rawValue == "decisive")
    #expect(HandlerTone.milestone.rawValue == "milestone")
    #expect(Tone.fuchsia.rawValue == "fuchsia")
    #expect(SocArchetype.known.allSatisfy { $0.isKnown })
    #expect(Set(Bundled.pack.cases.map(\.archetype)).isSubset(of: Set(SocArchetype.known)))
  }
}
