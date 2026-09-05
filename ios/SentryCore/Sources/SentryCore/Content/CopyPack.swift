import Foundation

/// Every letter the app draws (S1), decoded 1:1 from `copy.json`.
///
/// No screen in `SentrySOC` authors a string: `Sources/Screens/**` and
/// `Sources/Components/**` carry no string literal containing a letter, and the
/// release guard greps for it. Copy changes are therefore an export, not a build.
public struct CopyPack: Codable, Sendable, Hashable {

  // ── nested shapes ──────────────────────────────────────────────────────────

  /// A call button: what it says, what it means, and the colour run it carries.
  public struct DispositionMeta: Codable, Sendable, Hashable {
    public let label: String
    public let sub: String
    public let tone: Tone
  }

  /// The three debrief headlines.
  public struct DebriefHeadlines: Codable, Sendable, Hashable {
    public let good: String
    public let verdictOnly: String
    public let wrong: String
  }

  /// A shift grade's stamp and its one line of feedback.
  public struct GradeMeta: Codable, Sendable, Hashable {
    public let label: String
    public let line: String
    public let tone: Tone
  }

  /// A chip label plus the run it renders in.
  public struct ToneMeta: Codable, Sendable, Hashable {
    public let label: String
    public let tone: Tone

    public init(label: String, tone: Tone) {
      self.label = label
      self.tone = tone
    }
  }

  /// A lenient lookup with an authored fallback tone (S5) — an unknown severity or
  /// handler tone renders instead of failing the decode.
  public struct ToneTable: Codable, Sendable, Hashable {
    public let entries: [String: ToneMeta]
    public let fallback: Tone

    /// The chip for `rawValue`. An unknown value keeps its own text and takes the
    /// fallback run; nothing here is authored copy, only a lookup and a case fold.
    public func meta(for rawValue: String) -> ToneMeta {
      entries[rawValue] ?? ToneMeta(label: rawValue, tone: fallback)
    }
  }

  /// One pressure meter, as the briefing introduces it.
  public struct Meter: Codable, Sendable, Hashable {
    public let label: String
    /// What it costs you — the fear, not the formula.
    public let fear: String
  }

  /// The briefing's meter row, which is ordered and keyed.
  public struct IntroMeter: Codable, Sendable, Hashable {
    public let key: MeterKey
    public let label: String
    public let fear: String
  }

  /// The 08:00 handover.
  public struct Intro: Codable, Sendable, Hashable {
    public let eyebrow: String
    /// Carries `{n}` — the alert count.
    public let title: String
    public let taxonomy: [RichSegment]
    public let severity: [RichSegment]
    public let meters: [IntroMeter]
    public let handoff: Handoff
    public let cta: String
    public let disclaimer: String

    /// Shift 4's re-voiced paragraph, in both seat framings (DESIGN §3.2). iOS
    /// always shows `blueOnly`.
    public struct Handoff: Codable, Sendable, Hashable {
      public let blueOnly: [RichSegment]
      public let redSeat: [RichSegment]
    }
  }

  /// Where a coach step points.
  public enum CoachAnchor: String, Codable, Sendable, Hashable, CaseIterable {
    case sources
    case evidence
    case call
  }

  /// How a coach step ends (S4). `terminal` is the last step — the first real call closes it.
  public enum CoachAdvance: String, Codable, Sendable, Hashable, CaseIterable {
    case onFirstSourcePulled = "on-first-source-pulled"
    case button
    case terminal
  }

  public struct CoachStep: Codable, Sendable, Hashable {
    public let anchor: CoachAnchor
    public let title: String
    public let body: String
    public let button: String?
    public let advance: CoachAdvance
  }

  /// The career-ladder panel. Fiction, never a hiring or pay claim.
  public struct Ladder: Codable, Sendable, Hashable {
    public let eyebrow: String
    public let body: [RichSegment]
    public let note: String
  }

  /// The 16:00 handover's two derived lines. `investigationLine` carries `{pct}`,
  /// `blindLine` carries `{blind}`.
  public struct Summary: Codable, Sendable, Hashable {
    public let eyebrow: String
    public let investigationLine: String
    public let blindLine: String
  }

  /// The one-time fiction gate.
  public struct FirstRun: Codable, Sendable, Hashable {
    public let title: String
    public let body: String
    public let cta: String
  }

