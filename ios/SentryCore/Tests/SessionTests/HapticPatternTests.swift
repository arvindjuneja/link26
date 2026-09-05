import Foundation
import Testing

@testable import SentryCore

/// **The only pre-device verification that exists** (§10 C5 #4, X7).
///
/// The Simulator has no haptics hardware, so nothing below this line can be caught
/// by running the app: a curve with its control points in the wrong order, a dub
/// that lands before its lub, a "rank-up" that falls in intensity instead of rising
/// — all of it ships silently. These assertions are the substitute for a thumb.
@Suite("Haptic patterns")
struct HapticPatternTests {

  private var tuning: Tuning { Deck.tuning }

  // MARK: - The cue vocabulary

  @Test("SocCue covers the 15 rows of the §2.15 cue table")
  func cueVocabulary() {
    // The §2.15 table has 15 rows. Two of them (`beat-lub`, `beat-dub`) are one
    // Swift case, because natively they are one looping pattern with the dub at
    // +120 ms; one of them (`shift-*`) is three, because the caller has a
    // `ShiftGrade` and not a string. 15 − 2 − 1 + 1 + 3 = **16 cases**.
    let withoutHeartbeat = SocCue.allCases.filter {
      if case .heartbeat = $0 { false } else { true }
    }
    #expect(withoutHeartbeat.count == 15, "the 12 single-row cues plus the three shift grades")
    #expect(withoutHeartbeat.count + 1 == 16, "…and `heartbeat(_:)` is the sixteenth case")
    // `allCases` instantiates the heartbeat at every band, so it is longer than the
    // case count by three.
    #expect(SocCue.allCases.count == withoutHeartbeat.count + TraceStatus.allCases.count)

    let distinct = Set(SocCue.allCases)
    #expect(distinct.count == SocCue.allCases.count, "a cue is listed twice")
    #expect(Set(SocCue.allCases.map(\.name)).count == SocCue.allCases.count)

    // Three cues cannot be expressed with `.sensoryFeedback` and have a pattern; the
    // twelve that can, do not.
    for cue in SocCue.bespoke {
      #expect(CHPatternSpec.pattern(for: cue) != nil, "\(cue.name) has no pattern")
    }
    let routed = SocCue.allCases.filter { CHPatternSpec.pattern(for: $0) != nil }
    #expect(Set(routed) == Set(SocCue.bespoke))
  }

  @Test("the debrief cue follows the grade, not the verdict alone")
  func verdictCueMapping() {
    let good = CallGrade(
      verdictCorrect: true, dispositionCorrect: true, exact: true, breachDelta: 0,
      noiseDelta: 0, outcomeKey: .tpEscalatedCorrect)
    let off = CallGrade(
      verdictCorrect: true, dispositionCorrect: false, exact: false, breachDelta: 10,
      noiseDelta: 0, outcomeKey: .tpUnderContained)
    let wrong = CallGrade(
      verdictCorrect: false, dispositionCorrect: false, exact: false, breachDelta: 30,
      noiseDelta: 0, outcomeKey: .tpMissed)

    #expect(SocCue.verdict(good) == .verdictGood)
    #expect(SocCue.verdict(off) == .verdictOff)
    #expect(SocCue.verdict(wrong) == .verdictWrong)
    #expect(SocCue.shift(.clean) == .shiftClean)
    #expect(SocCue.shift(.rough) == .shiftRough)
    #expect(SocCue.shift(.breached) == .shiftBreached)
  }

  // MARK: - The heartbeat, event by event

