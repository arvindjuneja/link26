import Foundation
import Testing

@testable import SentryCore

/// **`docs/ios/FEEL.md`, asserted rather than eyeballed** (F2a, §11's second bullet).
///
/// Motion cannot be judged from a still and a reviewer cannot time a 260 ms gap by
/// hand, so every number the document prints is read back here from the pure
/// generator that produces it. If a timeline is retuned, this suite is the diff:
/// the document and the app cannot drift apart without a red line naming the beat.
@Suite("Feel sequences")
struct SequenceTests {

  // MARK: - §1 · the shift handover

  @Test("§1 · the handover lands the board, seven alerts, Vale and the dock on time")
  func handoverTimeline() throws {
    let beats = Sequences.handoverSequence(alertCount: 7)

    #expect(beats.first(where: { $0.kind == .ground })?.at == 0)
    #expect(beats.first(where: { $0.kind == .eyebrow })?.at == 0)
    // "600 | The board slides up: empty rail with 7 slots."
    #expect(beats.first(where: { $0.kind == .boardRise })?.at == 600)

    // "900 → 900+7×260 | Alerts land one per 260 ms."
    let lands = beats.filter { if case .alertLand = $0.kind { true } else { false } }
    #expect(lands.count == 7)
    #expect(lands.map(\.at) == [900, 1160, 1420, 1680, 1940, 2200, 2460])
    for (earlier, later) in zip(lands, lands.dropFirst()) {
      #expect(later.at - earlier.at == 260)
    }
    // Each landing blips the ECG: `ping` per alert, `select` per alert.
    #expect(lands.allSatisfy { $0.cue == .select && $0.sound == .ping })
    // The pitch steps up per alert — the beat carries the index that picks it.
    #expect(lands.enumerated().allSatisfy { $0.element.kind == .alertLand($0.offset) })

    // "+400 | Vale's ONE line arrives as a message card." From the end of the alert
    // run: 900 + 7×260 = 2720, + 400 = 3120.
    let message = try #require(beats.first(where: { $0.kind == .message }))
    #expect(message.at == 3120)
    #expect(message.cue == .commitSoft)
    #expect(message.sound == .tick)

    // "+300 | Dock rises" — after the 500 ms of typing dots resolve into text.
    #expect(beats.first(where: { $0.kind == .dock })?.at == 3920)
    // "Total ≈ 4.5 s" — the dock's own rise closes it at 4180 ms.
    #expect(beats.endStateMs == 4180)
  }

  @Test(
    "§1 · the rail is as long as the board", arguments: [0, 1, 3, 5, 7, 12])
  func handoverScalesWithTheQueue(_ count: Int) {
    let beats = Sequences.handoverSequence(alertCount: count)
    let lands = beats.filter { if case .alertLand = $0.kind { true } else { false } }
    #expect(lands.count == count)
    // The message never lands before the last alert has.
    let message = beats.first(where: { $0.kind == .message })?.at ?? 0
    #expect(lands.allSatisfy { $0.at < message })
    #expect(beats.endStateMs > message)
  }

  @Test("§1 · a negative alert count is an empty rail, not a crash")
  func handoverClampsTheQueue() {
    let beats = Sequences.handoverSequence(alertCount: -3)
    #expect(beats.filter { if case .alertLand = $0.kind { true } else { false } }.isEmpty)
    #expect(beats.endStateMs > 0)
  }

  // MARK: - §2 · the alert arrival

