import Foundation

/// The daily board, PRECOMPUTED at export — 730 days (D6).
///
/// No PRNG is ported to Swift: `fnv1a32` + `xorshift32` + rejection sampling depend
/// on JS `Math.imul` and `>>> 0` semantics, and the board is a pure function of the
/// date anyway. Past the horizon the app wraps
/// `daysSince(horizonStart) mod days.count` — deterministic and documented.
public struct DailyCalendar: Codable, Sendable, Hashable {

  /// The daily shift's `ShiftDef`, minus the board (S9). `{date}` interpolates the
  /// player-facing date into `label`; the id is `idPrefix` + the ISO date.
  public struct ShiftTemplate: Codable, Sendable, Hashable {
    public let idPrefix: String
    public let label: String
    public let note: String?
    public let unlockStanding: Int
    /// R3 put this on the template precisely so `dailyShift(on:)` is a field copy and
    /// not a Swift literal sitting next to the copied fields. It was exported and
    /// never read (P1-10); it is read now.
    public let requiresRedRun: Bool
    public let kind: ShiftKind
  }

  /// One precomputed board.
  public struct Day: Codable, Sendable, Hashable, Identifiable {
    /// `"2026-09-05"`.
    public let date: String
    public let caseIds: [String]

    public var id: String { date }
  }

  public let schemaVersion: Int
  public let contentHash: String
  /// `"2026-09-05"` — day 0 of the horizon.
  public let horizonStart: String
  public let shiftTemplate: ShiftTemplate
  public let days: [Day]

  /// The board for `date`, wrapping past the horizon. `nil` only if the calendar is
  /// empty or `horizonStart` is unparseable — neither is reachable in a shipped bundle.
  public func day(on date: Date, calendar: Calendar = .current) -> Day? {
    guard !days.isEmpty, let start = Self.date(fromISO: horizonStart, calendar: calendar) else {
      return nil
    }
    let from = calendar.startOfDay(for: start)
    let to = calendar.startOfDay(for: date)
    guard let elapsed = calendar.dateComponents([.day], from: from, to: to).day else { return nil }
    let count = days.count
    let index = ((elapsed % count) + count) % count
    return days[index]
  }

  /// `"2026-09-05"` for `date` in `calendar` — the id half of the daily shift, and
  /// the key the once-a-day standing award is stamped with (DESIGN §4.2).
  public static func isoDay(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  /// The inverse of `isoDay` — midnight on an exported `"YYYY-MM-DD"`.
  public static func date(fromISO iso: String, calendar: Calendar = .current) -> Date? {
    let parts = iso.split(separator: "-")
    guard parts.count == 3,
          let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return calendar.date(from: components)
  }
}
