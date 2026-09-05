import Foundation
import Testing

@testable import SentryCore

/// SPEC.md §3.6 — the content is internally consistent, and it is the *same* export
/// as the fixtures it will be graded against.
@Suite("Integrity")
struct IntegrityTests {

  // ── one export, ten files ──────────────────────────────────────────────────

  @Test("schemaVersion is 1 and contentHash is identical across all ten files")
  func oneExport() throws {
    let pack = Bundled.pack
    var stamps: [(String, Int, String)] = [
      ("content.json", pack.schemaVersion, pack.contentHash),
      ("copy.json", pack.copy.schemaVersion, pack.copy.contentHash),
      ("daily.json", pack.daily.schemaVersion, pack.daily.contentHash),
    ]
    for name in Bundled.fixtureNames {
      let probe = try Bundled.decodeFixture(name, as: Bundled.StampProbe.self)
      stamps.append(("\(name).json", probe.schemaVersion, probe.contentHash))
    }

    #expect(stamps.count == 10)
    for (name, version, hash) in stamps {
      #expect(version == 1, "\(name) schemaVersion")
      #expect(hash == pack.contentHash, "\(name) contentHash")
    }
  }

  // ── per case ───────────────────────────────────────────────────────────────

  @Test("every case is internally consistent", arguments: ContentPack.bundled.cases)
  func caseIntegrity(_ socCase: SocCase) {
    let sourceIds = Set(socCase.sourceIds)
    #expect(!socCase.sourceIds.isEmpty)
    #expect(Set(socCase.keySourceIds).isSubset(of: sourceIds))
    #expect(socCase.evidence.allSatisfy { sourceIds.contains($0.sourceId) })
    #expect(sourceIds.allSatisfy { Bundled.pack.sourcesByID[$0] != nil })

    // The disposition the case calls correct must encode the case's own truth.
    #expect(socCase.correctDisposition.verdict == socCase.truth)
    // …and the acceptables are the *other* defensible calls, never a restatement.
    #expect(!socCase.acceptableDispositions.contains(socCase.correctDisposition))
    #expect(Set(socCase.acceptableDispositions).count == socCase.acceptableDispositions.count)

    #expect(!socCase.why.isEmpty)
    #expect(!socCase.learn.concept.isEmpty)
    #expect(socCase.evidence.map(\.id).count == Set(socCase.evidence.map(\.id)).count)
  }

  @Test("case, source and shift ids are unique")
  func uniqueIDs() {
    let pack = Bundled.pack
    #expect(Set(pack.cases.map(\.id)).count == pack.cases.count)
    #expect(Set(pack.sources.map(\.id)).count == pack.sources.count)
    #expect(Set(pack.shifts.map(\.id)).count == pack.shifts.count)
  }

  /// The two long fields, to the character. A re-encode that normalises an entity or
  /// a dash breaks here rather than in a screenshot six screens later.
  @Test("the two known-long fields have their exact character counts")
  func longFieldLengths() throws {
    let departing = try #require(Bundled.pack.case("soc-insider-departing"))
    let unsanctioned = try #require(Bundled.pack.case("soc-handoff-unsanctioned"))
    #expect(departing.why.count == 559)
    #expect(unsanctioned.why.count == 566)
  }

  // ── per shift ──────────────────────────────────────────────────────────────

  @Test("every shift's caseIds resolve", arguments: ContentPack.bundled.shifts)
  func shiftCasesResolve(_ shift: ShiftDef) {
    #expect(!shift.caseIds.isEmpty)
    #expect(shift.caseIds.allSatisfy { Bundled.pack.case($0) != nil })
    #expect(Set(shift.caseIds).count == shift.caseIds.count)
  }

  /// §3.6 asks for all three verdicts on every campaign shift. Four of the five do.
  /// Shift 4 is a contracted red team's board seen from the blue seat, and it is
  /// authored as Benign-TP / Benign-TP / TP — the whole read is "was this engagement
  /// sanctioned", so there is no false positive to have. The exemption is pinned
  /// here so a content change to it is loud rather than silent.
  @Test("campaign shifts teach the whole taxonomy")
  func verdictCoverage() {
    for shift in Bundled.pack.shifts where shift.kind == .campaign {
      let verdicts = Set(shift.caseIds.compactMap { Bundled.pack.case($0)?.truth })
      if shift.id == "handoff-shift" {
        #expect(verdicts == [.benignTruePositive, .truePositive])
      } else {
        #expect(verdicts == Set(SocVerdict.allCases), "\(shift.id) verdict coverage")
      }
    }
  }

  @Test("every case appears on at least one campaign shift")
  func everyCaseIsPlayable() {
    let scheduled = Set(Bundled.pack.shifts.flatMap(\.caseIds))
    #expect(scheduled == Set(Bundled.pack.cases.map(\.id)))
  }

  @Test("the three handoff cases are the ones carrying a handoff ref")
  func handoffCases() {
    let withRef = Bundled.pack.cases.filter { $0.handoff != nil }.map(\.id)
    let onShift4 = Bundled.pack.shift("handoff-shift")?.caseIds ?? []
    #expect(withRef.count == 3)
    #expect(Set(withRef) == Set(onShift4))
  }