  @Test("§2 · the alert arrives as an event: spike, trigger, title, chip, sources")
  func arrivalTimeline() throws {
    let beats = Sequences.arrivalSequence()

    #expect(beats.first(where: { $0.kind == .ground })?.at == 0)
    // "120 | ECG spikes once … the queue pill increments." `arrive` at 120,
    // `select` at 120.
    let spike = try #require(beats.first(where: { $0.kind == .ecgSpike }))
    #expect(spike.at == 120)
    #expect(spike.cue == .select)
    #expect(spike.sound == .arrive)
    #expect(beats.first(where: { $0.kind == .queuePill })?.at == 120)

    // "260 | Trigger line only … types in over ~700 ms."
    #expect(beats.first(where: { $0.kind == .trigger })?.at == 260)
    #expect(Sequences.arrivalTriggerTypeMs == 700)
    // "1100 | the alert title fades in with the ASSET: line."
    #expect(beats.first(where: { $0.kind == .title })?.at == 1100)
    // "1500 | The severity chip stamps in (scale 1.3 → 1, 140 ms)."
    let severity = try #require(beats.first(where: { $0.kind == .severity }))
    #expect(severity.at == 1500)
    #expect(severity.cue == .commitSoft)
    #expect(severity.sound == .tick)
    #expect(Sequences.arrivalSeverityStampMs == 140)
    // "1800 | The SOURCES list rises from the bottom, collapsed."
    #expect(beats.first(where: { $0.kind == .sources })?.at == 1800)

    // "2100 | Coach line slides in only on shift 1."
    #expect(beats.contains { $0.kind == .coach } == false)
    #expect(beats.endStateMs == 1800)
  }

  @Test("§2 · shift 1 gets the coach line at 2100 and nothing else moves")
  func arrivalWithCoach() {
    let plain = Sequences.arrivalSequence()
    let coached = Sequences.arrivalSequence(withCoach: true)

    #expect(coached.first(where: { $0.kind == .coach })?.at == 2100)
    #expect(coached.endStateMs == 2100)
    // Every beat the plain arrival has, the coached one has at the same time.
    for beat in plain where beat.kind != .end {
      #expect(coached.contains(beat), "\(beat.kind) moved when the coach was added")
    }
  }

  // MARK: - §4 · the pull

  @Test(
    "§4 · the window scales with cost: ≤8m → 1.5 s, 10m → 2.0 s, ≥12m → 2.4 s",
    arguments: [(4, 1500), (8, 1500), (9, 2000), (10, 2000), (11, 2000), (12, 2400), (20, 2400)])
  func pullDurationScalesWithCost(_ pair: (cost: Int, expected: Int)) {
    #expect(Sequences.pullDurationMs(cost: pair.cost) == pair.expected)
  }

  @Test("§4 · a second pull in the same case is 25 % faster")
  func repeatPullsAreFaster() {
    #expect(Sequences.pullDurationMs(cost: 8, isRepeat: true) == 1125)
    #expect(Sequences.pullDurationMs(cost: 10, isRepeat: true) == 1500)
    #expect(Sequences.pullDurationMs(cost: 12, isRepeat: true) == 1800)
    for cost in [4, 8, 10, 12, 20] {
      let full = Double(Sequences.pullDurationMs(cost: cost))
      let quick = Double(Sequences.pullDurationMs(cost: cost, isRepeat: true))
      #expect(abs(quick / full - 0.75) < 0.001)
    }
  }

  @Test("§4 · the pane streams 4–6 log lines inside the window, and the header closes it")
  func pullStreamsLogLines() throws {
    for cost in [8, 10, 12] {
      for isRepeat in [false, true] {
        for seed in [Sequences.seed("soc-1"), Sequences.seed("soc-2"), 0, 99] {
          let total = Sequences.pullDurationMs(cost: cost, isRepeat: isRepeat)
          let beats = Sequences.pullSequence(cost: cost, isRepeat: isRepeat, seed: seed)

          let open = try #require(beats.first)
          #expect(open.kind == .queryOpen)
          #expect(open.at == 0)
          #expect(open.cue == .select)
          #expect(open.sound == .queryStart)

          let lines = beats.filter { if case .logLine = $0.kind { true } else { false } }
          #expect(lines.count >= 4 && lines.count <= 6, "cost \(cost) seed \(seed)")
          // Every line lands inside the window, in order, and none lands on 0 or on
          // the RESULTS header.
          #expect(lines.allSatisfy { $0.at > 0 && $0.at < total })
          #expect(lines.map(\.at).sorted() == lines.map(\.at))
          // A tick per line, and no haptic — §4's "soft `tick` per line", "—".
          #expect(lines.allSatisfy { $0.sound == .tick && $0.cue == nil })

          let results = try #require(beats.first(where: { $0.kind == .results }))
          #expect(results.at == total)
          #expect(results.cue == .commitSoft)
        }
      }
    }
  }

