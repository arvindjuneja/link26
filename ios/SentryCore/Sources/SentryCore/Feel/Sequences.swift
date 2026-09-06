import Foundation

/// Milliseconds from the top of a sequence. `FEEL.md` writes every timeline in
/// milliseconds, so the type the generators speak is milliseconds too — a
/// `TimeInterval` here would put a rounding step between the document and the test.
public typealias Milliseconds = Int

/// **The four timelines of `docs/ios/FEEL.md`, as pure functions** (F2a).
///
/// The feel pass is a set of *sequences*: the shift handover (§1), an alert
/// arriving (§2), a source pull (§4) and the call (§8). A sequence is the thing a
/// still cannot show and a reviewer cannot check by eye — so it is written here as
/// data, `[Beat]`, and `SessionTests/SequenceTests` asserts every number FEEL.md
/// prints. What a screen does with a beat is the screen's business; *when* it
/// happens is settled before any view is built.
///
/// Three rules hold for every generator below:
///
/// 1. **Pure.** No clock, no randomness that is not seeded, no `Date()`. Two calls
///    with the same arguments return the same array, which is what lets a QA replay
///    and a device run read the same log pane.
/// 2. **Terminated.** Every sequence ends with a `.end` beat, and `endState()` is
///    that beat's time. Reduce Motion collapses a sequence to its end state
///    (`collapsed()`), which is the whole of D18's visual half — sound and haptics
///    are unchanged, and stay on the beats they were on.
/// 3. **Cue-carrying.** A beat names both channels: `cue` is the haptic and `sound`
///    is the audio. They are the same vocabulary (`SocCue`) so the app has one
///    switch, and either may be `nil` — a beat that only moves pixels is silent in
///    both.
///
/// Nothing here reads content, so `Feel/` keeps importing Foundation and nothing
/// else (§10 C5 #3) and the whole file is exercised by `swift test` on macOS.
public enum Sequences {

  // MARK: - §1 · Shift handover

  /// The eyebrow types in at one glyph per 18 ms (§1 row 1).
  public static let glyphMs: Milliseconds = 18
  /// The board slides up (§1 row 2).
  public static let boardRiseAtMs: Milliseconds = 600
  /// The first alert lands (§1 row 3).
  public static let firstAlertAtMs: Milliseconds = 900
  /// One alert per 260 ms (§1 row 3).
  public static let alertStepMs: Milliseconds = 260
  /// The gap between the last alert's slot ending and Vale's card (§1 row 4).
  public static let handoverMessageGapMs: Milliseconds = 400
  /// Typing dots before a message card resolves into text (§1 row 4, §6).
  public static let typingDotsMs: Milliseconds = 500
  /// The gap between the message resolving and the dock rising (§1 row 5).
  public static let handoverDockGapMs: Milliseconds = 300
  /// The dock's own rise — the last thing to finish before `Clock in ▸` is live.
  public static let dockRiseMs: Milliseconds = 260
  /// `Clock in` cuts to black for this long before the first alert arrives (§1).
  public static let handoverCutMs: Milliseconds = 120

  /// **§1 — the opening.** Black ground, the board, `alertCount` alerts landing one
  /// per 260 ms, Vale's one line, the dock.
  ///
  /// The rows FEEL.md writes as `+400` / `+300` chain from the **end** of the row
  /// above: the alert run's last slot closes at `900 + n × 260` (which is what
  /// "900 → 900+7×260" measures), and the message row is 500 ms of typing dots
  /// before its text, so the dock waits for the text and not for the dots. For the
  /// seven-alert board of shift 1 that puts the dock at 3920 ms and the sequence's
  /// end state at 4180 ms — the "≈ 4.5 s" of §1, which is the only number in the
  /// document written with a `≈`.
  ///
  /// Sound is a `ping` per alert, stepping up in pitch (`SoundBank` renders seven
  /// pitches and the beat's index picks one); the haptic is `select`. Room tone
  /// fades in under the whole thing and is the sound service's business, not a
  /// beat's — it is a state, not an event.
  public static func handoverSequence(alertCount: Int) -> [Beat] {
    let alerts = max(0, alertCount)
    var beats: [Beat] = [
      Beat(at: 0, kind: .ground),
      Beat(at: 0, kind: .eyebrow),
      Beat(at: boardRiseAtMs, kind: .boardRise),
    ]
    for index in 0..<alerts {
      beats.append(
        Beat(
          at: firstAlertAtMs + index * alertStepMs, kind: .alertLand(index),
          cue: .select, sound: .ping))
    }
    let runEnd = firstAlertAtMs + alerts * alertStepMs
    let message = runEnd + handoverMessageGapMs
    beats.append(Beat(at: message, kind: .message, cue: .commitSoft, sound: .tick))
    let dock = message + typingDotsMs + handoverDockGapMs
    beats.append(Beat(at: dock, kind: .dock))
    beats.append(Beat(at: dock + dockRiseMs, kind: .end))
    return beats
  }

