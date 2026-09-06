import Foundation
import Testing

@testable import SentryCore

/// The looping heartbeat's scheduler (§10 C5 #3, `DESIGN.md` §2.15).
///
/// Every guard lives in the pure function precisely so it can be asserted here, on
/// a Mac, with no device and no clock: silence at CALM and ALERT, the two rates, the
/// 400 ms floor, the 120 ms dub, and the 40 s wall with its three re-arms.
@Suite("Heartbeat")
struct HeartbeatTests {

  private var tuning: Tuning { Deck.tuning }

  // MARK: - Silence is the reward

  @Test("CALM and ALERT have no plan at all", arguments: [TraceStatus.calm, .alert])
  func silentBands(_ status: TraceStatus) {
    #expect(heartbeatPlan(status: status, tuning: tuning) == nil)
    #expect(CHPatternSpec.heartbeat(status, tuning) == nil)
  }

  // MARK: - The two beating bands

  @Test("HUNT beats at 60000/112 rounded — 536 ms, not 535")
  func huntRate() throws {
    let plan = try #require(heartbeatPlan(status: .hunt, tuning: tuning))
    #expect(tuning.bpm[.hunt] == 112)
    #expect(plan.periodMs == 536)                       // `SocConsole.tsx:210` rounds
    #expect(plan.status == .hunt)
    #expect(plan.autoSuspendMs == tuning.heartbeat.autoSuspendMs)
  }

  @Test("LOCKDOWN beats at 60000/150 — 400 ms, and sharper as well as faster")
  func lockdownRate() throws {
    let hunt = try #require(heartbeatPlan(status: .hunt, tuning: tuning))
    let lockdown = try #require(heartbeatPlan(status: .lockdown, tuning: tuning))

    #expect(tuning.bpm[.lockdown] == 150)
    #expect(lockdown.periodMs == 400)
    #expect(lockdown.periodMs < hunt.periodMs)
    let huntLub = try #require(hunt.lub)
    let lockdownLub = try #require(lockdown.lub)
    #expect(lockdownLub.intensity > huntLub.intensity)
    #expect(lockdownLub.sharpness > huntLub.sharpness, "dread, not volume")
  }

  @Test("the lub and dub carry the §4.4 table's values")
  func beatShape() throws {
    let hunt = try #require(heartbeatPlan(status: .hunt, tuning: tuning))
    #expect(hunt.beats.count == 2)
    #expect(hunt.lub == HeartbeatPlan.Beat(atMs: 0, intensity: 0.75, sharpness: 0.30))
    // The dub is 55 % of the lub's intensity, a tenth off its sharpness, at +120 ms.
    #expect(hunt.dub?.atMs == tuning.heartbeat.dubOffsetMs)
    #expect(tuning.heartbeat.dubOffsetMs == 120)
    #expect(isClose(hunt.dub?.intensity, 0.75 * 0.55))
    #expect(isClose(hunt.dub?.sharpness, 0.20))

    let lockdown = try #require(heartbeatPlan(status: .lockdown, tuning: tuning))
    #expect(lockdown.lub == HeartbeatPlan.Beat(atMs: 0, intensity: 1.0, sharpness: 0.55))
    #expect(isClose(lockdown.dub?.intensity, 0.55))
    #expect(isClose(lockdown.dub?.sharpness, 0.45))
  }

  // MARK: - The floor

  @Test("no band can beat faster than the 400 ms floor")
  func minimumPeriod() throws {
    #expect(tuning.heartbeat.minPeriodMs == 400)
    // A retune to 200 bpm would be 300 ms; the floor holds it at 400.
    let panicked = Tuning(
      trace: tuning.trace,
      bpm: Tuning.BPMTuning(CALM: 50, ALERT: 76, HUNT: 112, LOCKDOWN: 200),
      timeBudgetDefault: tuning.timeBudgetDefault, grade: tuning.grade, shift: tuning.shift,
      career: tuning.career, heartbeat: tuning.heartbeat, handler: tuning.handler)

    let plan = try #require(heartbeatPlan(status: .lockdown, tuning: panicked))
    #expect(plan.periodMs == 400, "the floor did not hold")
  }

  @Test("a zero bpm cannot divide by zero")
  func degenerateTuning() throws {
    let broken = Tuning(
      trace: tuning.trace,
      bpm: Tuning.BPMTuning(CALM: 0, ALERT: 0, HUNT: 0, LOCKDOWN: 0),
      timeBudgetDefault: tuning.timeBudgetDefault, grade: tuning.grade, shift: tuning.shift,
      career: tuning.career, heartbeat: tuning.heartbeat, handler: tuning.handler)

    let plan = try #require(heartbeatPlan(status: .hunt, tuning: broken))
    #expect(plan.periodMs == 60_000, "one beat a minute is the degenerate answer, not a crash")
  }

