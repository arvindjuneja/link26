import SentryCore
import SwiftUI
import Testing
import UIKit

@testable import SentrySOC

/// The half of C7 a screenshot cannot prove.
///
/// A PNG shows that the ring is drawn; it cannot show that releasing at 400 ms files
/// nothing, that the ticks land at 0 / 180 / 360 ms, that every named animation
/// collapses under Reduce Motion, or that `severityMeta.High`'s exported `orange`
/// reaches the HUNT hue rather than falling through to body text. Those are here.
@MainActor
@Suite("Component behaviour")
struct ComponentBehaviourTests {

  // MARK: - Hold to file (acceptance #3)

  @Test("the hold ticks at 0 / 180 / 360 ms and completes at 550 ms")
  func holdTimings() {
    #expect(Motion.holdToFileDuration == 0.55)
    #expect(Motion.holdToFileTicks == [0, 0.18, 0.36])

    var hold = HoldProgress()
    #expect(hold.begin() == [0], "the first tick fires under the thumb, not a frame later")
    #expect(hold.advance(elapsed: 0.10) == .init(ticks: [], completed: false))
    #expect(hold.advance(elapsed: 0.18) == .init(ticks: [1], completed: false))
    #expect(hold.advance(elapsed: 0.30) == .init(ticks: [], completed: false))
    #expect(hold.advance(elapsed: 0.36) == .init(ticks: [2], completed: false))
    #expect(hold.advance(elapsed: 0.54) == .init(ticks: [], completed: false))
    #expect(hold.advance(elapsed: 0.55).completed)
  }

  @Test("a tick is never reported twice, and a skipped frame reports both")
  func holdTicksAreIdempotent() {
    var hold = HoldProgress()
    _ = hold.begin()
    // One long frame across both remaining ticks: both fire, in order, once.
    #expect(hold.advance(elapsed: 0.40) == .init(ticks: [1, 2], completed: false))
    #expect(hold.advance(elapsed: 0.41) == .init(ticks: [], completed: false))
  }

  @Test("releasing early is zero state change")
  func holdCancelIsInert() {
    var hold = HoldProgress()
    _ = hold.begin()
    _ = hold.advance(elapsed: 0.40)
    hold.cancel()

    #expect(hold == HoldProgress(), "a cancelled hold is indistinguishable from one never started")
    #expect(hold.fraction(elapsed: 0.40, reduceMotion: false) == 0)
    // And a cancelled hold cannot complete on a late frame from the gesture it lost.
    #expect(hold.advance(elapsed: 9.0) == .init(ticks: [], completed: false))
  }

  @Test("Reduce Motion fills the ring in three discrete steps")
  func holdReducedMotionSteps() {
    var hold = HoldProgress()
    _ = hold.begin()
    #expect(hold.fraction(elapsed: 0.05, reduceMotion: true) == 1.0 / 3.0)
    _ = hold.advance(elapsed: 0.18)
    #expect(hold.fraction(elapsed: 0.20, reduceMotion: true) == 2.0 / 3.0)
    _ = hold.advance(elapsed: 0.36)
    #expect(hold.fraction(elapsed: 0.40, reduceMotion: true) == 1)
    // The sweep is continuous at the same moments — the two paths differ only here.
    #expect(hold.fraction(elapsed: 0.40, reduceMotion: false) == 0.40 / 0.55)
  }

  // MARK: - The Reduce Motion gate (acceptance #5)

