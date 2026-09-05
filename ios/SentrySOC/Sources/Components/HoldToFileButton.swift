import SwiftUI

/// Hold to file — `DESIGN.md` §2.9; `SPEC.md` §5.7, §10 C7 #3.
///
/// The Papers-Please stamp, and the only control in the deck that asks for more than
/// a tap. 550 ms of contact, three ticks under the thumb at 0 / 180 / 360 ms, and a
/// conic ring that fills clockwise. Release early and **nothing happens** — not a
/// partial call, not a warning, not a penalty; the ring vanishes and the sheet is
/// exactly as it was. That is the contract that makes the hold safe enough to be
/// worth the ceremony.
///
/// **The ring is driven by a real clock.** `TimelineView(.animation)` reads a `Date`
/// delta against the moment of `pressStart`, so the ring never fights `withAnimation`
/// and never drifts when the main thread stutters mid-gesture. A `withAnimation`
/// ring would keep animating past a release, or land early after a dropped frame —
/// both of which file a call the player did not make.
///
/// Three escape hatches, because a 550 ms hold is not available to everyone:
/// * **Settings → Hold to file: off** switches to two-tap (`File ▸` → `Confirm`).
/// * **VoiceOver** cannot hold, so `.accessibilityAction(named:)` commits at once.
/// * **Reduce Motion** fills the ring in three discrete steps instead of sweeping.
///
/// One `MAKE_CALL` per case is guaranteed by the **reducer** (`phase ==
/// .investigating`), never by this view — a UI guard is a guard you can race.
struct HoldToFileButton: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// `copy.chrome.callHoldToFile` rendered, or `copy.chrome.callFile` in two-tap mode.
  let title: String
  /// `copy.chrome.callConfirm` — two-tap mode's second state.
  var confirmTitle: String?
  /// `copy.chrome.callFileAction` — the VoiceOver action name.
  let actionLabel: String
  var tone: Color = Theme.truePositive
  /// `settings.holdToFile`. `false` → two-tap.
  var holdEnabled: Bool = true
  /// Fired at each of `Motion.holdToFileTicks`, by index. The screen routes it to
  /// the `holdTick` cue; this view knows nothing about haptics.
  var onTick: (Int) -> Void = { _ in }
  let onFile: () -> Void

  @State private var pressStart: Date?
  @State private var hold = HoldProgress()
  @State private var armed = false

  var body: some View {
    Group {
      if holdEnabled {
        holdBody
      } else {
        twoTapBody
      }
    }
    .frame(maxWidth: .infinity, minHeight: Theme.Hit.holdToFile)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(armed ? (confirmTitle ?? title) : title)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { onFile() }
    .accessibilityAction(named: actionLabel) { onFile() }
    .accessibilityIdentifier("call.holdToFile")
  }

  // MARK: - Hold

  private var holdBody: some View {
    TimelineView(.animation(minimumInterval: Motion.ecgFrameInterval, paused: pressStart == nil)) {
      context in
      let elapsed = pressStart.map { context.date.timeIntervalSince($0) } ?? 0
      HoldFace(title: title, tone: tone, progress: progress(elapsed: elapsed))
        .onChange(of: context.date) { _, now in
          guard let start = pressStart else { return }
          advance(elapsed: now.timeIntervalSince(start))
        }
    }
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          if abs(value.translation.width) > Motion.holdToFileCancelSlop
            || abs(value.translation.height) > Motion.holdToFileCancelSlop {
            cancel()
          } else {
            begin()
          }
        }
        .onEnded { _ in cancel() })
  }

  // MARK: - Two-tap

  private var twoTapBody: some View {
    Button {
      if armed {
        armed = false
        onFile()
      } else {
        armed = true
        onTick(0)
      }
    } label: {
      HoldFace(
        title: armed ? (confirmTitle ?? title) : title, tone: tone, progress: armed ? 1 : 0)
    }
    .buttonStyle(PressableStyle(weight: .control, showsFill: false))
  }

  // MARK: - The clock

  private func progress(elapsed: TimeInterval) -> Double {
    guard pressStart != nil else { return 0 }
    return hold.fraction(elapsed: elapsed, reduceMotion: reduceMotion)
  }

  private func begin() {
    guard pressStart == nil else { return }
    pressStart = Date()
    for tick in hold.begin() { onTick(tick) }
  }

  /// Early release. **Zero state change** beyond forgetting the hold.
  private func cancel() {
    pressStart = nil
    hold.cancel()
  }

  private func advance(elapsed: TimeInterval) {
    guard pressStart != nil else { return }
    let step = hold.advance(elapsed: elapsed)
    for tick in step.ticks { onTick(tick) }
    if step.completed {
      cancel()
      onFile()
    }
  }
}