  // MARK: - The guards, suspension and re-arming

  @Test("the loop runs only on the case screen, and only with haptics on")
  func phaseAndSettingGates() {
    var director = HeartbeatDirector(tuning: tuning, nowMs: 0, status: .hunt, phase: .investigating)

    #expect(director.update(status: .hunt, phase: .investigating, hapticsEnabled: true, nowMs: 0) != nil)
    #expect(director.update(status: .hunt, phase: .debrief(readOnly: false), hapticsEnabled: true, nowMs: 10) == nil)
    #expect(director.update(status: .hunt, phase: .complete, hapticsEnabled: true, nowMs: 20) == nil)
    #expect(director.update(status: .hunt, phase: .hub, hapticsEnabled: true, nowMs: 30) == nil)
    #expect(director.update(status: .hunt, phase: .investigating, hapticsEnabled: false, nowMs: 40) == nil)
    #expect(director.update(status: .calm, phase: .investigating, hapticsEnabled: true, nowMs: 50) == nil)
  }

  @Test("it goes quiet after 40 s of continuous beating")
  func autoSuspend() {
    #expect(tuning.heartbeat.autoSuspendMs == 40_000)
    var director = HeartbeatDirector(tuning: tuning, nowMs: 0, status: .hunt, phase: .investigating)

    #expect(director.update(status: .hunt, phase: .investigating, hapticsEnabled: true, nowMs: 39_999) != nil)
    #expect(director.update(status: .hunt, phase: .investigating, hapticsEnabled: true, nowMs: 40_000) == nil)
    #expect(director.isSuspended(nowMs: 40_000))
  }

  @Test("a pull re-arms it — the player is working again")
  func rearmOnPull() {
    var director = HeartbeatDirector(tuning: tuning, nowMs: 0, status: .hunt, phase: .investigating)
    #expect(director.update(status: .hunt, phase: .investigating, hapticsEnabled: true, nowMs: 45_000) == nil)

    director.pulledSource(nowMs: 45_000)
    #expect(director.update(status: .hunt, phase: .investigating, hapticsEnabled: true, nowMs: 45_001) != nil)
    #expect(director.update(status: .hunt, phase: .investigating, hapticsEnabled: true, nowMs: 85_001) == nil)
  }

  @Test("a status change re-arms it, and so does coming back to the case screen")
  func rearmOnStatusAndPhase() throws {
    var director = HeartbeatDirector(tuning: tuning, nowMs: 0, status: .hunt, phase: .investigating)
    #expect(director.update(status: .hunt, phase: .investigating, hapticsEnabled: true, nowMs: 50_000) == nil)

    // The board got worse: the wall is reset and it beats again, harder.
    let escalated = director.update(
      status: .lockdown, phase: .investigating, hapticsEnabled: true, nowMs: 50_000)
    #expect(try #require(escalated).status == .lockdown)

    // Suspend again, leave for the debrief, come back: the run is new.
    #expect(director.update(status: .lockdown, phase: .investigating, hapticsEnabled: true, nowMs: 95_000) == nil)
    #expect(director.update(status: .lockdown, phase: .debrief(readOnly: false), hapticsEnabled: true, nowMs: 95_100) == nil)
    #expect(director.update(status: .lockdown, phase: .investigating, hapticsEnabled: true, nowMs: 95_200) != nil)
  }

  @Test("every number in the plan came out of tuning")
  func everyNumberIsTuned() throws {
    // Halve the rate, double the dub offset, drop the wall: the plan must follow.
    let retuned = Tuning(
      trace: tuning.trace,
      bpm: Tuning.BPMTuning(CALM: 50, ALERT: 76, HUNT: 60, LOCKDOWN: 90),
      timeBudgetDefault: tuning.timeBudgetDefault, grade: tuning.grade, shift: tuning.shift,
      career: tuning.career,
      heartbeat: Tuning.HeartbeatTuning(minPeriodMs: 100, autoSuspendMs: 5_000, dubOffsetMs: 240),
      handler: tuning.handler)

    let plan = try #require(heartbeatPlan(status: .hunt, tuning: retuned))
    #expect(plan.periodMs == 1_000)
    #expect(plan.dub?.atMs == 240)
    #expect(plan.autoSuspendMs == 5_000)

    var director = HeartbeatDirector(tuning: retuned, nowMs: 0, status: .hunt, phase: .investigating)
    #expect(director.update(status: .hunt, phase: .investigating, hapticsEnabled: true, nowMs: 5_000) == nil)
  }