  @Test("§4 · the jitter is seeded — the same pull reads the same, a different one does not")
  func pullJitterIsDeterministic() {
    let a = Sequences.pullSequence(cost: 10, isRepeat: false, seed: Sequences.seed("edr-proc"))
    let b = Sequences.pullSequence(cost: 10, isRepeat: false, seed: Sequences.seed("edr-proc"))
    let c = Sequences.pullSequence(cost: 10, isRepeat: false, seed: Sequences.seed("idp-auth"))
    #expect(a == b)
    #expect(a != c, "two sources streamed in lockstep")
    // FNV-1a, not `Hashable` — a hash salted per process would re-roll every launch.
    #expect(Sequences.seed("edr-proc") == Sequences.seed("edr-proc"))
    #expect(Sequences.seed("") == 0xcbf2_9ce4_8422_2325)
  }

  @Test("§4 · raw gaps sit in the 280–420 ms band before they are scaled onto the window")
  func logLineGapsAreInBand() {
    // The 280–420 ms band is the *shape* of the stream; the window is its length.
    // Read the band where it is authored, at a window long enough that scaling is
    // close to 1: five lines × 350 ms ≈ 2100 ms.
    for seed in (0..<64).map({ Sequences.seed("case-\($0)") }) {
      let times = Sequences.logLineTimes(total: 2100, seed: seed)
      #expect(times.count >= 4 && times.count <= 6)
      let gaps = zip([0] + times, times).map { $1 - $0 }
      // Scaled, so allow the window's own stretch — but never a gap that collapsed
      // to nothing or ran to twice the band.
      #expect(gaps.allSatisfy { $0 > 0 })
      #expect(gaps.allSatisfy { $0 < Sequences.logLineMaxGapMs * 2 })
    }
    #expect(Sequences.logLineMinGapMs == 280)
    #expect(Sequences.logLineMaxGapMs == 420)
  }

  @Test("§4 · findings land one per 260 ms, three at most, then the rest together")
  func findingsLandOneAtATime() throws {
    let total = Sequences.pullDurationMs(cost: 10)
    let beats = Sequences.pullSequence(
      cost: 10, isRepeat: false, seed: 7, findingCount: 5, hasDecisive: false)

    let cards = beats.filter { if case .card = $0.kind { true } else { false } }
    #expect(cards.count == 5)
    // +0 / +260 / +520, then everything else together at +780.
    #expect(cards.map(\.at) == [total, total + 260, total + 520, total + 780, total + 780])
    // "`finding-land` per card (≤3)" — the haptic caps, the sound does not.
    #expect(cards.prefix(3).allSatisfy { $0.cue == .findingLand })
    #expect(cards.dropFirst(3).allSatisfy { $0.cue == nil })
    #expect(cards.allSatisfy { $0.sound == .landCard })
    // The sound-only cue really is sound-only.
    #expect(SocCue.landCard.isSoundOnly)
  }

  @Test("§4 · a decisive finding buys one extra beat after the last card")
  func decisiveAddsABeat() throws {
    let quiet = Sequences.pullSequence(cost: 10, isRepeat: false, seed: 7, findingCount: 2)
    #expect(quiet.contains { $0.kind == .decisive } == false)

    let loud = Sequences.pullSequence(
      cost: 10, isRepeat: false, seed: 7, findingCount: 2, hasDecisive: true)
    let cards = loud.filter { if case .card = $0.kind { true } else { false } }
    let decisive = try #require(loud.first(where: { $0.kind == .decisive }))
    #expect(decisive.at == (cards.map(\.at).max() ?? 0) + 260)
    #expect(loud.endStateMs == decisive.at)
  }