  // ── ranks and kit ──────────────────────────────────────────────────────────

  @Test("the rank ladder is ascending and opens at zero standing")
  func ranks() throws {
    let ranks = Bundled.pack.ranks
    #expect(ranks.first?.min == 0)
    #expect(ranks.map(\.min) == ranks.map(\.min).sorted())
    #expect(Set(ranks.map(\.id)).count == ranks.count)
    #expect(Bundled.pack.kit.allSatisfy { $0.cost > 0 })
  }

  // ── copy is total ──────────────────────────────────────────────────────────

  @Test("every keyed copy table covers its whole closed enum")
  func copyTablesAreTotal() {
    let copy = Bundled.copy
    #expect(Set(copy.outcomes.keys) == Set(OutcomeKey.allCases))
    #expect(Set(copy.verdictLabels.keys) == Set(SocVerdict.allCases))
    #expect(Set(copy.dispositionMeta.keys) == Set(Disposition.allCases))
    #expect(Set(copy.gradeMeta.keys) == Set(ShiftGrade.allCases))
    #expect(Set(copy.meters.keys) == Set(CopyPack.MeterKey.allCases))
    #expect(Set(copy.handler.senders.keys) == Set(CopyPack.SenderID.allCases))
    #expect(copy.coachSteps.count == 3)
    #expect(copy.coachSteps.last?.advance == .terminal)
    #expect(!copy.chrome.isEmpty)
  }

  /// S11: the briefing's meter row and the standalone meter table are one dataset.
  @Test("intro.meters and copy.meters agree")
  func metersAgree() throws {
    let copy = Bundled.copy
    #expect(copy.intro.meters.count == copy.meters.count)
    for meter in copy.intro.meters {
      let standalone = try #require(copy.meters[meter.key])
      #expect(standalone.label == meter.label)
      #expect(standalone.fear == meter.fear)
    }
  }

  /// Every severity the corpus actually authors has a chip; the fallback covers the rest.
  @Test("every authored tone value resolves")
  func tonesResolve() {
    let copy = Bundled.copy
    for socCase in Bundled.pack.cases {
      #expect(copy.severityMeta.entries[socCase.toolSeverity.rawValue] != nil)
      #expect(socCase.toolSeverity.isKnown)
      #expect(socCase.archetype.isKnown)
      #expect(socCase.evidence.allSatisfy { $0.weight.isKnown })
    }
    for template in copy.handler.templates.values {
      #expect(copy.handlerToneMeta.entries[template.tone.rawValue] != nil)
      #expect(template.tone.isKnown)
    }
  }

  /// D5: the pinned paragraphs arrived as colour runs, not as flat strings.
  @Test("the pinned paragraphs carry tone runs")
  func richTextSurvived() {
    let copy = Bundled.copy
    for paragraph in [copy.intro.taxonomy, copy.intro.severity, copy.ladder.body,
                      copy.intro.handoff.blueOnly, copy.intro.handoff.redSeat] {
      #expect(paragraph.count > 1)
      #expect(paragraph.contains { $0.tone != nil })
      #expect(!paragraph.plainText.isEmpty)
    }
  }

  /// §11 rule 10, on the artefact rather than on the source: the shipped copy never
  /// states a pay figure or a hiring claim. The exporter guards this too (B4); this
  /// is the same net one layer down, where the app actually reads.
  @Test("no pay figure or hiring claim reaches the decoded copy")
  func credibilityGuardrail() throws {
    let pattern =
      #"\$\s?\d|\bsalar(y|ies)\b|\bper year\b|\bpay\b\s*(range|band)|\b(USD|EUR|PLN)\b"#
    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    var haystack: [String] = []
    haystack.append(contentsOf: Bundled.copy.chrome.values)
    haystack.append(contentsOf: Bundled.copy.outcomes.values)
    haystack.append(contentsOf: Bundled.copy.verdictLabels.values)
    haystack.append(contentsOf: Bundled.copy.gradeMeta.values.map { $0.label + " " + $0.line })
    haystack.append(contentsOf: Bundled.copy.dispositionMeta.values.map { $0.label + " " + $0.sub })
    haystack.append(contentsOf: Bundled.copy.handler.templates.values.map { $0.subject + " " + $0.body })
    haystack.append(Bundled.copy.ladder.note)
    haystack.append(Bundled.copy.ladder.body.plainText)
    haystack.append(Bundled.copy.firstRun.body)
    haystack.append(Bundled.copy.about.fiction)
    haystack.append(Bundled.copy.about.privacy)
    haystack.append(Bundled.copy.about.promise)
    haystack.append(Bundled.copy.about.credits)
    haystack.append(contentsOf: Bundled.pack.cases.map { $0.why + " " + $0.learn.concept })

    for text in haystack {
      let range = NSRange(text.startIndex..., in: text)
      #expect(
        regex.firstMatch(in: text, range: range) == nil,
        "credibility guardrail hit: \(text)")
    }
  }
}