  // MARK: - §2 · Alert arrival

  /// The ECG spike and the queue pill (§2 row 2).
  public static let arrivalSpikeAtMs: Milliseconds = 120
  /// The trigger line starts typing (§2 row 3).
  public static let arrivalTriggerAtMs: Milliseconds = 260
  /// How long the trigger line takes to type — "~700 ms" (§2 row 3).
  public static let arrivalTriggerTypeMs: Milliseconds = 700
  /// The alert title and the `ASSET:` line (§2 row 4).
  public static let arrivalTitleAtMs: Milliseconds = 1100
  /// The severity chip stamps in (§2 row 5).
  public static let arrivalSeverityAtMs: Milliseconds = 1500
  /// How long the chip's 1.3 → 1 scale takes (§2 row 5).
  public static let arrivalSeverityStampMs: Milliseconds = 140
  /// The SOURCES list rises, collapsed (§2 row 6).
  public static let arrivalSourcesAtMs: Milliseconds = 1800
  /// The coach line, shift 1 only (§2 row 7).
  public static let arrivalCoachAtMs: Milliseconds = 2100

  /// **§2 — every case starts as an event, not a page.**
  ///
  /// `withCoach` is the shift-1 coach line; every other shift ends at the sources
  /// rising. The severity chip's sound is a `tick` pitched by severity (§2's
  /// "`severity` tick at 1500"), which is why the cue is `tick` and not a row of
  /// its own — §9's asset table has one tick and `SoundBank` pitches it.
  public static func arrivalSequence(withCoach: Bool = false) -> [Beat] {
    var beats: [Beat] = [
      Beat(at: 0, kind: .ground),
      Beat(at: arrivalSpikeAtMs, kind: .ecgSpike, cue: .select, sound: .arrive),
      Beat(at: arrivalSpikeAtMs, kind: .queuePill),
      Beat(at: arrivalTriggerAtMs, kind: .trigger),
      Beat(at: arrivalTitleAtMs, kind: .title),
      Beat(at: arrivalSeverityAtMs, kind: .severity, cue: .commitSoft, sound: .tick),
      Beat(at: arrivalSourcesAtMs, kind: .sources),
    ]
    if withCoach { beats.append(Beat(at: arrivalCoachAtMs, kind: .coach)) }
    beats.append(Beat(at: beats.last?.at ?? arrivalSourcesAtMs, kind: .end))
    return beats
  }

  // MARK: - §4 · The pull

  /// The shortest gap between two log lines (§4 row 2).
  public static let logLineMinGapMs: Milliseconds = 280
  /// The longest gap between two log lines (§4 row 2).
  public static let logLineMaxGapMs: Milliseconds = 420
  /// The fewest log lines a pull streams (§4 row 2).
  public static let minLogLines = 4
  /// The most log lines a pull streams (§4 row 2).
  public static let maxLogLines = 6
  /// `cost ≤ 8m → 1.5 s` (§4, "Duration scales with cost").
  public static let pullShortMs: Milliseconds = 1500
  /// `10m → 2.0 s`. Also 9 m and 11 m, which the table does not name.
  public static let pullMediumMs: Milliseconds = 2000
  /// `≥ 12m → 2.4 s`.
  public static let pullLongMs: Milliseconds = 2400
  /// The cost at or below which a pull is short.
  public static let pullShortCost = 8
  /// The cost at or above which a pull is long.
  public static let pullLongCost = 12
  /// "Second and later pulls in the same case are 25 % faster" (§4).
  public static let pullRepeatScale = 0.75
  /// Findings land one per 260 ms (§4 row 4).
  public static let findingStepMs: Milliseconds = 260
  /// "max 3 before the rest appear together" (§4 row 4) — and the haptic cap.
  public static let findingSoloCap = 3
  /// The extra ECG beat when a decisive finding landed (§4 row 5).
  public static let decisiveGapMs: Milliseconds = 260

