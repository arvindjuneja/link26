import Foundation
import Testing
import SentryCore

@testable import SentrySOC

/// **The half of the feel pass a frame strip cannot prove** (F2b).
///
/// `SessionTests/SequenceTests` asserts every millisecond `FEEL.md` prints, and the
/// strips under `docs/screenshots/ios/feel/` show those milliseconds landing on real
/// glass. Neither answers the questions this suite exists for:
///
/// - does a skip really arrive *everything*, including the indexed beats?
/// - does Reduce Motion still fire the cues, and does it fire seven pings as seven
///   sounds or as one?
/// - does §7 nudge the sources it should and stay silent on a pane of noise?
/// - is a rule that says "once per shift" once per shift?
/// - is §8's thud threshold the same number the grader uses, or two numbers that
///   happen to agree today?
///
/// Everything below is deterministic: the seeded helpers are pure, and the sequence
/// runner is exercised through its Reduce-Motion path, which delivers on the calling
/// frame and therefore needs no clock.
@MainActor
@Suite("Director")
struct DirectorTests {

  private static let pack = ContentPack.bundled
  private static var firstCase: SocCase {
    pack.case(pack.shifts[0].caseIds[0])!
  }

  /// A director with a recording cue channel — the same shape `GameModel` wires.
  private static func recording() -> (Director, Box) {
    let box = Box()
    let director = Director()
    director.cue = { haptic, sound, variant in
      box.fired.append((haptic, sound, variant))
    }
    return (director, box)
  }

  @MainActor final class Box {
    /// `(haptic, sound, variant)` — the two channels, kept apart, exactly as a `Beat`
    /// names them.
    var fired: [(SocCue?, SocCue?, Int)] = []
    var names: [String] { fired.compactMap { ($0.1 ?? $0.0)?.name } }
    var hands: [String] { fired.compactMap { $0.0?.name } }
  }

  // MARK: - Reduce Motion (D18)

  @Test("Reduce Motion arrives every beat at once and still fires the cues")
  func reduceMotionCollapses() {
    let (director, box) = Self.recording()
    let beats = Sequences.handoverSequence(alertCount: 7)
    director.play(beats, id: "t", reduceMotion: true)

    // Every beat, including the indexed ones, is on screen on the first frame.
    for beat in beats {
      #expect(director.shows(beat.kind, of: "t"))
    }
    #expect(director.isPlaying == false)
    // The cues are unchanged in *kind* and deduplicated in *count*: seven identical
    // pings inside one millisecond is a blurt, not §1's rising line.
    #expect(Set(box.names) == Set(beats.compactMap { ($0.sound ?? $0.cue)?.name }))
    #expect(box.names.count == Set(box.names).count)
  }

  @Test("a beat's two channels stay apart — §1 is a select under a ping")
  func channelsAreSeparate() {
    let (director, box) = Self.recording()
    director.play(Sequences.handoverSequence(alertCount: 3), id: "t", reduceMotion: true)

    // §1 row 3: sound `ping`, haptic `select`. Collapsing them into one cue replaced
    // the tap with a second ping and lost the row entirely.
    #expect(box.names.contains(SocCue.ping.name))
    #expect(box.hands.contains(SocCue.select.name))
    #expect(box.hands.contains(SocCue.ping.name) == false)

    // §9's `—` rows: heard, never felt. §4's log line is the clearest.
    let (pull, pullBox) = Self.recording()
    pull.play(
      Sequences.pullSequence(cost: 10, isRepeat: false, seed: 1, findingCount: 0),
      id: "p", reduceMotion: true)
    #expect(pullBox.names.contains(SocCue.tick.name))
    #expect(pullBox.hands.contains(SocCue.tick.name) == false)
  }

  @Test("a sequence with no beats leaves nothing playing")
  func emptySequence() {
    let (director, _) = Self.recording()
    director.play([], id: "t", reduceMotion: false)
    #expect(director.isPlaying == false)
    #expect(director.shows(.end, of: "t") == false)
  }

  // MARK: - Identity and idempotence

  @Test("a second play of the same id is a no-op, a different id is not")
  func idempotentPerID() {
    let (director, box) = Self.recording()
    director.play(Sequences.arrivalSequence(), id: "a", reduceMotion: true)
    let first = box.names.count
    director.play(Sequences.arrivalSequence(), id: "a", reduceMotion: true)
    #expect(box.names.count == first, "an .onAppear that fires twice must not replay")

    director.play(Sequences.arrivalSequence(), id: "b", reduceMotion: true)
    #expect(box.names.count > first)
    #expect(director.runID == "b")
    // "a" finished, so it keeps its end state — that is `endStateSurvivesTheNext…`'s
    // property. What must never be claimed is a sequence that has not run at all,
    // which is what stops a rebuilt screen flashing an alert it was never given.
    #expect(director.shows(.trigger, of: "never-ran") == false)

    // A sequence still on the clock claims nothing for anyone else's id either.
    let (running, _) = Self.recording()
    running.play(Sequences.arrivalSequence(), id: "live", reduceMotion: false)
    #expect(running.shows(.sources, of: "live") == false, "1800 ms have not passed")
    #expect(running.shows(.sources, of: "other") == false)
  }

