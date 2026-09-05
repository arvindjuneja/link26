import SwiftUI

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

  /// The ECG's scroll period, in seconds, for a status's BPM. Read from
  /// `content.tuning.bpm` — never a literal (D7).
  static func ecgPeriod(bpm: Int) -> Double { 60.0 / Double(max(bpm, 1)) }

  /// The edge glow pulses at the beat cadence, and **only** at HUNT / LOCKDOWN.
  static func glowPulse(periodSeconds: Double) -> Animation {
    .easeInOut(duration: periodSeconds / 2).repeatForever(autoreverses: true)
  }

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