  // MARK: - The audible heartbeat (F2a)

  /// The ear's schedule is what makes `FEEL.md` §9's "Heartbeat sound" switch do
  /// something, so its numbers are asserted here rather than trusted: the hand's
  /// loop is scheduled by the OS and the ear's is scheduled by us.

  @Test("the sound schedule is the same loop, flattened — lub, dub, one per period")
  func soundScheduleShape() throws {
    let plan = try #require(heartbeatPlan(status: .hunt, tuning: tuning))
    let hits = heartbeatSoundSchedule(plan)

    // 536 ms period over a 40 s wall = 75 cycles, two beats each.
    #expect(plan.periodMs == 536)
    #expect(hits.count == 150)
    #expect(hits[0] == HeartbeatSoundHit(atMs: 0, beatIndex: 0))
    #expect(hits[1] == HeartbeatSoundHit(atMs: 120, beatIndex: 1))
    #expect(hits[2] == HeartbeatSoundHit(atMs: 536, beatIndex: 0))
    #expect(hits[3] == HeartbeatSoundHit(atMs: 656, beatIndex: 1))

    // Monotonic, and every lub exactly one period after the last one.
    let lubs = hits.filter { $0.beatIndex == 0 }.map(\.atMs)
    #expect(lubs == (0..<lubs.count).map { $0 * plan.periodMs })
    #expect(zip(hits, hits.dropFirst()).allSatisfy { $0.atMs <= $1.atMs })
  }

  @Test("the ear stops at the same 40 s wall the hand does")
  func soundScheduleStopsAtTheWall() throws {
    for status in [TraceStatus.hunt, .lockdown] {
      let plan = try #require(heartbeatPlan(status: status, tuning: tuning))
      let hits = heartbeatSoundSchedule(plan)
      #expect(hits.allSatisfy { $0.atMs < plan.autoSuspendMs })
      // And it really does run to the wall rather than stopping early.
      #expect(try #require(hits.last).atMs >= plan.autoSuspendMs - plan.periodMs)
    }
  }

  @Test("LOCKDOWN is audibly faster than HUNT — more thumps in the same window")
  func soundScheduleFollowsTheBand() throws {
    let hunt = heartbeatSoundSchedule(try #require(heartbeatPlan(status: .hunt, tuning: tuning)))
    let lockdown = heartbeatSoundSchedule(
      try #require(heartbeatPlan(status: .lockdown, tuning: tuning)))
    #expect(lockdown.count > hunt.count)
  }

  @Test("a plan with nothing to play schedules nothing")
  func soundScheduleDegenerates() {
    let empty = HeartbeatPlan(status: .hunt, periodMs: 536, beats: [], autoSuspendMs: 40_000)
    #expect(heartbeatSoundSchedule(empty).isEmpty)
    let beat = HeartbeatPlan.Beat(atMs: 0, intensity: 1, sharpness: 1)
    #expect(
      heartbeatSoundSchedule(
        HeartbeatPlan(status: .hunt, periodMs: 0, beats: [beat], autoSuspendMs: 40_000)
      ).isEmpty)
    #expect(
      heartbeatSoundSchedule(
        HeartbeatPlan(status: .hunt, periodMs: 536, beats: [beat], autoSuspendMs: 0)
      ).isEmpty)
  }

  @Test("the schedule is tuned, not hard-coded")
  func soundScheduleIsTuned() throws {
    let retuned = Tuning(
      trace: tuning.trace,
      bpm: Tuning.BPMTuning(CALM: 50, ALERT: 76, HUNT: 60, LOCKDOWN: 90),
      timeBudgetDefault: tuning.timeBudgetDefault, grade: tuning.grade, shift: tuning.shift,
      career: tuning.career,
      heartbeat: Tuning.HeartbeatTuning(minPeriodMs: 100, autoSuspendMs: 5_000, dubOffsetMs: 240),
      handler: tuning.handler)
    let plan = try #require(heartbeatPlan(status: .hunt, tuning: retuned))
    let hits = heartbeatSoundSchedule(plan)
    // 1000 ms period, 5 s wall: five lubs and five dubs, the last dub at 4240 ms.
    #expect(hits.count == 10)
    #expect(hits.last == HeartbeatSoundHit(atMs: 4_240, beatIndex: 1))
  }
}