  /// How long the log pane runs for a pull of `cost` shift-minutes.
  public static func pullDurationMs(cost: Int, isRepeat: Bool = false) -> Milliseconds {
    let base: Milliseconds
    if cost <= pullShortCost {
      base = pullShortMs
    } else if cost < pullLongCost {
      base = pullMediumMs
    } else {
      base = pullLongMs
    }
    guard isRepeat else { return base }
    return Int((Double(base) * pullRepeatScale).rounded())
  }

  /// **§4 — the pull is a moment, not a progress bar.**
  ///
  /// Four to six log lines stream into the pane, jittered between 280 and 420 ms
  /// apart and **seeded**, so the same pull reads the same every time it is
  /// replayed and two different sources never stream in step. The gaps are then
  /// scaled onto the window `pullDurationMs(cost:isRepeat:)` gives, which is the
  /// only way §4's two rules — "one per 280–420 ms" and "duration scales with
  /// cost" — can both be true of the same pane: the *shape* of the stream is the
  /// jitter, the *length* is the cost. A repeat pull is 25 % faster and therefore
  /// 25 % more urgent, with the same number of lines.
  ///
  /// `findingCount` and `hasDecisive` default to nothing so the ticket's
  /// `pullSequence(cost:isRepeat:seed:)` is a legal call: a caller that only wants
  /// the query timeline gets it, and the source sheet — which knows how many
  /// findings the pull surfaced — gets the cards too. The first three cards carry
  /// `findingLand` (haptic and sound); the rest carry `landCard`, which is sound
  /// only, because §4 caps the haptic at three and not the sound.
  public static func pullSequence(
    cost: Int, isRepeat: Bool, seed: UInt64, findingCount: Int = 0, hasDecisive: Bool = false
  ) -> [Beat] {
    let total = pullDurationMs(cost: cost, isRepeat: isRepeat)
    var beats: [Beat] = [Beat(at: 0, kind: .queryOpen, cue: .select, sound: .queryStart)]

    for (index, at) in logLineTimes(total: total, seed: seed).enumerated() {
      beats.append(Beat(at: at, kind: .logLine(index), sound: .tick))
    }

    beats.append(Beat(at: total, kind: .results, cue: .commitSoft, sound: .commitSoft))

    let cards = max(0, findingCount)
    for index in 0..<cards {
      let slot = min(index, findingSoloCap)
      beats.append(
        Beat(
          at: total + slot * findingStepMs, kind: .card(index),
          cue: index < findingSoloCap ? .findingLand : nil, sound: .landCard))
    }
    let cardsEnd = total + min(max(cards - 1, 0), findingSoloCap) * findingStepMs
    if hasDecisive { beats.append(Beat(at: cardsEnd + decisiveGapMs, kind: .decisive)) }
    beats.append(Beat(at: beats.map(\.at).max() ?? total, kind: .end))
    return beats
  }

  /// The 4–6 jittered log-line times inside a window, seeded.
  ///
  /// `n + 1` gaps are drawn and the last one is the tail between the final line and
  /// the `RESULTS` header, so no line ever lands *on* the header. The gaps are then
  /// scaled onto `total`; the ratios between them — the jitter a player actually
  /// perceives — survive the scaling, which is the point.
  public static func logLineTimes(total: Milliseconds, seed: UInt64) -> [Milliseconds] {
    var rng = SeededRandom(seed: seed)
    let count = minLogLines + Int(rng.next(upperBound: UInt64(maxLogLines - minLogLines + 1)))
    let span = UInt64(logLineMaxGapMs - logLineMinGapMs + 1)
    var gaps: [Milliseconds] = []
    for _ in 0...count { gaps.append(logLineMinGapMs + Int(rng.next(upperBound: span))) }

    var prefix: [Milliseconds] = []
    var running = 0
    for gap in gaps {
      running += gap
      prefix.append(running)
    }
    guard let raw = prefix.last, raw > 0 else { return [] }
    return prefix.dropLast().map { Int((Double($0) * Double(total) / Double(raw)).rounded()) }
  }