  @Test("resetForShift clears everything a board is allowed to remember")
  func resetForShift() {
    let (director, _) = Self.recording()
    director.nudge(["edr-process-tree"])
    director.play(Sequences.arrivalSequence(), id: "a", reduceMotion: true)
    director.interject(key: "k", text: "line")
    director.noteMeters(breach: 0, noise: 0)
    director.noteMeters(breach: 30, noise: 0)
    #expect(director.fearRevealed.contains(Director.breachKey))

    director.resetForShift()
    #expect(director.runID == "")
    #expect(director.worthALook.isEmpty)
    #expect(director.valeLine == nil)
    #expect(director.fearRevealed.isEmpty)
    #expect(director.revealedAlerts.isEmpty)
    #expect(director.clockHeld == 0)

    // …and a sequence that already ran in the last shift may run again in this one.
    let (fresh, box) = Self.recording()
    fresh.play(Sequences.arrivalSequence(), id: "a", reduceMotion: true)
    let before = box.names.count
    fresh.resetForShift()
    fresh.play(Sequences.arrivalSequence(), id: "a", reduceMotion: true)
    #expect(box.names.count == before * 2)
  }

  // MARK: - Skip

  @Test("a finished sequence shows exactly the beats it contained — and no others")
  func endStateIsTheSequence() {
    // The bug this pins: remembering only that a run *finished* made `shows(_:of:)`
    // answer `true` for every kind, so the debrief of a **good** call drew §8's rose
    // breach edge. A `breachDelta` of 0 emits no `.breach` beat; a finished run must
    // not claim one.
    let (quiet, _) = Self.recording()
    let quietBeats = Sequences.callSequence(breachDelta: 0, verdict: .verdictGood)
    quiet.play(quietBeats, id: "quiet", reduceMotion: true)
    #expect(quiet.isFinished("quiet"))
    #expect(quiet.shows(.stamp, of: "quiet"))
    #expect(quiet.shows(.breach, of: "quiet") == false)

    let (loud, _) = Self.recording()
    loud.play(Sequences.callSequence(breachDelta: 40), id: "loud", reduceMotion: true)
    #expect(loud.shows(.breach, of: "loud"))

    // …and the same is true of an arrival with no coach line.
    let (plain, _) = Self.recording()
    plain.play(Sequences.arrivalSequence(withCoach: false), id: "plain", reduceMotion: true)
    #expect(plain.shows(.sources, of: "plain"))
    #expect(plain.shows(.coach, of: "plain") == false)
  }

  @Test("an end state outlives the sequence that follows it")
  func endStateSurvivesTheNextSequence() {
    // The other half of the same bug, from the other side: the case screen draws its
    // SOURCES list off `shows(.sources, of: "arrival:…")`, and a pull starting takes
    // the clock. Without the memory the list vanished under the open sheet — which is
    // exactly how the Shift-1 replay failed to find its second source.
    let (director, _) = Self.recording()
    director.play(Sequences.arrivalSequence(), id: "arrival:c1", reduceMotion: true)
    director.play(
      Sequences.pullSequence(cost: 10, isRepeat: false, seed: 1, findingCount: 1),
      id: "pull:c1/s1", reduceMotion: true)

    #expect(director.runID == "pull:c1/s1")
    #expect(director.shows(.sources, of: "arrival:c1"), "a finished arrival stays delivered")
    #expect(director.shows(.results, of: "pull:c1/s1"))
  }