  public struct About: Codable, Sendable, Hashable {
    public let fiction: String
    public let privacy: String
    public let promise: String
    public let credits: String
  }

  /// Which meter a line is about.
  public enum MeterKey: String, Codable, Sendable, Hashable, CaseIterable, CodingKeyRepresentable {
    case breach
    case noise
    case time
  }

  /// Who a message is from.
  public enum SenderID: String, Codable, Sendable, Hashable, CaseIterable, CodingKeyRepresentable {
    case vale
    case mercer
  }

  public struct Sender: Codable, Sendable, Hashable {
    public let from: String
    public let role: String
  }

  /// A message body before interpolation. Placeholders: `{gap} {rank} {cash} {item} {queue}`.
  public struct HandlerTemplate: Codable, Sendable, Hashable {
    public let sender: SenderID
    public let subject: String
    public let body: String
    public let tone: HandlerTone
  }

  public struct Handler: Codable, Sendable, Hashable {
    public let senders: [SenderID: Sender]
    public let templates: [String: HandlerTemplate]
  }

  // ── the file ───────────────────────────────────────────────────────────────

  public let schemaVersion: Int
  public let contentHash: String
  /// Screen chrome — labels, CTAs, eyebrows (S1). Free-form keys by design.
  public let chrome: [String: String]
  public let verdictLabels: [SocVerdict: String]
  public let dispositionMeta: [Disposition: DispositionMeta]
  /// All 11 (D12). A key outside `OutcomeKey` fails the decode and names itself.
  public let outcomes: [OutcomeKey: String]
  public let debriefHeadlines: DebriefHeadlines
  public let gradeMeta: [ShiftGrade: GradeMeta]
  public let severityMeta: ToneTable
  public let handlerToneMeta: ToneTable
  public let intro: Intro
  public let coachSteps: [CoachStep]
  public let ladder: Ladder
  public let summary: Summary
  public let firstRun: FirstRun
  public let about: About
  public let meters: [MeterKey: Meter]
  public let handler: Handler

  // ── lookups ────────────────────────────────────────────────────────────────

  /// The debrief headline for a graded call (D2/D12). Every key is present — the
  /// export asserts the 96-pair `outcomeKey ↔ prose` correspondence and
  /// `IntegrityTests` asserts the map is total — so a miss is a programmer error.
  public func outcomeText(_ key: OutcomeKey) -> String {
    guard let text = outcomes[key] else {
      assertionFailure("copy.json is missing outcome \(key.rawValue)")
      return ""
    }
    return text
  }

  /// A chrome string by key. Missing keys are a programmer error, loud in DEBUG and
  /// blank in Release — never a raw key drawn on screen.
  public func chromeText(_ key: String) -> String {
    guard let text = chrome[key] else {
      assertionFailure("copy.json chrome is missing \(key)")
      return ""
    }
    return text
  }

  /// The severity chip, with the S5 fallback for a severity authored after this build.
  public func severity(_ value: ToolSeverity) -> ToneMeta {
    severityMeta.meta(for: value.rawValue)
  }

  /// The handler-tone chip, with the S5 fallback.
  public func handlerTone(_ tone: HandlerTone) -> ToneMeta {
    handlerToneMeta.meta(for: tone.rawValue)
  }

  /// Named-placeholder interpolation over `{key}` runs, single pass — an inserted
  /// value is never rescanned, and an unrecognised placeholder is left intact so a
  /// missing parameter shows up in review rather than silently blanking a sentence.
  ///
  /// `Career/Templating.swift` renders handler bodies through this.
  public func render(_ template: String, _ params: [String: String]) -> String {
    guard template.contains("{") else { return template }
    var out = ""
    out.reserveCapacity(template.count)
    var rest = Substring(template)
    while let open = rest.firstIndex(of: "{") {
      guard let close = rest[rest.index(after: open)...].firstIndex(of: "}") else { break }
      let key = String(rest[rest.index(after: open)..<close])
      out += rest[rest.startIndex..<open]
      if let value = params[key] {
        out += value
      } else {
        out += rest[open...close]
      }
      rest = rest[rest.index(after: close)...]
    }
    out += rest
    return out
  }
}