  @Test("§4 · a pull with no findings is still a pull")
  func pullWithNoFindings() {
    let beats = Sequences.pullSequence(cost: 10, isRepeat: false, seed: 3, findingCount: 0)
    #expect(beats.contains { if case .card = $0.kind { true } else { false } } == false)
    #expect(beats.endStateMs == Sequences.pullDurationMs(cost: 10))
  }

  // MARK: - §8 · the call

  @Test("§8 · the call is a cut: file, stamp, verdict, truth, meters, why")
  func callTimeline() throws {
    let beats = Sequences.callSequence(breachDelta: 0, verdict: .verdictGood)

    // "0 | Cut to black … `file` (heavy)."
    let cut = try #require(beats.first(where: { $0.kind == .cut }))
    #expect(cut.at == 0)
    #expect(cut.cue == .file)
    #expect(cut.sound == .file)
    // "450 | The stamp slams … `stamp` (paper + thud)." No haptic: the hand was
    // already answered at 0.
    let stamp = try #require(beats.first(where: { $0.kind == .stamp }))
    #expect(stamp.at == 450)
    #expect(stamp.sound == .stamp)
    #expect(stamp.cue == nil)
    #expect(Sequences.stampScaleMs == 180)
    // "900 | GOOD CALL / RIGHT VERDICT / WRONG CALL … `verdict-*` chord."
    let verdict = try #require(beats.first(where: { $0.kind == .verdict }))
    #expect(verdict.at == 900)
    #expect(verdict.cue == .verdictGood)
    #expect(verdict.sound == .verdictGood)
    // "1200 | TRUTH: chip reveals (flip 200 ms)."
    #expect(beats.first(where: { $0.kind == .truth })?.at == 1200)
    // "1500 | Meters sweep to their new values with count-up."
    #expect(beats.first(where: { $0.kind == .meters })?.at == 1500)
    // "2100 | WHY and the decisive findings fade in, staggered 80 ms."
    #expect(beats.first(where: { $0.kind == .why })?.at == 2100)
    #expect(Sequences.whyStaggerMs == 80)
    // "Tap anywhere from 450 ms onward → end state."
    #expect(Sequences.callSkipFromMs == 450)
    // The room tone ducks −12 dB for 600 ms on `file` (§9).
    #expect(Sequences.fileDuckMs == 600)
  }

  @Test(
    "§8 · the breach thud fires at delta ≥ 30, with the meters, and never below it",
    arguments: [(0, false), (10, false), (29, false), (30, true), (60, true)])
  func breachThudThreshold(_ pair: (delta: Int, fires: Bool)) {
    let beats = Sequences.callSequence(breachDelta: pair.delta)
    let breach = beats.first(where: { $0.kind == .breach })
    #expect((breach != nil) == pair.fires, "delta \(pair.delta)")
    if let breach {
      #expect(breach.at == 1500, "the thud must land with the meters, not after them")
      #expect(breach.cue == .breachThud)
      #expect(breach.sound == .breachThud)
    }
    #expect(Sequences.breachThudDelta == 30)
  }

  @Test(
    "§8 · the verdict cue is the graded one, not a guess",
    arguments: [SocCue.verdictGood, .verdictOff, .verdictWrong])
  func callCarriesTheGradedVerdict(_ cue: SocCue) {
    let beats = Sequences.callSequence(breachDelta: 0, verdict: cue)
    let verdict = beats.first(where: { $0.kind == .verdict })
    #expect(verdict?.cue == cue)
    #expect(verdict?.sound == cue)
  }

  // MARK: - §5 · the time pulse

