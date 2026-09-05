import Foundation
import Testing

@testable import SentryCore

/// `Trace.status` and `Trace.clamp` against `trace.json` — every level from −5 to
/// 105, plus the clamp edges.
///
/// The band table is where an off-by-one hides: a `>` where the TypeScript has a
/// `>=` moves the LOCKDOWN boundary by one and only shows up on the one shift that
/// lands exactly on it. Every level is pinned rather than a sample.
@Suite("Golden trace")
struct GoldenTraceTests {

  @Test("getTraceStatus matches at every level", arguments: try Golden.traceStatusRows())
  func statusParity(_ row: TraceStatusRow) {
    #expect(
      Trace.status(row.level, Golden.pack.tuning) == row.status,
      "level \(row.level)")
  }

  @Test("clampLevel matches at every edge", arguments: try Golden.traceClampRows())
  func clampParity(_ row: TraceClampRow) {
    #expect(
      Trace.clamp(row.level, Golden.pack.tuning) == row.value,
      "clamp(\(row.level))")
  }

  @Test("the level sweep is unbroken")
  func sweepIsUnbroken() throws {
    let rows = try Golden.traceStatusRows()
    #expect(rows.count == 111)
    #expect(rows.map(\.level) == Array(-5...105))
    #expect(Set(rows.map(\.status)) == Set(TraceStatus.allCases))
  }

  /// The boundaries themselves, read off tuning rather than transcribed: each band
  /// starts exactly at its threshold and the level below it reads one band lower.
  @Test("each band starts exactly at its threshold")
  func boundariesAreInclusive() {
    let t = Golden.pack.tuning
    #expect(Trace.status(t.trace.lockdown, t) == .lockdown)
    #expect(Trace.status(t.trace.lockdown - 1, t) == .hunt)
    #expect(Trace.status(t.trace.hunt, t) == .hunt)
    #expect(Trace.status(t.trace.hunt - 1, t) == .alert)
    #expect(Trace.status(t.trace.alert, t) == .alert)
    #expect(Trace.status(t.trace.alert - 1, t) == .calm)
    #expect(Trace.status(t.trace.min, t) == .calm)
  }

  /// Clamping is total: nothing the engine can add to a meter escapes the band
  /// table, in either direction, which is what keeps `status` total too.
  @Test("clamp is closed over the band table")
  func clampIsClosed() {
    let t = Golden.pack.tuning
    for level in (t.trace.min - 50)...(t.trace.max + 50) {
      let clamped = Trace.clamp(level, t)
      #expect(clamped >= t.trace.min)
      #expect(clamped <= t.trace.max)
    }
    #expect(Trace.clamp(t.trace.min, t) == t.trace.min)
    #expect(Trace.clamp(t.trace.max, t) == t.trace.max)
  }

  /// DV-3: `TraceStatus` is `Comparable`, which is what lets `overallShiftStatus`
  /// pick the worse meter directly instead of through a rank dictionary.
  @Test("the status order is CALM < ALERT < HUNT < LOCKDOWN")
  func statusIsOrdered() {
    #expect(TraceStatus.allCases == [.calm, .alert, .hunt, .lockdown])
    #expect(TraceStatus.calm < .alert)
    #expect(TraceStatus.alert < .hunt)
    #expect(TraceStatus.hunt < .lockdown)
    #expect(TraceStatus.allCases.sorted() == TraceStatus.allCases)
  }
}