  /// `Motion` is `@MainActor` (the app target defaults every type to it), so this
  /// enumerates the roster inline rather than through `@Test(arguments:)`, whose
  /// generated argument list is evaluated off the main actor.
  @Test("every named animation collapses through the one gate")
  func motionGate() {
    let roster: [(String, Animation)] = [
      ("screenPush", Motion.screenPush),
      ("screenPushCurve", Motion.screenPushCurve),
      ("sheet", Motion.sheet),
      ("scrim", Motion.scrim),
      ("queryProgress", Motion.queryProgress),
      ("findingLand", Motion.findingLand),
      ("stamp", Motion.stamp),
      ("meterSweep", Motion.meterSweep),
      ("payout", Motion.payout),
      ("rankBadgeDraw", Motion.rankBadgeDraw),
      ("rankBadgeFill", Motion.rankBadgeFill),
      ("glowPulse", Motion.glowPulse(periodSeconds: 0.536)),
    ]
    for (name, animation) in roster {
      #expect(Motion.gated(animation, reduceMotion: true) == nil, "\(name) survives Reduce Motion")
      #expect(Motion.gated(animation, reduceMotion: false) != nil, "\(name) is gated away always")
    }

    // The one documented exception, named in `Motion` so `verify.sh`'s gate grep has
    // an allowance with its reason attached rather than a bare duration literal in
    // `Components/`. It is a pressed state — direct manipulation, 80 ms, 2 % of
    // travel — and `PressableStyle` is its only call site.
    #expect(Motion.pressUngated == Animation.easeOut(duration: 0.08))
    #expect(Motion.gated(Motion.pressUngated, reduceMotion: true) == nil,
            "the gate still works on it; PressableStyle chooses not to use the gate")
  }

  // MARK: - Tones (R2)

  @Test("the exported `orange` tone resolves to the HUNT hue, not to body text")
  func orangeTone() {
    let orange = Tone(rawValue: "orange")
    #expect(Theme.tone(orange) == Theme.Orange.c300)
    #expect(Theme.tone(orange) != Theme.textSecondary, "orange must not fall through to the default")
    // The HUNT band is the hue's home; the chip borrows it so a `High` label reads
    // as one notch below a real breach.
    #expect(Theme.status(.hunt).text == Theme.Orange.c300)
  }

  @Test("severityMeta reaches Theme through the bundle, fallback included")
  func severityTones() {
    let copy = ContentPack.bundled.copy
    #expect(Theme.tone(copy.severityMeta.meta(for: "High").tone) == Theme.Orange.c300)
    #expect(Theme.tone(copy.severityMeta.meta(for: "Critical").tone) == Theme.Rose.c300)
    // S5: a severity authored after this build keeps its own text and takes the
    // documented fallback run rather than blanking the chip.
    let unknown = copy.severityMeta.meta(for: "Informational")
    #expect(unknown.label == "Informational")
    #expect(Theme.tone(unknown.tone) == Theme.textQuiet)
  }

  @Test("CALM is cyan — the blue seat's ramp, not the red seat's emerald")
  func calmIsCyan() {
    #expect(Theme.status(.calm).text == Theme.Cyan.c300)
    #expect(Theme.status(.calm).text != Theme.Emerald.c300)
    // Colour is spent as tension rises: nothing glows at CALM.
    #expect(Theme.status(.calm).glowOpacity == 0)
    #expect(Theme.status(.alert).glowOpacity == 0.08)
    #expect(Theme.status(.hunt).glowOpacity == 0.14)
    #expect(Theme.status(.lockdown).glowOpacity == 0.22)
  }

  @Test("every tone the bundle authors resolves to a colour a reader can see")
  func everyAuthoredToneResolves() throws {
    let copy = ContentPack.bundled.copy
    var authored = Set<String>()
    for segments in [copy.intro.taxonomy, copy.intro.severity, copy.ladder.body,
                     copy.intro.handoff.blueOnly, copy.intro.handoff.redSeat] {
      for segment in segments { if let tone = segment.tone { authored.insert(tone.rawValue) } }
    }
    for meta in copy.dispositionMeta.values { authored.insert(meta.tone.rawValue) }
    for meta in copy.gradeMeta.values { authored.insert(meta.tone.rawValue) }
    for meta in copy.severityMeta.entries.values { authored.insert(meta.tone.rawValue) }
    for meta in copy.handlerToneMeta.entries.values { authored.insert(meta.tone.rawValue) }

    #expect(!authored.isEmpty)
    for raw in authored {
      let tone = Tone(rawValue: raw)
      #expect(
        Theme.tone(tone) != Theme.textSecondary || raw == "em",
        "\(raw) falls through to the default run — Theme.tone is missing a case")
    }
  }

  // MARK: - Type (R11)

  @Test("the two new type steps bind to faces the bundle actually registers")
  func newTypeStepsResolve() {
    // R11's grade numeral is Plex SemiBold, which also carries the stamp — so no
    // registered face is dead weight.
    #expect(UIFont(name: Typography.Mono.semibold.rawValue, size: 28) != nil)
    // R11's quiet log step is Plex **Regular**, not Light: the Light TTF is not in
    // the bundle and `Resources/` + `project.yml` are outside C7's ownership. This
    // assertion is the tripwire — the day Light ships, `registeredFaceNames` grows
    // and the divergence recorded in `Typography.quietLog` can be closed.
    #expect(UIFont(name: Typography.Mono.regular.rawValue, size: 11) != nil)
    #expect(
      !Typography.registeredFaceNames.contains(where: { $0.hasSuffix("Light") }),
      "IBMPlexMono-Light is not registered — see the divergence note on Typography.quietLog")
  }

  @Test("the body step lands §2.16's 1.55 line height against the real face metric")
  func bodyLineHeightIsMeasured() throws {
    let size: CGFloat = 15
    let face = try #require(
      UIFont(name: Typography.Grotesk.regular.rawValue, size: size),
      "Space Grotesk is not registered — the line height below would be system-ui's")

    // `.lineSpacing` is additive: total = the face's own line box + the added
    // leading. The ratio is asked of CoreText, never transcribed from `hhea` — the
    // hand-typed 1.257 that shipped first is 1.5 % under the rendered 1.276 and put
    // the body at 1.569 ×.
    let total = face.lineHeight + Typography.bodyLineSpacing
    #expect(
      abs(total / size - 1.55) < 0.01,
      "body line height is \(total / size) ×, not §2.16's 1.55 × — the face metric moved")

    // And the clamp holds: a ratio tighter than the face's own box cannot be
    // expressed through `lineSpacing`, so it floors at 0 rather than overlapping.
    #expect(Typography.lineSpacing(forSize: size, ratio: 1.0) == 0)
  }

  // MARK: - Targets and glyphs

  @Test("the §2.2 thumb-zone floors are what the design says")
  func hitTargets() {
    #expect(Theme.Hit.minimum == 44)
    #expect(Theme.Hit.row == 56)
    #expect(Theme.Hit.primaryCTA == 56)
    #expect(Theme.Hit.holdToFile == 64)
    #expect(Theme.Hit.dispositionRow == 68)
    #expect(Theme.Hit.gap == 8)
  }

  @Test("the pressed state is a real, visible change")
  func pressedState() {
    #expect(Theme.Press.scale < 1)
    #expect(Theme.Press.opacity < 1)
  }

  @Test("the glyph roster is glyphs — no emoji reached the deck")
  func glyphsAreNotEmoji() {
    for glyph in Glyph.all {
      for scalar in glyph.unicodeScalars {
        #expect(
          !scalar.properties.isEmojiPresentation,
          "\(glyph) renders as emoji — DESIGN §2.16 allows glyphs only")
      }
    }
  }
}
