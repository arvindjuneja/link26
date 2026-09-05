import Foundation
import SentryContent

/// `content.json`, decoded 1:1. The generated file; never hand-edited.
public struct ContentBundle: Codable, Sendable, Hashable {
  public let schemaVersion: Int
  /// `"sha256:<hex>"` over the canonical JSON of everything else. Identical across
  /// all ten generated files — that is what proves they were exported together.
  public let contentHash: String
  /// `DISPOSITIONS` order — the call-sheet button order.
  public let dispositions: [Disposition]
  public let sources: [DataSource]
  public let cases: [SocCase]
  public let shifts: [ShiftDef]
  public let ranks: [Rank]
  public let kit: [KitItem]
  public let tuning: Tuning
}

/// The decoded content, with the lookups the app and the engine index by.
///
/// `bundled` is a `static let` of a `Sendable` struct — thread-safe via `swift_once`
/// under `.swiftLanguageMode(.v6)`, with no actor and no lock. A decode failure is a
/// programmer error and traps with the underlying `DecodingError`; `ContentTests`
/// makes that unreachable in a shipped build.
public struct ContentPack: Sendable {
  public let schemaVersion: Int
  public let contentHash: String
  public let dispositions: [Disposition]
  public let sources: [DataSource]
  /// Every case, with `sources` already expanded from `sourceIds` (D3).
  public let cases: [SocCase]
  public let shifts: [ShiftDef]
  public let ranks: [Rank]
  public let kit: [KitItem]
  public let tuning: Tuning
  public let copy: CopyPack
  public let daily: DailyCalendar

  public let casesByID: [String: SocCase]
  public let sourcesByID: [String: DataSource]
  public let shiftsByID: [String: ShiftDef]

  public init(bundle: ContentBundle, copy: CopyPack, daily: DailyCalendar) {
    let sourcesByID = Dictionary(uniqueKeysWithValues: bundle.sources.map { ($0.id, $0) })
    let expanded = bundle.cases.map { $0.expandingSources(from: sourcesByID) }

    self.schemaVersion = bundle.schemaVersion
    self.contentHash = bundle.contentHash
    self.dispositions = bundle.dispositions
    self.sources = bundle.sources
    self.cases = expanded
    self.shifts = bundle.shifts
    self.ranks = bundle.ranks
    self.kit = bundle.kit
    self.tuning = bundle.tuning
    self.copy = copy
    self.daily = daily
    self.sourcesByID = sourcesByID
    self.casesByID = Dictionary(uniqueKeysWithValues: expanded.map { ($0.id, $0) })
    self.shiftsByID = Dictionary(uniqueKeysWithValues: bundle.shifts.map { ($0.id, $0) })
  }

  // ── lookups ────────────────────────────────────────────────────────────────

  public func `case`(_ id: String) -> SocCase? { casesByID[id] }

  public func shift(_ id: String) -> ShiftDef? { shiftsByID[id] }

  /// A case that is not in the bundle — the inline sets of `grades-synthetic.json`
  /// and `scoring.json` — with its `sources` resolved against this catalogue.
  public func expanded(_ socCase: SocCase) -> SocCase {
    socCase.expandingSources(from: sourcesByID)
  }

  /// The daily board as a `ShiftDef`, built from `daily.shiftTemplate` (S9).
  ///
  /// The id and the label carry the **requested** date, so a player two years past
  /// the horizon still gets one board per calendar day and the once-a-day standing
  /// award still keys correctly; only the case list wraps (D6). `requiresRedRun` is
  /// `false` like every exported shift — this build is blue-only (B1).
  public func dailyShift(on date: Date, calendar: Calendar = .current) -> ShiftDef {
    let template = daily.shiftTemplate
    let iso = DailyCalendar.isoDay(date, calendar: calendar)
    return ShiftDef(
      id: template.idPrefix + iso,
      label: copy.render(template.label, ["date": Self.playerFacingDate(date, calendar: calendar)]),
      caseIds: daily.day(on: date, calendar: calendar)?.caseIds ?? [],
      unlockStanding: template.unlockStanding,
      requiresRedRun: false,
      note: template.note,
      kind: template.kind)
  }

  /// `"Fri 05 Sep"` — the `{date}` run of the daily label (DESIGN §4.2). Formatted
  /// through ICU on a fixed `en_US_POSIX` locale, so the weekday and month names
  /// come from the system rather than being authored here, and so the string does
  /// not shift under the device locale while every other line of copy is English.
  private static func playerFacingDate(_ date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "EEE dd MMM"
    return formatter.string(from: date)
  }

  // ── the bundled content ────────────────────────────────────────────────────

  public static let bundled = ContentPack(
    bundle: load("content", as: ContentBundle.self),
    copy: load("copy", as: CopyPack.self),
    daily: load("daily", as: DailyCalendar.self))

  private static func load<T: Decodable>(_ name: String, as type: T.Type) -> T {
    guard let url = SentryContent.bundle.url(forResource: name, withExtension: "json") else {
      fatalError("SentryContent is missing \(name).json — run `npm run soc:export`")
    }
    do {
      return try JSONDecoder().decode(type, from: try Data(contentsOf: url))
    } catch {
      fatalError("\(name).json does not match the Swift schema: \(error)")
    }
  }
}