  @Test(
    "§5 · time status: <50 % CALM · 50–75 % ALERT · 75–100 % HUNT · >100 % LOCKDOWN",
    arguments: [
      (0, TraceStatus.calm), (44, .calm), (45, .alert), (60, .alert), (67, .alert),
      (68, .hunt), (89, .hunt), (90, .hunt), (91, .lockdown), (200, .lockdown),
    ])
  func timeStatusBands(_ pair: (used: Int, expected: TraceStatus)) {
    // The 90-minute budget is `tuning.timeBudgetDefault`, not a literal of this suite.
    let budget = Deck.tuning.timeBudgetDefault
    #expect(budget == 90)
    #expect(Sequences.timeStatus(used: pair.used, budget: budget) == pair.expected)
  }

  @Test("§5 · the bands are monotonic and the boundaries land where the document says")
  func timeStatusIsMonotonic() {
    let budget = Deck.tuning.timeBudgetDefault
    var previous = TraceStatus.calm
    for used in 0...(budget * 2) {
      let status = Sequences.timeStatus(used: used, budget: budget)
      #expect(status >= previous, "the clock's band went backwards at \(used)m")
      previous = status
    }
    // 50 % is ALERT, not CALM; 100 % is still HUNT; a minute over is LOCKDOWN.
    #expect(Sequences.timeStatus(used: 50, budget: 100) == .alert)
    #expect(Sequences.timeStatus(used: 75, budget: 100) == .hunt)
    #expect(Sequences.timeStatus(used: 100, budget: 100) == .hunt)
    #expect(Sequences.timeStatus(used: 101, budget: 100) == .lockdown)
    // Degenerate input is CALM, never a divide by zero.
    #expect(Sequences.timeStatus(used: 40, budget: 0) == .calm)
    #expect(Sequences.timeStatus(used: -5, budget: 90) == .calm)
  }

  @Test("§5 · what the desk feels is the worse of the two bands")
  func feltStatusIsTheMax() {
    #expect(Sequences.feltStatus(engine: .calm, time: .hunt) == .hunt)
    #expect(Sequences.feltStatus(engine: .lockdown, time: .calm) == .lockdown)
    #expect(Sequences.feltStatus(engine: .alert, time: .alert) == .alert)
    for engine in TraceStatus.allCases {
      for time in TraceStatus.allCases {
        let felt = Sequences.feltStatus(engine: engine, time: time)
        #expect(felt >= engine && felt >= time)
        #expect(felt == engine || felt == time)
      }
    }
  }

  // MARK: - §5 · the live board

  @Test("§5 · the live board reveals every 25–40 s, capped at the remaining queue")
  func boardRevealSchedule() {
    for remaining in [1, 3, 6, 11] {
      let schedule = Sequences.boardRevealSchedule(
        remaining: remaining, seed: Sequences.seed("shift-1"))
      #expect(schedule.count == remaining, "the cap is the queue, not the clock")
      // Every gap sits in the band, including the first one from t=0.
      let gaps = zip([0] + schedule.map(\.atMs), schedule.map(\.atMs)).map { $1 - $0 }
      #expect(gaps.allSatisfy { $0 >= 25_000 && $0 <= 40_000 })
      #expect(schedule.map(\.atMs).sorted() == schedule.map(\.atMs))
      // Each upcoming alert is revealed exactly once — nothing is revealed twice
      // and no index outside the queue is ever named.
      #expect(Set(schedule.map(\.alertIndex)) == Set(0..<remaining))
    }
    #expect(Sequences.boardRevealSchedule(remaining: 0, seed: 1).isEmpty)
    #expect(Sequences.boardRevealSchedule(remaining: -4, seed: 1).isEmpty)
  }