  // MARK: - §8 · The call

  /// The stamp slams (§8 row 3).
  public static let stampAtMs: Milliseconds = 450
  /// How long the stamp's 1.4 → 1 scale takes (§8 row 3).
  public static let stampScaleMs: Milliseconds = 180
  /// The ground returns and the headline fades in (§8 row 4).
  public static let verdictAtMs: Milliseconds = 900
  /// The `TRUTH:` chip flips (§8 row 5).
  public static let truthAtMs: Milliseconds = 1200
  /// The meters sweep with a count-up (§8 row 6).
  public static let metersAtMs: Milliseconds = 1500
  /// `WHY` and the decisive findings (§8 row 7).
  public static let whyAtMs: Milliseconds = 2100
  /// The stagger between the `WHY` items (§8 row 7).
  public static let whyStaggerMs: Milliseconds = 80
  /// "Tap anywhere from 450 ms onward → end state" (§8).
  public static let callSkipFromMs: Milliseconds = stampAtMs
  /// The breach thud fires at or above this delta (§8 row 6; the same threshold
  /// `DESIGN.md` §2.15 gives the cue).
  public static let breachThudDelta = 30
  /// The room tone ducks for this long under `file` (§9's room-tone row).
  public static let fileDuckMs: Milliseconds = 600

  /// **§8 — the call is a cut, not a transition.**
  ///
  /// `verdict` is the graded cue the debrief mounts with — the caller passes
  /// `SocCue.verdict(grade)`, which is where the good / off / wrong decision has
  /// always been made, so this function never grades anything. `breachDelta` is the
  /// only number it branches on, and it branches on it exactly once: at 1500 ms,
  /// with the meters, the way `DESIGN.md` §2.15 files it.
  public static func callSequence(breachDelta: Int, verdict: SocCue = .verdictGood) -> [Beat] {
    var beats: [Beat] = [
      Beat(at: 0, kind: .cut, cue: .file, sound: .file),
      Beat(at: stampAtMs, kind: .stamp, sound: .stamp),
      Beat(at: verdictAtMs, kind: .verdict, cue: verdict, sound: verdict),
      Beat(at: truthAtMs, kind: .truth),
      Beat(at: metersAtMs, kind: .meters),
    ]
    if breachDelta >= breachThudDelta {
      beats.append(Beat(at: metersAtMs, kind: .breach, cue: .breachThud, sound: .breachThud))
    }
    beats.append(Beat(at: whyAtMs, kind: .why))
    beats.append(Beat(at: whyAtMs + whyStaggerMs, kind: .end))
    return beats
  }

  // MARK: - §5 · Pressure you can feel

  /// **The time pulse** (§5). Shift-minutes used against the budget, as a band.
  ///
  /// `< 50 % → CALM`, `50–75 % → ALERT`, `75–100 % → HUNT`, `> 100 % → LOCKDOWN`.
  /// Integer arithmetic throughout: a `Double` ratio would put 45/90 either side of
  /// 0.5 depending on the platform's rounding, and the band a player feels is not
  /// somewhere to spend a float.
  ///
  /// **Presentation only.** `scoreShift` never sees this — the shift is scored on
  /// what was called, not on how long it took (§5, and the founder's "no hard
  /// timer"). A budget of zero or less is CALM: there is nothing to be late for.
  public static func timeStatus(used: Int, budget: Int) -> TraceStatus {
    guard budget > 0 else { return .calm }
    let spent = max(0, used)
    if spent * 4 < budget * 2 { return .calm }
    if spent * 4 < budget * 3 { return .alert }
    if spent <= budget { return .hunt }
    return .lockdown
  }

  /// What the desk *feels* like: the worse of the engine's band and the clock's
  /// (§5). `TraceStatus` is `Comparable` in the CALM < ALERT < HUNT < LOCKDOWN
  /// order (DV-3), so this is `max` and not a rank table.
  ///
  /// The heartbeat follows this rather than the engine's band alone, which is what
  /// makes the desk start to thump when you are burning the shift — without a
  /// single number of the score moving.
  public static func feltStatus(engine: TraceStatus, time: TraceStatus) -> TraceStatus {
    max(engine, time)
  }

