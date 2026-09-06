import SwiftUI
import SentryCore

/// **Vale, as a voice in your ear** — `FEEL.md` §1 and §6.
///
/// The three-paragraph coach panel is gone (§10). What replaces it is this: one
/// sentence, on a card that slides in from the left rail, with 500 ms of typing dots
/// in front of it so the line reads as *arriving* rather than as having always been
/// there. The dots are the whole difference between a coach and a colleague.
///
/// It draws four things and decides none of them: who is speaking, what they said,
/// whether the dots are still running, and — for the taxonomy card of shift 1 — an
/// optional block of tone-run prose under the line. `richBody` is how the DEF-A
/// paragraph keeps its cyan / emerald / rose verdict runs (D5) inside a card that is
/// otherwise one sentence.
struct MessageCard: View {

  /// `copy.chrome.coachEyebrow`, or the handler's own `from` — the screen resolves it.
  let sender: String
  /// The one line. Typed in after the dots.
  var line: String?
  /// The taxonomy paragraph, when this is the card that carries it.
  var richBody: [RichSegment] = []
  /// `1/3` on a coach step, `nil` on an interjection.
  var counter: String?
  /// Whether this card is still being written. The card owns its own 500 ms
  /// (`Sequences.typingDotsMs`) from the moment it appears: the sequence has a beat
  /// for the card *arriving* and none for the dots stopping, and binding the dots to
  /// the next beat instead made them run 800 ms — measured on the simulator at
  /// `docs/screenshots/ios/feel/handover`, where the line landed at 4062 ms against
  /// §1's 3620.
  var typingMs: Int = Sequences.typingDotsMs
  /// The step's own button (S4's `advance: "button"`), when it has one.
  var buttonTitle: String?
  /// `copy.chrome.coachSkip`, when the card is dismissible.
  var skipTitle: String?
  var tone: Color = Theme.benign
  var onButton: (() -> Void)?
  var onSkip: (() -> Void)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isTyping = true
  @State private var dots: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(Glyph.dot)
          .font(Typography.quietLog)
          .foregroundStyle(tone)

        Text(sender).trackedLabel(tone)

        Spacer(minLength: 8)

        if let counter {
          Text(counter)
            .font(Typography.meta)
            .tabularNumbers()
            .foregroundStyle(Theme.textDisabled)
        }
      }

      if isTyping {
        TypingDots(tone: tone)
          .transition(.opacity)
      } else {
        if let line {
          // The dots **are** the typing (§1 row 4, §6: "typing dots 500 ms → text").
          // Running a typewriter on the line as well pushed the sentence 400 ms past
          // the dock that is supposed to rise after it.
          Text(line)
            .font(Typography.body)
            .lineSpacing(Typography.bodyLineSpacing)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
        if !richBody.isEmpty {
          RichTextView(segments: richBody)
            .padding(.top, line == nil ? 0 : 4)
        }
      }

      if buttonTitle != nil || skipTitle != nil {
        HStack(spacing: 14) {
          if let buttonTitle, let onButton {
            Button(action: onButton) {
              Text(buttonTitle)
                .font(Typography.metaStrong)
                .foregroundStyle(tone)
                .padding(.horizontal, 12)
                .minimumHitTarget()
            }
            .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
            .overlay {
              RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(tone.opacity(0.40), lineWidth: 1)
                .allowsHitTesting(false)
            }
            .accessibilityIdentifier("coach.advance")
          }

          Spacer(minLength: 0)

          if let skipTitle, let onSkip {
            Button(action: onSkip) {
              Text(skipTitle)
                .font(Typography.meta)
                .foregroundStyle(Theme.textQuiet)
                .padding(.horizontal, 8)
                .minimumHitTarget()
            }
            .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
            .accessibilityIdentifier("coach.skip")
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.leading, 14 + Theme.ruleWidth)
    .padding(.trailing, 14)
    .padding(.vertical, 12)
    .panelCard()
    // The rail Vale speaks from (§6: "slides in from the left rail").
    .leadingRule(tone.opacity(0.75))
    .animation(Motion.gated(Motion.messageCard, reduceMotion: reduceMotion), value: isTyping)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("message.card")
    .onAppear(perform: startDots)
    // A coach step advancing reuses this view rather than replacing it, so `onAppear`
    // never fires again — and step 2 would arrive without ever having been written.
    .onChange(of: line) { _, _ in startDots() }
    .onDisappear { dots?.cancel() }
  }

  /// Hold the line back for its 500 ms, then let it through.
  ///
  /// Reduce Motion skips the wait entirely: the pause is a piece of theatre, and D18
  /// is about not performing at a player who asked you not to. The *sound* of the
  /// card arriving is not this view's, so nothing is lost from the other channel.
  private func startDots() {
    dots?.cancel()
    guard typingMs > 0, !reduceMotion else {
      isTyping = false
      return
    }
    isTyping = true
    dots = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(typingMs), tolerance: .zero)
      guard !Task.isCancelled else { return }
      withAnimation(Motion.gated(Motion.messageCard, reduceMotion: reduceMotion)) {
        isTyping = false
      }
    }
  }
}

/// The 500 ms before a line arrives.
///
/// Three dots on a staggered bob, and a **bounded** one: the card swaps them for its
/// text after `Sequences.typingDotsMs`, so this is on screen for half a second and
/// then gone. Under Reduce Motion it is never built at all — the card shows its line
/// on the first frame, because a pause whose only content is an animation is exactly
/// what D18 is about.
struct TypingDots: View {
  var tone: Color = Theme.benign

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var lift = false

  var body: some View {
    HStack(spacing: 5) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(tone.opacity(lift ? 0.85 : 0.35))
          .frame(width: 5, height: 5)
          .offset(y: lift ? -2 : 0)
          .animation(
            Motion.gated(
              Motion.typingDot.repeatForever(autoreverses: true).delay(Double(index) * 0.12),
              reduceMotion: reduceMotion),
            value: lift)
      }
    }
    .frame(height: Typography.bodyLineSpacing + 12, alignment: .leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear { lift = true }
    .accessibilityHidden(true)
  }
}

#Preview("MessageCard · Vale") {
  VStack(spacing: 12) {
    MessageCard(sender: "SHIFT LEAD · IN YOUR EAR", line: "…")
    MessageCard(
      sender: "SHIFT LEAD · IN YOUR EAR",
      line: "Good — now read what it says, not what the tool guessed.",
      counter: "1/3",
      typingMs: 0,
      buttonTitle: "Got it ▸",
      skipTitle: "skip coaching",
      onButton: {},
      onSkip: {})
  }
  .padding(20)
  .frame(width: 390)
  .background(Theme.ground)
}