  @Test("skip arrives the running sequence's own beats")
  func skipArrivesTheSequence() {
    let (director, _) = Self.recording()
    let beats = Sequences.arrivalSequence(withCoach: false)
    director.play(beats, id: "s", reduceMotion: false)
    director.skip()
    for beat in beats { #expect(director.shows(beat.kind, of: "s")) }
    #expect(director.shows(.coach, of: "s") == false, "a skip does not invent a beat")
    #expect(director.isFinished("s"))
  }

  @Test("skip drops the cues it passed")
  func skipIsSilent() {
    let (director, box) = Self.recording()
    director.play(Sequences.handoverSequence(alertCount: 7), id: "t", reduceMotion: false)
    let heardBeforeSkip = box.names.count
    director.skip()
    #expect(box.names.count == heardBeforeSkip, "a skip is a request to stop being performed at")
    #expect(director.shows(.dock, of: "t"))
    #expect(director.isPlaying == false)
  }

  // MARK: - §7 · leads-to

  @Test("a decisive pull points at the key sources that are still unread")
  func leadsToFires() {
    let socCase = Self.firstCase
    let decisive = socCase.evidence.first { $0.weight == .decisive }!
    let led = Director.leadsTo(socCase, justPulled: decisive.sourceId, queried: [decisive.sourceId])

    #expect(!led.isEmpty)
    #expect(led.allSatisfy { socCase.keySourceIds.contains($0) })
    #expect(!led.contains(decisive.sourceId), "the source just pulled is not a lead")
  }

  @Test("a pane of noise points nowhere")
  func leadsToStaysQuietOnNoise() {
    // Synthesised rather than found: the first board is authored well enough that
    // every source of case 1 carries something, and the rule still has to be right
    // for the case that does not.
    let quiet = SocEvidence(
      id: "e", sourceId: "s-noise", label: "l", detail: "d", weight: .noise)
    let socCase = SocCase(
      id: "c", archetype: Self.firstCase.archetype, alertTitle: "t", detectionRule: "r",
      toolSeverity: Self.firstCase.toolSeverity, trigger: "g", asset: "a",
      sourceIds: ["s-noise", "s-key"], keySourceIds: ["s-key"], evidence: [quiet],
      truth: Self.firstCase.truth, correctDisposition: Self.firstCase.correctDisposition,
      acceptableDispositions: Self.firstCase.acceptableDispositions, why: "w",
      learn: Self.firstCase.learn, handoff: nil)

    #expect(Director.leadsTo(socCase, justPulled: "s-noise", queried: ["s-noise"]).isEmpty)
    #expect(Director.hasDecisive(socCase, from: "s-noise") == false)
  }

  @Test("a nudge waits for the pull's findings, then lights once per row per shift")
  func nudgeWaitsAndFiresOnce() {
    let (director, _) = Self.recording()
    let beats = Sequences.pullSequence(cost: 10, isRepeat: false, seed: 1, findingCount: 1)

    director.nudge(["a", "b"])
    #expect(director.worthALook.isEmpty, "the pane is still streaming — nothing glows yet")
    director.play(beats, id: "pull:1", reduceMotion: true)
    #expect(director.worthALook == ["a", "b"], "the findings landed; now it points")

    // A row already nudged this shift does not glow again.
    director.nudge(["a"])
    director.play(beats, id: "pull:2", reduceMotion: true)
    #expect(director.worthALook == ["a", "b"])

    // A touch answers it.
    director.clearNudge()
    #expect(director.worthALook.isEmpty)

    director.nudge(["c"])
    director.play(beats, id: "pull:3", reduceMotion: true)
    #expect(director.worthALook == ["c"], "a fresh nudge replaces the glow, it does not stack")
  }

  // MARK: - §6 · Vale

  @Test("an interjection fires once per key per shift")
  func interjectionIsOnce() {
    let (director, _) = Self.recording()
    director.interject(key: FeelCopyKey.valeFirstPull, text: "one")
    #expect(director.valeLine == "one")
    director.dismissVale()
    director.interject(key: FeelCopyKey.valeFirstPull, text: "one")
    #expect(director.valeLine == nil, "the same rule may not fire twice in a shift")

    director.interject(key: FeelCopyKey.valeThinCall, text: "two")
    #expect(director.valeLine == "two", "a different rule still speaks")
  }

  // MARK: - §5 · pressure

  @Test("a fear caption arrives on the delta, not on the first look")
  func fearArrivesOnDelta() {
    let (director, _) = Self.recording()
    #expect(director.noteMeters(breach: 0, noise: 0).isEmpty, "the first look is the baseline")
    #expect(director.fearRevealed.isEmpty)

    let moved = director.noteMeters(breach: 30, noise: 0)
    #expect(moved == [Director.breachKey])
    #expect(director.fearRevealed == [Director.breachKey])

    let again = director.noteMeters(breach: 55, noise: 0)
    #expect(again.isEmpty, "a caption arrives once and then stays")
    #expect(director.fearRevealed == [Director.breachKey])

    director.noteMeters(breach: 55, noise: 12)
    #expect(director.fearRevealed == [Director.breachKey, Director.noiseKey])
  }

  @Test("the felt band is the worse of the meters and the clock")
  func feltStatusIsMax() {
    // §5's whole claim, restated where a screen can be held to it: the desk thumps
    // because the shift is burning, even when the meters are clean.
    #expect(Sequences.timeStatus(used: 70, budget: 90) == .hunt)
    #expect(Sequences.feltStatus(engine: .calm, time: .hunt) == .hunt)
    #expect(Sequences.feltStatus(engine: .lockdown, time: .calm) == .lockdown)
  }

  @Test("the live board reveals nothing when there is nothing ahead")
  func liveBoardCap() {
    let (director, box) = Self.recording()
    director.startLiveBoard(from: 6, count: 7, seed: 1)
    #expect(director.revealedAlerts.isEmpty)
    #expect(box.names.isEmpty)
    // And the schedule it would run is capped at the queue that is actually left.
    let schedule = Sequences.boardRevealSchedule(remaining: 3, seed: 1)
    #expect(schedule.count <= 3)
    #expect(Set(schedule.map(\.alertIndex)).count == schedule.count)
  }

  @Test("Reduce Motion settles the clock instead of counting it")
  func clockUnderReduceMotion() {
    let (director, _) = Self.recording()
    director.countUpClock(cost: 10, overMs: 2000, reduceMotion: true)
    #expect(director.clockHeld == 0)

    director.countUpClock(cost: 10, overMs: 2000, reduceMotion: false)
    #expect(director.clockHeld == 10, "the strip starts 10 minutes behind the session")
    director.settleClock()
    #expect(director.clockHeld == 0)
  }

  // MARK: - §4 · seeds and the pane

  @Test("a pull's seed is stable, and no two pulls share one")
  func seedsAreStable() {
    let one = Director.pullSeed(caseID: "soc-ps-cradle", sourceID: "edr-process-tree")
    let same = Director.pullSeed(caseID: "soc-ps-cradle", sourceID: "edr-process-tree")
    let other = Director.pullSeed(caseID: "soc-ps-cradle", sourceID: "decoded-command")
    let elsewhere = Director.pullSeed(caseID: "soc-auth-reset", sourceID: "edr-process-tree")

    #expect(one == same, "a re-read of the same pull must read the same")
    #expect(one != other)
    #expect(one != elsewhere)

    // The pane the seed produces is the same pane, twice.
    let a = Sequences.logLineTimes(total: 2000, seed: one)
    let b = Sequences.logLineTimes(total: 2000, seed: same)
    #expect(a == b)
    #expect((Sequences.minLogLines...Sequences.maxLogLines).contains(a.count))
  }

  @Test("a log line's number is deterministic and differs down the pane")
  func logNumbers() {
    let first = Director.logNumber(caseID: "c", sourceID: "s", line: 0)
    #expect(first == Director.logNumber(caseID: "c", sourceID: "s", line: 0))
    #expect(first != Director.logNumber(caseID: "c", sourceID: "s", line: 1))
    #expect((1000...9000).contains(first), "four digits, so a log line reads like one")
  }

  @Test("the host is the asset's first token")
  func hostOfAsset() {
    #expect(Director.host(of: "FIN-WS-04 · user jdoe (Finance)") == "FIN-WS-04")
    // `soc-phish-harvest`'s asset is one unbroken sender token: nothing to trim.
    let sender = Self.pack.cases.first { $0.asset.split(separator: " ").count == 1 }?.asset
    if let sender { #expect(Director.host(of: sender) == sender) }
  }

  @Test("a beat's pitch slot is its own index")
  func variants() {
    #expect(Director.variant(of: .alertLand(6)) == 6)
    #expect(Director.variant(of: .card(2)) == 2)
    #expect(Director.variant(of: .logLine(4)) == 4)
    #expect(Director.variant(of: .stamp) == 0)
  }

  // MARK: - §8 · the cut

  @Test("the breach thud fires on the grader's own threshold, not a second number")
  func thudThresholdMatchesTuning() {
    // `Sequences.breachThudDelta` is 30 and so is `tuning.grade.tpMissedBreach`. If a
    // designer retunes the miss, this is the test that says the thud moved with it —
    // otherwise the debrief would thump for a delta the grader no longer calls a miss.
    #expect(Sequences.breachThudDelta == Self.pack.tuning.grade.tpMissedBreach)

    let loud = Sequences.callSequence(breachDelta: Self.pack.tuning.grade.tpMissedBreach)
    #expect(loud.contains { $0.kind == .breach })
    let quiet = Sequences.callSequence(breachDelta: Self.pack.tuning.grade.tpMissedBreach - 1)
    #expect(!quiet.contains { $0.kind == .breach })
  }

  @Test("the call sequence's file thud is silenced, because the reducer already fired it")
  func fileIsNotDoubled() {
    let (director, box) = Self.recording()
    director.play(
      Sequences.callSequence(breachDelta: 40, verdict: .verdictGood),
      id: "call", reduceMotion: true, silencing: [.file])

    #expect(!box.names.contains(SocCue.file.name), "MAKE_CALL already thudded")
    #expect(!box.hands.contains(SocCue.file.name), "…on both channels")
    #expect(box.names.contains(SocCue.stamp.name))
    #expect(box.names.contains(SocCue.verdictGood.name))
    #expect(box.names.contains(SocCue.breachThud.name))
  }
}