/// **One frame of the hold**, at a given fill — the ring, the title, the card that
/// warms as the ring closes.
///
/// Separated from `HoldToFileButton` for the same reason `ECGTrace` is separated
/// from `ECGCanvas`: a still frame of a gesture-driven control has to be *renderable*
/// — by a `#Preview`, by `ImageRenderer` in the snapshot suite — without a finger on
/// the glass. The alternative that shipped first was a `previewProgress` parameter on
/// the button itself, which is a test hook in a production API: a screen could set it,
/// pin the ring at a fraction, and the button would never fill from a real hold, with
/// no compile error to catch it. `HoldToFileButton`'s surface now has no such
/// parameter, and the two drawings cannot drift because there is only one.
struct HoldFace: View {
  /// Already rendered by the screen from `copy.chrome.callHoldToFile`.
  let title: String
  var tone: Color = Theme.truePositive
  /// 0…1. The ring's fill, and how warm the card underneath it reads.
  let progress: Double

  var body: some View {
    HStack(spacing: 14) {
      ring

      Text(title)
        .font(Typography.rowTitle)
        .foregroundStyle(tone)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.leading)

      Spacer(minLength: 8)
    }
    .padding(.horizontal, 18)
    .frame(maxWidth: .infinity, minHeight: Theme.Hit.holdToFile, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        .fill(tone.opacity(0.10 + 0.10 * clamped))
    }
    .overlay {
      RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        .strokeBorder(tone.opacity(0.45 + 0.40 * clamped), lineWidth: 1)
    }
  }

  private var clamped: Double { max(0, min(1, progress)) }

  private var ring: some View {
    ZStack {
      Circle()
        .strokeBorder(tone.opacity(0.25), lineWidth: 3)

      Circle()
        .trim(from: 0, to: clamped)
        .stroke(
          AngularGradient(
            colors: [tone.opacity(0.55), tone, tone],
            center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
          style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(-90))

      Text(clamped >= 1 ? Glyph.resolved : Glyph.partial)
        .font(Typography.meta)
        .foregroundStyle(tone.opacity(0.5 + 0.5 * clamped))
    }
    .frame(width: 30, height: 30)
  }
}

/// The pure half of the hold: how many ticks have fired, and whether 550 ms of
/// contact has elapsed. Extracted from the view so the contract §5.7 actually cares
/// about — *ticks at 0 / 180 / 360 ms, completion at 550 ms, and an early release
/// that changes nothing* — is unit-testable without a gesture recogniser, a
/// simulator or a wall clock.
struct HoldProgress: Equatable {
  /// How many of `Motion.holdToFileTicks` have been reported.
  private(set) var ticksFired = 0

  /// What one step of the clock produced.
  struct Step: Equatable {
    var ticks: [Int] = []
    var completed = false
  }

  /// The press landed. Returns the tick at 0 ms, which fires under the thumb rather
  /// than one frame later.
  mutating func begin() -> [Int] {
    guard ticksFired == 0 else { return [] }
    ticksFired = 1
    return [0]
  }

  /// Advance to `elapsed` seconds since the press. Reports every tick crossed since
  /// the last call — never one per frame, never one twice.
  mutating func advance(elapsed: TimeInterval) -> Step {
    var step = Step()
    guard ticksFired > 0 else { return step }
    while ticksFired < Motion.holdToFileTicks.count,
      elapsed >= Motion.holdToFileTicks[ticksFired] {
      step.ticks.append(ticksFired)
      ticksFired += 1
    }
    step.completed = elapsed >= Motion.holdToFileDuration
    return step
  }

  /// Early release: back to rest, and the caller fires nothing.
  mutating func cancel() {
    ticksFired = 0
  }

  /// The ring's fill. Under Reduce Motion it steps once per tick instead of
  /// sweeping — the same information, none of the travel (§10 C7 #3).
  func fraction(elapsed: TimeInterval, reduceMotion: Bool) -> Double {
    guard ticksFired > 0 else { return 0 }
    if reduceMotion {
      return Double(ticksFired) / Double(Motion.holdToFileTicks.count)
    }
    return min(1, max(0, elapsed / Motion.holdToFileDuration))
  }
}

#Preview("HoldToFileButton · rest, mid-hold, filed, two-tap") {
  VStack(spacing: 20) {
    HoldToFileButton(
      title: "Hold to file · Escalate → IR", actionLabel: "File this call",
      onFile: {})

    // Mid-flight and complete are frames of the gesture, so they are drawn as
    // frames — `HoldFace` — not by poking a fraction into the live control.
    HoldFace(title: "Hold to file · Escalate → IR", progress: 0.42)

    HoldFace(
      title: "Hold to file · Close · Benign (authorized)", tone: Theme.benign, progress: 1)

    HoldToFileButton(
      title: "File ▸", confirmTitle: "Confirm", actionLabel: "File this call",
      tone: Theme.falsePositive, holdEnabled: false, onFile: {})
  }
  .padding(24)
  .frame(width: 390)
  .background(Theme.ground)
}
