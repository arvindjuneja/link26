import SwiftUI
import SentryCore

/// Every named animation of `DESIGN.md` §2.14, and **one** Reduce-Motion gate.
///
/// The budget rule (design doc §10) is part of the contract, not a preference: no
/// idle decorative motion, no glitch, no scanlines, no CRT. Motion is spent as
/// tension rises; CALM is deliberately still.
///
/// **Reduce Motion stops visual motion only — it does NOT disable haptics (D18).**
/// The heartbeat is a non-visual channel and an accessibility *aid* for a player who
/// cannot track a sweeping meter; the Settings toggle is the haptics off-switch.
enum Motion {

  // ── durations and curves ───────────────────────────────────────────────────

  /// Screen push: 260 ms, `cubic-bezier(.2,.8,.2,1)`, `translateX 24 → 0` + fade.
  /// `.smooth(duration:extraBounce: 0)` is the native form of that curve (§4.2).
  static let screenPush = Animation.smooth(duration: 0.26, extraBounce: 0)
  /// The literal §2.14 curve, for the two places a spring reads wrong.
  static let screenPushCurve = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)
  /// How far a pushed screen travels.
  static let screenPushOffset: CGFloat = 24

  /// Sheet: 320 ms up.
  static let sheet = Animation.smooth(duration: 0.32, extraBounce: 0)
  /// Its scrim fades in 200 ms.
  static let scrim = Animation.easeOut(duration: 0.20)

  /// The 600 ms `QueryProgress` bar a source pull runs behind.
  static let queryProgress = Animation.linear(duration: 0.60)
  /// A finding lands: `translateY 12 → 0` + fade, 220 ms.
  static let findingLand = Animation.smooth(duration: 0.22, extraBounce: 0)
  static let findingLandOffset: CGFloat = 12
  /// 45 ms between landings. Capped at 3 per pull, which is also the `findingLand`
  /// haptic cap — one feeling per landing, never a burst.
  static let findingStagger: Double = 0.045

  /// The stamp: 180 ms, `scale 1.4 → 1` + `rotate(-3°)`. Once per call, and the
  /// single most important 180 ms in the app.
  static let stamp = Animation.spring(duration: 0.18, bounce: 0.35)
  static let stampScaleFrom: CGFloat = 1.4
  static let stampRotation = Angle.degrees(-3)

  /// A meter delta: 600 ms sweep, numeric count-up alongside.
  static let meterSweep = Animation.smooth(duration: 0.60, extraBounce: 0)
  /// The payout: 800 ms count-up; the standing bar sweeps old → new.
  static let payout = Animation.smooth(duration: 0.80, extraBounce: 0)
  /// The rank badge: 900 ms `stroke-dashoffset` draw, then a 10 % fill.
  static let rankBadgeDraw = Animation.easeInOut(duration: 0.90)
  /// The same 900 ms, as a number — the fill has to start when the draw ends.
  static let rankBadgeDrawDuration: Double = 0.90
  /// The 10 % fill that arrives behind the finished stroke.
  static let rankBadgeFill = Animation.easeOut(duration: 0.30)

  /// **Hold to file** (§2.9, §5.7). 550 ms is the stamp: long enough that it is a
  /// decision and not a slip, short enough that it never feels like a punishment.
  static let holdToFileDuration: TimeInterval = 0.55
  /// The three ticks under the thumb, in seconds from press. They are a *rhythm*,
  /// not a progress read-out — the ring is the read-out.
  static let holdToFileTicks: [TimeInterval] = [0, 0.18, 0.36]
  /// A drag this far off the button abandons the hold. Slop, not precision: the
  /// thumb rolls while it presses, and a roll is not a change of mind.
  static let holdToFileCancelSlop: CGFloat = 44

  // ── the feel pass (F2b, `docs/ios/FEEL.md`) ────────────────────────────────
  //
  // Durations only. *When* each of these plays is `SentryCore`'s
  // `Sequences` — the timelines of §1/§2/§4/§8, asserted in `SequenceTests` — and
  // *whether* it plays at all is still `Motion.gated`. Nothing below re-times a beat;
  // each one is how long the pixels take to settle once the beat has landed.

  /// One beat arriving: the default settle for anything the Director marks arrived.
  /// 220 ms is `findingLand`'s curve, which is the deck's existing "a thing landed".
  static let beatArrive = Animation.smooth(duration: 0.22, extraBounce: 0)
  /// How far a beat's content travels as it lands — §1's slots, §2's rows, §4's
  /// cards. The same 12 pt `findingLand` already spends.
  static let beatRise: CGFloat = 12

  /// **§2's severity chip**: `scale 1.3 → 1` over 140 ms. A stamp, smaller — the
  /// tool making a claim, not the analyst filing one, so it is 40 ms shorter and less
  /// bouncy than `Motion.stamp`.
  static let severityStamp = Animation.spring(duration: 0.14, bounce: 0.28)
  static let severityStampScaleFrom: CGFloat = 1.3

  /// **§1's cut** — `Clock in` to the first alert, and §8's cut to black.
  static let cut = Animation.easeInOut(duration: 0.12)

  /// **§8's `TRUTH:` flip**, 200 ms.
  static let truthFlip = Animation.smooth(duration: 0.20, extraBounce: 0)
  /// The rose edge flash behind the breach thud. One pulse, out slower than in, so it
  /// reads as a wince rather than a strobe.
  static let breachFlash = Animation.easeOut(duration: 0.45)

  /// **§6's message card**: Vale slides in from the left rail.
  static let messageCard = Animation.smooth(duration: 0.26, extraBounce: 0)
  /// How long an interjection stays before it withdraws. Long enough to read
  /// fourteen words twice, short enough that it never becomes furniture.
  static let valeDwellSeconds: Double = 6.0
  /// The typing dots' own bob. Bounded by the 500 ms the sequence gives them, so it
  /// is not idle decorative motion — it stops when the text arrives.
  static let typingDot = Animation.easeInOut(duration: 0.42)

  /// **§3's peek**: a source row opening to show its question.
  static let peek = Animation.smooth(duration: 0.24, extraBounce: 0)
  /// **§3's long-press to pull**, 350 ms. Shorter than `holdToFileDuration` on
  /// purpose: a pull costs shift-minutes, a call costs the case.
  static let sourceLongPress: TimeInterval = 0.35

  /// **§7's leads-to glow**: the ease either side of the pulse on an unpulled key
  /// source's left rule.
  static let worthALookGlow = Animation.easeInOut(duration: 0.30)
  /// How long the rule stays **at full glow** — §7's "one 600 ms glow", measured
  /// between the two eases rather than across them.
  static let worthALookHoldMs = 600
  /// How long the `worth a look` caption stays before it withdraws on its own.
  ///
  /// §7 asks for the *pulse* to be one 600 ms glow, and it is. The caption is a
  /// different question: the nudge fires when the pull's findings land, and the
  /// player is then inside the source sheet with the results — they reach the row it
  /// points at a beat or two later. A caption timed to the glow was measured gone
  /// before the sheet had even been dismissed, which makes it a nudge nobody
  /// receives. It also clears the moment the player touches any row, so it is
  /// answered rather than waited out.
  static let worthALookLifeMs = 4200

  /// A typed line's glyph cadence, when the caller has no duration to spread over.
  /// `Sequences.glyphMs` is the number; this is it as seconds, once.
  static let glyphSeconds: Double = Double(Sequences.glyphMs) / 1000.0

  /// The ECG's frame budget — 30 fps is plenty for a 40 pt-tall trace and it halves
  /// the wake-ups of `.animation`'s default.
  static let ecgFrameInterval: Double = 1.0 / 30.0

  /// The ECG's scroll period, in seconds, for a status's BPM. Read from
  /// `content.tuning.bpm` — never a literal (D7).
  static func ecgPeriod(bpm: Int) -> Double { 60.0 / Double(max(bpm, 1)) }

  /// The edge glow pulses at the beat cadence, and **only** at HUNT / LOCKDOWN.
  static func glowPulse(periodSeconds: Double) -> Animation {
    .easeInOut(duration: periodSeconds / 2).repeatForever(autoreverses: true)
  }

  /// **The one documented exception to the gate.** The pressed-state crossfade of
  /// `PressableStyle`, 80 ms.
  ///
  /// A pressed state is *direct manipulation*: the finger is on the glass and the
  /// pixel under it has to move now, or the tap that landed and the tap that missed
  /// look identical (risk R11). Reduce Motion is a vestibular setting about
  /// **travel** — a 2 % scale over 80 ms under the thumb is below the threshold it
  /// exists to protect, and removing it removes the only feedback a control has.
  ///
  /// It lives here, named, so `verify.sh`'s "every animation goes through
  /// `Motion.gated`" grep has exactly one allowance with its reason attached
  /// instead of an unexplained duration literal in `Components/`. Nothing else in
  /// the deck may use it: `PressableStyle` is the only call site, and it is the only
  /// place a press is drawn.
  static let pressUngated = Animation.easeOut(duration: 0.08)

  // ── the gate ───────────────────────────────────────────────────────────────

  /// `true` when the player has asked the system for less motion.
  ///
  /// **Divergence from the §4.6 sketch,** which read `@Environment(\.accessibility…)`
  /// from a `static` context — that cannot compile. `UIAccessibility` is the same
  /// value the environment key is derived from, and it is readable from anywhere,
  /// which is what makes the single-gate rule possible.
  static var isReduced: Bool { UIAccessibility.isReduceMotionEnabled }

  /// **The one gate.** Every animated view animates through this, so Reduce Motion
  /// is correct in exactly one place instead of thirty. `nil` means "apply the state
  /// change instantly", which is precisely what `withAnimation(nil)` and
  /// `.animation(nil, value:)` do.
  static func gated(_ animation: Animation) -> Animation? {
    isReduced ? nil : animation
  }

  /// The same gate, for a view that already holds the environment value — inside a
  /// `View.body` the environment is the more accurate source, because it updates the
  /// view when the setting changes mid-session.
  static func gated(_ animation: Animation, reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : animation
  }
}

extension View {

  /// `.animation(_:value:)` through the gate.
  func gatedAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
    self.animation(Motion.gated(animation), value: value)
  }

  /// The §4.2 phase transition: in from the trailing edge with a fade, out on the
  /// fade alone — so a completed debrief never appears to slide *back* into the call
  /// sheet it can no longer reach.
  var phaseTransition: some View {
    transition(
      .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .opacity))
  }
}