  @Test("§5 · the board is seeded and cut off by the horizon")
  func boardRevealIsSeededAndCapped() {
    let a = Sequences.boardRevealSchedule(remaining: 6, seed: 42)
    let b = Sequences.boardRevealSchedule(remaining: 6, seed: 42)
    let c = Sequences.boardRevealSchedule(remaining: 6, seed: 43)
    #expect(a == b)
    #expect(a != c)
    // A horizon shorter than the queue's own 25 s minimum truncates rather than
    // rushing: the board stays live, it just does not finish.
    let short = Sequences.boardRevealSchedule(remaining: 6, seed: 42, horizonMs: 60_000)
    #expect(short.count < a.count)
    #expect(short.allSatisfy { $0.atMs <= 60_000 })
    #expect(Sequences.boardRevealSchedule(remaining: 6, seed: 42, horizonMs: 0).isEmpty)
  }

  // MARK: - Reduce Motion (D18)

  @Test("Reduce Motion collapses every sequence to its end state, cues intact")
  func reduceMotionCollapse() {
    let sequences: [[Beat]] = [
      Sequences.handoverSequence(alertCount: 7),
      Sequences.arrivalSequence(withCoach: true),
      Sequences.pullSequence(cost: 10, isRepeat: false, seed: 5, findingCount: 4, hasDecisive: true),
      Sequences.callSequence(breachDelta: 40, verdict: .verdictWrong),
    ]
    for beats in sequences {
      let collapsed = beats.collapsed()
      // Everything at zero: the screen draws its end state on the first frame.
      #expect(collapsed.allSatisfy { $0.at == 0 })
      #expect(collapsed.endStateMs == 0)
      // Same beats, same order — nothing was dropped.
      #expect(collapsed.map(\.kind) == beats.map(\.kind))
      // "sound and haptics stay" (D18) — both channels survive the collapse.
      #expect(collapsed.cues == beats.cues)
      #expect(collapsed.sounds == beats.sounds)
      #expect(!collapsed.sounds.isEmpty)
    }
  }

  @Test("every sequence is ordered, terminated, and readable up to a moment")
  func sequenceInvariants() {
    let sequences: [[Beat]] = [
      Sequences.handoverSequence(alertCount: 7),
      Sequences.arrivalSequence(),
      Sequences.arrivalSequence(withCoach: true),
      Sequences.pullSequence(cost: 12, isRepeat: true, seed: 11, findingCount: 3),
      Sequences.callSequence(breachDelta: 30),
    ]
    for beats in sequences {
      #expect(!beats.isEmpty)
      #expect(beats.allSatisfy { $0.at >= 0 })
      #expect(beats.map(\.at).sorted() == beats.map(\.at), "a sequence arrived out of order")
      #expect(beats.contains { $0.kind == .end }, "a sequence never ends")
      #expect(beats.endStateMs == beats.map(\.at).max())
      // `upTo` is what a screen driving a timer reads.
      #expect(beats.upTo(0).allSatisfy { $0.at == 0 })
      #expect(beats.upTo(beats.endStateMs).count == beats.count)
      #expect(beats.upTo(-1).isEmpty)
    }
  }

  // MARK: - The cue vocabulary the sequences use

  @Test("every cue a sequence names is a real cue, and the six new ones are used")
  func sequencesUseTheCueVocabulary() {
    let beats =
      Sequences.handoverSequence(alertCount: 7)
      + Sequences.arrivalSequence(withCoach: true)
      + Sequences.pullSequence(
        cost: 10, isRepeat: false, seed: 1, findingCount: 5, hasDecisive: true)
      + Sequences.callSequence(breachDelta: 40, verdict: .verdictWrong)

    let named = Set(beats.cues + beats.sounds)
    #expect(named.isSubset(of: Set(SocCue.allCases)))
    // All six of F2a's cues earn their place in a timeline.
    #expect(Set(SocCue.sequenceCues).isSubset(of: named))
    // The three sound-only cues never appear in the haptic column.
    #expect(Set(beats.cues).isDisjoint(with: Set(SocCue.soundOnly)))
  }
}