  /// The shortest gap between two live-board reveals (§5).
  public static let boardRevealMinGapMs: Milliseconds = 25_000
  /// The longest gap between two live-board reveals (§5).
  public static let boardRevealMaxGapMs: Milliseconds = 40_000
  /// How long a schedule is generated for, by default — a very long case. The cap
  /// that matters is `remaining`, not this.
  public static let boardRevealHorizonMs: Milliseconds = 900_000

  /// **The live board** (§5). One upcoming alert reveals its severity every ~25–40
  /// seconds of real time while the player is investigating.
  ///
  /// Seeded, so a case that is re-entered does not re-roll its board; **capped at
  /// the remaining queue**, so the desk cannot reveal an alert that is not there;
  /// and ordered by a seeded shuffle, so the reveals do not walk the queue
  /// top-to-bottom and read as a progress bar. Nothing about the queue's order or
  /// content moves — only what the player has been shown.
  public static func boardRevealSchedule(
    remaining: Int, seed: UInt64, horizonMs: Milliseconds = boardRevealHorizonMs
  ) -> [BoardReveal] {
    let count = max(0, remaining)
    guard count > 0 else { return [] }
    var rng = SeededRandom(seed: seed)

    var order = Array(0..<count)
    // Fisher–Yates with the seeded generator: deterministic, and every index
    // appears exactly once, so `remaining` really is the cap.
    if order.count > 1 {
      for index in stride(from: order.count - 1, to: 0, by: -1) {
        let pick = Int(rng.next(upperBound: UInt64(index + 1)))
        order.swapAt(index, pick)
      }
    }

    let span = UInt64(boardRevealMaxGapMs - boardRevealMinGapMs + 1)
    var out: [BoardReveal] = []
    var at = 0
    for alertIndex in order {
      at += boardRevealMinGapMs + Int(rng.next(upperBound: span))
      guard at <= horizonMs else { break }
      out.append(BoardReveal(atMs: at, alertIndex: alertIndex))
    }
    return out
  }

  // MARK: - Seeding

  /// A stable seed for a string — the case id, or a case id and a source id joined.
  ///
  /// FNV-1a, written out rather than taken from `Hasher`: `Hashable`'s hash values
  /// are salted per process and would give the same pull a different log pane on
  /// every launch, which is exactly what "seeded by case id so it's deterministic"
  /// (§4) forbids.
  public static func seed(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    return hash
  }
}

// MARK: - Beat

/// One moment in a sequence: when it happens, what happens, and what it costs the
/// player's hand and ear.
///
/// `cue` and `sound` are the same vocabulary on purpose (§9: "a single `SoundBank`
/// enum maps `SocCue` → file, so cues and sounds stay one vocabulary"). A beat that
/// only moves pixels has both `nil`; a beat that is heard but not felt — a log
/// line's tick, a card past the third — has only `sound`.
public struct Beat: Sendable, Hashable, Codable {
  /// Milliseconds from the top of the sequence.
  public let at: Milliseconds
  public let kind: BeatKind
  /// The haptic, or `nil` for a beat that is not felt.
  public let cue: SocCue?
  /// The sound, or `nil` for a beat that is not heard.
  public let sound: SocCue?

  public init(at: Milliseconds, kind: BeatKind, cue: SocCue? = nil, sound: SocCue? = nil) {
    self.at = at
    self.kind = kind
    self.cue = cue
    self.sound = sound
  }

  /// The same beat, at the top of the sequence — Reduce Motion's collapse (D18).
  public var collapsed: Beat { Beat(at: 0, kind: kind, cue: cue, sound: sound) }
}

/// What a beat *is*. The associated values are the index of the thing arriving —
/// which alert, which log line, which card — because a sequence is a list and the
/// screen has to know which row a beat is about.
public enum BeatKind: Sendable, Hashable, Codable {