  @Test("the heartbeat is a 90 ms continuous lub with a fast-attack curve, then a dub")
  func heartbeatPattern() throws {
    let pattern = try #require(CHPatternSpec.heartbeat(.hunt, tuning))

    #expect(pattern.events.count == 2)
    let lub = pattern.events[0]
    #expect(lub.kind == .continuous)
    #expect(lub.relativeTime == 0)
    #expect(isClose(lub.duration, 0.09))
    #expect(lub.intensity == 0.75)
    #expect(lub.sharpness == 0.30)

    let dub = pattern.events[1]
    #expect(dub.kind == .transient)
    // +120 ms, from `tuning.heartbeat.dubOffsetMs`.
    #expect(isClose(dub.relativeTime, 0.12))
    #expect(dub.duration == 0)
    #expect(isClose(dub.intensity, 0.4125))
    #expect(isClose(dub.sharpness, 0.20))
    #expect(dub.relativeTime > lub.relativeTime, "the dub landed before the lub")

    // The envelope: silence → full at 18 ms → silence at 90 ms. The fast attack is
    // what makes it a THUMP; the fall is what stops it being a buzz.
    #expect(pattern.curves.count == 1)
    let curve = pattern.curves[0]
    #expect(curve.parameterID == .intensityControl)
    #expect(curve.relativeTime == 0)
    #expect(curve.controlPoints.map(\.value) == [0, 1.0, 0])
    #expect(curve.controlPoints.map(\.relativeTime).elementsEqual([0, 0.018, 0.09], by: { isClose($0, $1) }))
    // Control points must be ascending or Core Haptics rejects the pattern.
    #expect(curve.controlPoints.map(\.relativeTime).sorted() == curve.controlPoints.map(\.relativeTime))
  }

  @Test("LOCKDOWN's beat is the same shape, louder and sharper")
  func lockdownHeartbeatPattern() throws {
    let hunt = try #require(CHPatternSpec.heartbeat(.hunt, tuning))
    let lockdown = try #require(CHPatternSpec.heartbeat(.lockdown, tuning))

    #expect(lockdown.events.count == hunt.events.count)
    #expect(lockdown.events[0].intensity == 1.0)
    #expect(lockdown.events[0].sharpness == 0.55)
    #expect(isClose(lockdown.events[1].intensity, 0.55))
    #expect(isClose(lockdown.events[1].sharpness, 0.45))
  }

  @Test("CALM and ALERT have no pattern", arguments: [TraceStatus.calm, .alert])
  func silentBands(_ status: TraceStatus) {
    #expect(CHPatternSpec.heartbeat(status, tuning) == nil)
  }

  // MARK: - file — tick-tick-CLUNK

  @Test("the stamp is two sharp ticks 45 ms apart, then a decaying body")
  func filePattern() {
    let pattern = CHPatternSpec.file

    #expect(pattern.events.count == 3)
    #expect(pattern.events[0] == .transient(at: 0, intensity: 0.35, sharpness: 0.90))
    #expect(pattern.events[1] == .transient(at: 0.045, intensity: 0.45, sharpness: 0.90))
    #expect(
      pattern.events[2]
        == .continuous(at: 0.09, duration: 0.14, intensity: 1.0, sharpness: 0.25))

    // The clunk is the dull one: the ticks are sharp, the body is not.
    #expect(pattern.events[2].sharpness < pattern.events[0].sharpness)
    // The second tick is harder than the first — the hold is resolving, not fading.
    #expect(pattern.events[1].intensity > pattern.events[0].intensity)

