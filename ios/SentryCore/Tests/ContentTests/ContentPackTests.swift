import Foundation
import Testing

@testable import SentryCore

/// `ContentPack.bundled` decodes `content.json` + `copy.json` + `daily.json` and
/// exposes the lookups the app indexes by (C2 acceptance #4).
@Suite("ContentPack")
struct ContentPackTests {

  // ── the bundle ─────────────────────────────────────────────────────────────

  @Test("the bundled pack decodes with the exported counts")
  func counts() {
    let pack = Bundled.pack
    #expect(pack.schemaVersion == 1)
    #expect(pack.contentHash.hasPrefix("sha256:"))
    #expect(pack.sources.count == 26)
    #expect(pack.cases.count == 24)
    #expect(pack.shifts.count == 5)
    #expect(pack.ranks.count == 4)
    #expect(pack.kit.count == 1)
    #expect(pack.dispositions.count == 4)
  }

  @Test("the id lookups are total")
  func lookups() throws {
    let pack = Bundled.pack
    #expect(pack.casesByID.count == 24)
    #expect(pack.sourcesByID.count == 26)
    #expect(pack.shiftsByID.count == 5)
    for socCase in pack.cases { #expect(pack.case(socCase.id)?.id == socCase.id) }
    for shift in pack.shifts { #expect(pack.shift(shift.id)?.id == shift.id) }
    #expect(pack.case("no-such-case") == nil)
    #expect(pack.shift("no-such-shift") == nil)
  }

  /// `DISPOSITIONS` order is load-bearing — it is the call-sheet button order.
  @Test("Disposition.allCases is the exported order")
  func dispositionOrder() {
    #expect(Disposition.allCases == Bundled.pack.dispositions)
    #expect(
      Disposition.allCases.map(\.rawValue) == [
        "close-false-positive", "close-benign", "escalate-tier2", "escalate-ir-isolate",
      ])
  }

  /// DV-3: CALM < ALERT < HUNT < LOCKDOWN, which is what lets `overallShiftStatus`
  /// be `max(a, b)` instead of a rank dictionary.
  @Test("TraceStatus is ordered by pressure")
  func traceOrder() {
    #expect(TraceStatus.calm < .alert)
    #expect(TraceStatus.alert < .hunt)
    #expect(TraceStatus.hunt < .lockdown)
    #expect(max(TraceStatus.alert, .hunt) == .hunt)
    #expect(TraceStatus.allCases.sorted() == [.calm, .alert, .hunt, .lockdown])
  }

  // ── source expansion (D3) ──────────────────────────────────────────────────

  @Test("every case's sources are expanded from sourceIds", arguments: ContentPack.bundled.cases)
  func expansion(_ socCase: SocCase) {
    #expect(socCase.sources.count == socCase.sourceIds.count)
    #expect(socCase.sources.map(\.id) == socCase.sourceIds)
  }

  @Test("a case from outside the bundle expands against the same catalogue")
  func expandingForeignCase() throws {
    let synthetic = try Bundled.decodeFixture("grades-synthetic", as: SyntheticGradeFile.self)
    let raw = try #require(synthetic.cases.first)
    #expect(raw.sources.isEmpty)
    let expanded = Bundled.pack.expanded(raw)
    #expect(expanded.sources.map(\.id) == raw.sourceIds)
  }

  // ── B1: blue-only ──────────────────────────────────────────────────────────

  /// B1. The exporter's blue-only override sets `requiresRedRun: false` on every
  /// shift, and the ladder is 0/40/80/120/160 standing.
  @Test("no shift requires a red run and the ladder is the blue-only one")
  func blueOnlyLadder() {
    #expect(Bundled.pack.shifts.allSatisfy { !$0.requiresRedRun })
    #expect(Bundled.pack.shifts.map(\.unlockStanding) == [0, 40, 80, 120, 160])
    #expect(Bundled.pack.shifts.allSatisfy { $0.kind == .campaign })
  }

  /// The B1 unlock assertion `CareerRules.isUnlocked(CareerState(standing: 160), shift5)`
  /// belongs to C4's `CareerTests` — `CareerRules` is C4's type. What C2 can pin is
  /// the decoded flags the predicate reads: at ⬢160 the last shift is gated on
  /// standing alone, with no red-run clause left to fail.
  @Test("Shift 5 is reachable on standing alone")
  func shiftFiveGate() throws {
    let shift = try #require(Bundled.pack.shifts.last)
    #expect(shift.id == "insider-shift")
    #expect(shift.unlockStanding == 160)
    #expect(shift.requiresRedRun == false)
    #expect(CareerState(standing: 160).standing >= shift.unlockStanding)
  }

  // ── the daily board (D6 / S9) ──────────────────────────────────────────────

  @Test("the daily calendar is 730 five-alert boards that all resolve")
  func dailyCalendar() throws {
    let daily = Bundled.daily
    #expect(daily.schemaVersion == 1)
    #expect(daily.days.count == 730)
    #expect(daily.horizonStart == daily.days.first?.date)
    #expect(daily.days.allSatisfy { $0.caseIds.count == 5 })
    #expect(daily.days.allSatisfy { $0.caseIds.allSatisfy { Bundled.pack.case($0) != nil } })
    #expect(Set(daily.days.map(\.date)).count == daily.days.count)
    #expect(daily.shiftTemplate.kind == .daily)
    #expect(daily.shiftTemplate.unlockStanding == 40)
  }

  @Test("dailyShift builds the board from the template")
  func dailyShiftOnHorizon() throws {
    let daily = Bundled.daily
    let template = daily.shiftTemplate
    let start = try #require(
      DailyCalendar.date(fromISO: daily.horizonStart, calendar: Bundled.utc))

    let shift = Bundled.pack.dailyShift(on: start, calendar: Bundled.utc)
    #expect(shift.id == template.idPrefix + daily.horizonStart)
    #expect(shift.caseIds == daily.days[0].caseIds)
    #expect(shift.kind == .daily)
    #expect(shift.unlockStanding == template.unlockStanding)
    #expect(shift.requiresRedRun == false)   // B1: daily-kind shifts too
    #expect(shift.note == template.note)

    // The label is the template with `{date}` interpolated — never a literal here.
    let prefix = String(template.label.prefix(while: { $0 != "{" }))
    #expect(shift.label.hasPrefix(prefix))
    #expect(!shift.label.contains("{"))
    #expect(shift.label.count > prefix.count)
    // …and what replaced `{date}` reads as a day, in the shape DESIGN §4.2 shows.
    let rendered = String(shift.label.dropFirst(prefix.count))
    #expect(
      rendered.wholeMatch(of: /[A-Z][a-z]{2} \d{2} [A-Z][a-z]{2}/) != nil,
      "daily label date run: \(rendered)")
  }

  /// D6: past the horizon the board wraps, but the id and label stay on the player's
  /// own calendar day, so the once-a-day standing award keys correctly forever.
  @Test("the board wraps past the horizon while the id follows the real date")
  func dailyShiftWraps() throws {
    let daily = Bundled.daily
    let start = try #require(
      DailyCalendar.date(fromISO: daily.horizonStart, calendar: Bundled.utc))
    let wrapped = try #require(
      Bundled.utc.date(byAdding: .day, value: daily.days.count, to: start))

    let day0 = Bundled.pack.dailyShift(on: start, calendar: Bundled.utc)
    let day730 = Bundled.pack.dailyShift(on: wrapped, calendar: Bundled.utc)
    #expect(day730.caseIds == day0.caseIds)
    #expect(day730.id != day0.id)
    #expect(day730.id == daily.shiftTemplate.idPrefix + DailyCalendar.isoDay(wrapped, calendar: Bundled.utc))
  }

  @Test("a date before the horizon wraps backwards, never crashes")
  func dailyShiftBeforeHorizon() throws {
    let daily = Bundled.daily
    let start = try #require(
      DailyCalendar.date(fromISO: daily.horizonStart, calendar: Bundled.utc))
    let before = try #require(Bundled.utc.date(byAdding: .day, value: -1, to: start))
    let shift = Bundled.pack.dailyShift(on: before, calendar: Bundled.utc)
    #expect(shift.caseIds == daily.days[daily.days.count - 1].caseIds)
  }

  @Test("isoDay round-trips every exported date")
  func isoRoundTrip() throws {
    for day in Bundled.daily.days {
      let date = try #require(DailyCalendar.date(fromISO: day.date, calendar: Bundled.utc))
      #expect(DailyCalendar.isoDay(date, calendar: Bundled.utc) == day.date)
    }
  }

  // ── copy helpers ───────────────────────────────────────────────────────────

  @Test("outcomeText resolves all 11 keys", arguments: OutcomeKey.allCases)
  func outcomeText(_ key: OutcomeKey) {
    #expect(!Bundled.copy.outcomeText(key).isEmpty)
  }

  @Test("render interpolates named placeholders in one pass")
  func render() {
    let copy = Bundled.copy
    #expect(copy.render("{a} and {b}", ["a": "one", "b": "two"]) == "one and two")
    // An unrecognised placeholder survives, so a missing parameter is visible.
    #expect(copy.render("{a} and {b}", ["a": "one"]) == "one and {b}")
    // A substituted value is never rescanned.
    #expect(copy.render("{a}", ["a": "{a}"]) == "{a}")
    #expect(copy.render("no placeholders", ["a": "one"]) == "no placeholders")
    #expect(copy.render("unclosed {a", ["a": "one"]) == "unclosed {a")
    #expect(copy.render("", [:]).isEmpty)
  }

  @Test("the summary lines carry the placeholders their screens fill")
  func summaryPlaceholders() {
    #expect(Bundled.copy.summary.investigationLine.contains("{pct}"))
    #expect(Bundled.copy.summary.blindLine.contains("{blind}"))
    #expect(Bundled.copy.intro.title.contains("{n}"))
  }
}
