import Foundation

/// A log the analyst can pull during triage. The teaching point is the question
/// it answers, not the tool that serves it.
public struct DataSource: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let label: String
  public let question: String
  /// Shift-minutes consumed to pull it.
  public let cost: Int

  public init(id: String, label: String, question: String, cost: Int) {
    self.id = id
    self.label = label
    self.question = question
    self.cost = cost
  }
}

/// A finding revealed when its source is queried. Never a runnable command — a log line.
public struct SocEvidence: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let sourceId: String
  public let label: String
  public let detail: String
  public let weight: EvidenceWeight

  public init(id: String, sourceId: String, label: String, detail: String, weight: EvidenceWeight) {
    self.id = id
    self.sourceId = sourceId
    self.label = label
    self.detail = detail
    self.weight = weight
  }
}

/// The "learn it for real" debrief block. Flattened by the exporter (`mitre.id` →
/// `mitreId`) so `Codable` synthesis needs no custom keys (§3.4). MITRE ATT&CK ids
/// are lookup labels only.
public struct LearnForReal: Codable, Sendable, Hashable {
  public let concept: String
  public let mitreId: String?
  public let mitreName: String?
  public let pointer: String?

  public init(concept: String, mitreId: String?, mitreName: String?, pointer: String?) {
    self.concept = concept
    self.mitreId = mitreId
    self.mitreName = mitreName
    self.pointer = pointer
  }
}

/// Set on the three cases generated from a red-seat run — the operator's tradecraft
/// became the analyst's evidence. Generated at export time; `caseFromRedRun` is
/// never ported to Swift.
public struct HandoffRef: Codable, Sendable, Hashable {
  public let fromRun: String
  public let `operator`: String

  public init(fromRun: String, operator: String) {
    self.fromRun = fromRun
    self.operator = `operator`
  }
}

/// One alert on the board, with its ground truth and its whole investigation surface.
///
/// Decodes 1:1 from `content.json`'s `cases[]`. `sources` is the single exception:
/// it is **not** in the JSON — the export replaced 135 inline source objects with
/// `sourceIds` into the 26-entry catalogue (D3) — so it is expanded after decode by
/// `ContentPack` and left out of `CodingKeys`, which keeps re-encoding byte-faithful
/// to the exported shape.
public struct SocCase: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let archetype: SocArchetype
  public let alertTitle: String
  public let detectionRule: String
  public let toolSeverity: ToolSeverity
  public let trigger: String
  public let asset: String
  public let sourceIds: [String]
  /// The sources that actually answer this case — the investigation-quality yardstick.
  public let keySourceIds: [String]
  public let evidence: [SocEvidence]
  public let truth: SocVerdict
  public let correctDisposition: Disposition
  /// `[]`, never absent. Defensible-but-imperfect calls earn partial credit.
  public let acceptableDispositions: [Disposition]
  public let why: String
  public let learn: LearnForReal
  public let handoff: HandoffRef?

  /// `sourceIds` resolved against the catalogue, in `sourceIds` order. Empty until
  /// `ContentPack` expands it; see `expandingSources(from:)`.
  public internal(set) var sources: [DataSource] = []

  private enum CodingKeys: String, CodingKey {
    case id, archetype, alertTitle, detectionRule, toolSeverity, trigger, asset
    case sourceIds, keySourceIds, evidence, truth, correctDisposition
    case acceptableDispositions, why, learn, handoff
  }

  public init(
    id: String, archetype: SocArchetype, alertTitle: String, detectionRule: String,
    toolSeverity: ToolSeverity, trigger: String, asset: String,
    sourceIds: [String], keySourceIds: [String], evidence: [SocEvidence],
    truth: SocVerdict, correctDisposition: Disposition, acceptableDispositions: [Disposition],
    why: String, learn: LearnForReal, handoff: HandoffRef?, sources: [DataSource] = []
  ) {
    self.id = id
    self.archetype = archetype
    self.alertTitle = alertTitle
    self.detectionRule = detectionRule
    self.toolSeverity = toolSeverity
    self.trigger = trigger
    self.asset = asset
    self.sourceIds = sourceIds
    self.keySourceIds = keySourceIds
    self.evidence = evidence
    self.truth = truth
    self.correctDisposition = correctDisposition
    self.acceptableDispositions = acceptableDispositions
    self.why = why
    self.learn = learn
    self.handoff = handoff
    self.sources = sources
  }

  /// A copy whose `sources` are resolved against `catalogue`. Used by `ContentPack`
  /// on the bundled cases, and by the golden suites on the fixture-inline cases of
  /// `grades-synthetic.json` / `scoring.json`, which are not in the bundle.
  public func expandingSources(from catalogue: [String: DataSource]) -> SocCase {
    var expanded = self
    expanded.sources = sourceIds.compactMap { catalogue[$0] }
    return expanded
  }

  /// The findings a given source reveals, in authored order.
  public func findings(from sourceId: String) -> [SocEvidence] {
    evidence.filter { $0.sourceId == sourceId }
  }
}

/// Campaign or daily. Closed: the hub, the unlock ladder and the daily-done hook
/// all branch on it.
public enum ShiftKind: String, Codable, Sendable, Hashable, CaseIterable {
  case campaign
  case daily
}

/// A board: the ordered alerts, plus what it costs to open it.
///
/// `requiresRedRun` is `false` on every exported shift — the iOS build is blue-only
/// and the exporter applies the 0/40/80/120/160 standing ladder (B1/D4). The field
/// stays in the schema because the web is the other consumer.
public struct ShiftDef: Codable, Sendable, Hashable, Identifiable {
  public let id: String
  public let label: String
  public let caseIds: [String]
  public let unlockStanding: Int
  public let requiresRedRun: Bool
  public let note: String?
  public let kind: ShiftKind

  public init(
    id: String, label: String, caseIds: [String], unlockStanding: Int,
    requiresRedRun: Bool, note: String?, kind: ShiftKind
  ) {
    self.id = id
    self.label = label
    self.caseIds = caseIds
    self.unlockStanding = unlockStanding
    self.requiresRedRun = requiresRedRun
    self.note = note
    self.kind = kind
  }
}