    #expect(pattern.curves.count == 1)
    let decay = pattern.curves[0]
    #expect(decay.parameterID == .intensityControl)
    #expect(isClose(decay.relativeTime, 0.09), "the decay must start with the body it shapes")
    #expect(decay.controlPoints.map(\.value) == [1.0, 0.65, 0])
    #expect(decay.controlPoints.map(\.relativeTime).elementsEqual([0, 0.04, 0.14], by: { isClose($0, $1) }))
    #expect(isClose(pattern.duration, 0.23))
  }

  // MARK: - breachThud — low, sickening, double

  @Test("the breach thud is a low 180 ms body with a second hit at 90 ms")
  func breachThudPattern() {
    let pattern = CHPatternSpec.breachThud

    #expect(pattern.events.count == 2)
    #expect(
      pattern.events[0] == .continuous(at: 0, duration: 0.18, intensity: 1.0, sharpness: 0.15))
    #expect(pattern.events[1] == .transient(at: 0.09, intensity: 0.8, sharpness: 0.40))
    // Felt, not heard: almost no sharpness on the body.
    #expect(pattern.events[0].sharpness < 0.2)
    // The second blow lands inside the first, which is what makes it read as double.
    #expect(pattern.events[1].relativeTime < pattern.events[0].endTime)
    #expect(isClose(pattern.duration, 0.18))
    #expect(pattern.curves.isEmpty)
  }

  // MARK: - rankup — the only cue that crescendos

  @Test("the rank-up is four events over 700 ms rising in intensity and sharpness")
  func rankupPattern() {
    let pattern = CHPatternSpec.rankup

    #expect(pattern.events.count == 4)
    #expect(
      pattern.events.map(\.relativeTime).elementsEqual([0, 0.18, 0.42, 0.70], by: { isClose($0, $1) }))
    #expect(pattern.events.allSatisfy { $0.kind == .transient })
    #expect(isClose(pattern.duration, 0.70))

    // Rising, strictly, in both parameters — this is the whole cue.
    for (earlier, later) in zip(pattern.events, pattern.events.dropFirst()) {
      #expect(later.intensity > earlier.intensity, "the rank-up stopped rising in intensity")
      #expect(later.sharpness > earlier.sharpness, "the rank-up stopped rising in sharpness")
    }
    #expect(pattern.events.last?.intensity == 1.0)
  }

  // MARK: - Invariants every pattern must hold

  /// Every pattern the spec defines, built with **no fallback**.
  ///
  /// The heartbeats are `compactMap`ped rather than `?? .file`: a `heartbeat(_:_:)`
  /// that regressed to nil at a beating band would otherwise leave this suite quietly
  /// re-checking `file` twice and still passing — in the one suite that stands in for
  /// a thumb. Short array, failed count assertion, caught.
  static let everyPattern: [HapticPattern] = {
    let authored: [HapticPattern] = [
      CHPatternSpec.file, CHPatternSpec.breachThud, CHPatternSpec.rankup,
    ]
    let beating: [HapticPattern] = [TraceStatus.hunt, .lockdown].compactMap {
      CHPatternSpec.heartbeat($0, ContentPack.bundled.tuning)
    }
    return authored + beating
  }()

  @Test("the invariant suite covers all five patterns — no band dropped out")
  func everyPatternIsAccountedFor() {
    #expect(
      Self.everyPattern.count == 5,
      "a heartbeat band went silent — `patternInvariants` is checking fewer patterns")
  }

  @Test(
    "every pattern is orderly enough for Core Haptics to accept it",
    arguments: HapticPatternTests.everyPattern)
  func patternInvariants(_ pattern: HapticPattern) {
    #expect(!pattern.events.isEmpty)
    // `CHHapticEvent` clamps intensity and sharpness to 0…1 and traps on a negative
    // time; anything outside that is a bug the device would silently swallow.
    for event in pattern.events {
      #expect(event.relativeTime >= 0)
      #expect(event.intensity >= 0 && event.intensity <= 1)
      #expect(event.sharpness >= 0 && event.sharpness <= 1)
      #expect(event.duration >= 0)
      #expect(event.kind == .continuous || event.duration == 0, "a transient has no duration")
    }
    #expect(pattern.events.map(\.relativeTime).sorted() == pattern.events.map(\.relativeTime))
    for curve in pattern.curves {
      #expect(curve.controlPoints.count >= 2)
      #expect(curve.controlPoints.allSatisfy { $0.value >= 0 && $0.value <= 1 })
      #expect(
        curve.controlPoints.map(\.relativeTime).sorted()
          == curve.controlPoints.map(\.relativeTime))
    }
  }
}