  // §1 · handover
  /// Black ground; the sequence's floor.
  case ground
  /// `SHIFT HANDOVER · 08:00`, typing in one glyph at a time.
  case eyebrow
  /// The empty rail slides up.
  case boardRise
  /// One alert lands on the rail, as a single line.
  case alertLand(Int)
  /// A message card from the left rail: typing dots, then text (§6).
  case message
  /// The dock rises with `Clock in ▸`.
  case dock

  // §2 · arrival
  /// The ECG spikes once, ×3 amplitude for one beat.
  case ecgSpike
  /// The queue pill increments.
  case queuePill
  /// The trigger line types in, log voice, mono.
  case trigger
  /// The alert title and the `ASSET:` line.
  case title
  /// The severity chip stamps in with the detection rule beneath it.
  case severity
  /// The SOURCES list rises, collapsed.
  case sources
  /// The shift-1 coach line slides in.
  case coach

  // §4 · the pull
  /// The sheet opens on the log pane.
  case queryOpen
  /// One fake log line streams in.
  case logLine(Int)
  /// The `RESULTS · {n} findings` header; the sheet grows.
  case results
  /// One finding card lands on the board.
  case card(Int)
  /// A decisive finding landed: an extra ECG beat and a band-word pulse.
  case decisive

  // §8 · the call
  /// Cut to black; the SystemBar hides.
  case cut
  /// The stamp slams, rotated −3°.
  case stamp
  /// The ground returns and the headline fades in.
  case verdict
  /// The `TRUTH:` chip flips.
  case truth
  /// The meters sweep with a count-up.
  case meters
  /// The breach thud and the rose edge flash.
  case breach
  /// `WHY` and the decisive findings, staggered.
  case why

  /// The last beat: nothing arrives, the sequence is simply over. `endState()` is
  /// this beat's time, and Reduce Motion collapses everything onto it.
  case end
}

/// One live-board reveal (§5): at `atMs`, the alert at `alertIndex` in the
/// remaining queue shows its severity.
public struct BoardReveal: Sendable, Hashable, Codable {
  public let atMs: Milliseconds
  public let alertIndex: Int

  public init(atMs: Milliseconds, alertIndex: Int) {
    self.atMs = atMs
    self.alertIndex = alertIndex
  }
}

// MARK: - Reading a sequence

extension Array where Element == Beat {

  /// When the sequence is over — the `.end` beat, or the last beat if a caller
  /// built one by hand without it.
  public var endStateMs: Milliseconds {
    first(where: { $0.kind == .end })?.at ?? (map(\.at).max() ?? 0)
  }

  /// **Reduce Motion** (§1–§8's last line, D18): every beat at zero, in the same
  /// order, with the same cues. The screen therefore draws its end state on the
  /// first frame and still plays every sound and every haptic — a sequence is not
  /// a decoration a player can lose by asking the system for less motion.
  public func collapsed() -> [Beat] {
    map(\.collapsed)
  }

  /// The beats at or before `atMs`, for a screen driving a sequence off a timer.
  public func upTo(_ atMs: Milliseconds) -> [Beat] {
    filter { $0.at <= atMs }
  }

  /// Every beat's haptic, in order — what the hand feels over the whole sequence.
  public var cues: [SocCue] { compactMap(\.cue) }
  /// Every beat's sound, in order.
  public var sounds: [SocCue] { compactMap(\.sound) }
}

// MARK: - Seeded randomness

/// A small deterministic generator — SplitMix64.
///
/// `SystemRandomNumberGenerator` is the wrong tool twice over: it cannot be seeded,
/// and it is not reproducible across launches, so a jittered log pane would be
/// different every time a player re-read the same pull. SplitMix64 is eight lines,
/// has no state beyond a `UInt64`, and passes well enough for jitter — which is all
/// that is being asked of it.
public struct SeededRandom: RandomNumberGenerator, Sendable {
  private var state: UInt64

  public init(seed: UInt64) {
    // A zero seed would make SplitMix64 walk a fixed low-entropy path; the golden
    // ratio constant is the reference implementation's own increment.
    self.state = seed == 0 ? 0x9e37_79b9_7f4a_7c15 : seed
  }

  public mutating func next() -> UInt64 {
    state = state &+ 0x9e37_79b9_7f4a_7c15
    var z = state
    z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z >> 31)
  }
}
