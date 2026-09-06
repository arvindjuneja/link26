import SwiftUI
import SentryCore

/// **A line that types itself in** — `FEEL.md` §1 (the handover eyebrow, one glyph
/// per 18 ms), §2 (the trigger line, ~700 ms), §5 (a fear caption, on the first
/// delta).
///
/// Two things make it a component rather than three `Task`s in three screens:
///
/// 1. **The frame never moves.** The full string is drawn at zero opacity and the
///    prefix is overlaid on it, so a two-line trigger reserves both lines on the
///    first frame and the rows under it do not jump as the second line fills. A
///    naïve `Text(prefix)` re-lays-out the whole column on every glyph, which is the
///    single most expensive way to draw a cheap effect.
/// 2. **One Reduce-Motion answer.** Less motion means the finished line, on frame
///    one — the *content* is never withheld, only the animation of its arrival.
///
/// Typing is the deck's one deliberately literal effect: this is a log console, and
/// a log console fills a line at a time. It is bounded (it stops), it is skippable
/// (`isActive` back to `false` finishes it), and it never loops — so it stays inside
/// §2.14's "no idle decorative motion" budget.
struct TypedText: View {

  /// The whole line. Never truncated — what is shown is a prefix of it.
  let text: String
  /// Hold the line back until the sequence says so. Flipping it to `true` starts the
  /// typing; flipping it to `false` while typing finishes the line at once, because a
  /// beat that has been superseded should not keep tapping.
  var isActive = true
  /// Spread the whole line over this many seconds. `nil` types at `Sequences.glyphMs`
  /// — §1's 18 ms per glyph, which is the cadence the document specifies where it
  /// specifies one at all.
  var duration: Double?

  var font: Font = Typography.quietLog
  var color: Color = Theme.textQuiet
  var lineSpacing: CGFloat = 0
  /// Letter-spacing, for the tracked 11 pt eyebrow of §1. It has to be a parameter
  /// rather than a `.tracking()` on the result: `tracking` is a `Text` modifier and
  /// this is a `View`, and the invisible sizer and the visible prefix must be tracked
  /// identically or the frame the sizer reserves is the wrong width.
  var tracking: CGFloat = 0
  /// Where the line sits in the width it is given. Leading everywhere in the deck;
  /// the parameter exists because the handover's clock reads right.
  var alignment: HorizontalAlignment = .leading

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = 0
  @State private var typing: Task<Void, Never>?

  var body: some View {
    let visible = String(text.prefix(shown))

    Text(text)
      .font(font)
      .tracking(tracking)
      .lineSpacing(lineSpacing)
      .foregroundStyle(.clear)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: frameAlignment)
      .overlay(alignment: overlayAlignment) {
        Text(visible)
          .font(font)
          .tracking(tracking)
          .lineSpacing(lineSpacing)
          .foregroundStyle(color)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: frameAlignment)
      }
      .accessibilityElement(children: .ignore)
      // VoiceOver reads the finished line, always. A screen reader has no use for a
      // performance, and a half-typed sentence read aloud is a bug.
      .accessibilityLabel(text)
      .onAppear { restart() }
      .onChange(of: isActive) { _, _ in restart() }
      .onChange(of: text) { _, _ in restart() }
      .onDisappear { typing?.cancel() }
  }

  private var frameAlignment: Alignment {
    alignment == .trailing ? .trailing : (alignment == .center ? .center : .leading)
  }

  private var overlayAlignment: Alignment {
    switch frameAlignment {
    case .trailing: .topTrailing
    case .center: .top
    default: .topLeading
    }
  }

  /// Start (or finish) the line. Idempotent — the only state is `shown`, and the task
  /// is replaced rather than raced.
  private func restart() {
    typing?.cancel()
    let count = text.count

    guard isActive else {
      shown = 0
      return
    }
    guard !reduceMotion, count > 0 else {
      shown = count
      return
    }

    shown = 0
    let step = Duration.milliseconds(
      max(1, Int(((duration.map { $0 * 1000 } ?? Double(count * Sequences.glyphMs)) / Double(count)).rounded())))
    typing = Task { @MainActor in
      // Absolute deadlines, like every other clock in the feel pass: a relative sleep
      // per glyph drifts, and a 46-character trigger line drifting 5 % is 35 ms of
      // lateness handed to the beat that follows it.
      let start = ContinuousClock.now
      for index in 1...count {
        let due = start.advanced(by: step * index)
        if ContinuousClock.now < due {
          try? await Task.sleep(until: due, tolerance: .zero, clock: ContinuousClock())
        }
        guard !Task.isCancelled else { return }
        shown = index
      }
    }
  }
}

#Preview("TypedText · a trigger line") {
  VStack(alignment: .leading, spacing: 16) {
    TypedText(
      text: "powershell.exe spawned with -EncodedCommand on FIN-WS-04 at 02:14 local — off-hours.",
      duration: 0.7,
      font: Typography.meta,
      color: Theme.textSecondary)
    TypedText(text: "SHIFT HANDOVER · 08:00", color: Theme.falsePositive)
  }
  .padding(20)
  .frame(width: 390)
  .background(Theme.ground)
}
