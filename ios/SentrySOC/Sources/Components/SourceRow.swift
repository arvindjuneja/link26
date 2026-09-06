import SwiftUI

/// A log you can pull — `DESIGN.md` §2.6, `SPEC.md` §5.4, rewritten to `FEEL.md` §3.
///
/// **What changed and why.** The row used to print its question at rest, and six of
/// them at once turned the screen into the lecture the founder saw: *"wszystko naraz,
/// zgaduj co czytać"*. §3's fix is not to delete the question — it is the teaching —
/// but to make the player **ask** for it:
///
/// - **At rest** the row is `name + cost`, mono, and nothing else.
/// - **Tap** = *peek*. The question unfolds with a `Pull · 10m` button under it. Only
///   one row peeks at a time (the screen enforces that, not this view), and peeking
///   is free — no shift-minutes, no action, no reducer.
/// - **Tap `Pull`, or long-press the row for 350 ms**, and the pull happens. No
///   confirm dialog: the cost was on the row before the finger landed.
/// - **A pulled row collapses to one dim line** with a `✓` and what it surfaced.
///
/// Row order is the authored order and rows never move (§3), so the player builds
/// spatial memory of a case: "the decode was third" stays true all shift.
///
/// The `nudge` caption is §7 — a mono `worth a look` under an unpulled key source,
/// once, after a decisive or supporting finding lands. It points without answering.
struct SourceRow: View {
  let label: String
  let question: String
  /// `10m` — formatted by the screen.
  let cost: String
  /// `Pull the log · 10m`, assembled by the screen from two chrome keys.
  var pullTitle: String = ""
  var isPulled: Bool = false
  /// `✓ 2 findings` once spent — the whole of a pulled row (§3).
  var pulledLabel: String?
  /// Whether this row is the one showing its question.
  var isPeeked: Bool = false
  /// §7's one-shot caption, present only while the nudge is glowing.
  var nudge: String?
  /// `copy.chrome.caseSourceSpoken` rendered.
  let spokenLabel: String
  /// `copy.chrome.caseSourceHint`.
  var spokenHint: String?
  /// Peek / un-peek. Free.
  let onTap: () -> Void
  /// The commit.
  let onPull: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Set by the long-press so the tap that ends the same gesture does not also toggle
  /// the peek behind the sheet that is already opening.
  @State private var longPressed = false

  var body: some View {
    Group {
      if isPulled { spent } else { live }
    }
    // **No `.accessibilityElement(children:)` here.** A `.ignore` on the group threw
    // away the labels its two branches carry and shipped a row VoiceOver reads as
    // nothing at all — caught by the Shift-1 replay, whose accessibility dump showed
    // two `case.source` elements with an empty label. Each branch owns its own
    // element: the resting row is one button, and a peeked row is two, which is
    // correct — the question and the commit are different things to touch.
    .accessibilityIdentifier("case.source")
  }

  // MARK: - Before the pull

  private var live: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        guard !longPressed else {
          longPressed = false
          return
        }
        onTap()
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
              .font(Typography.bodyMono)
              .foregroundStyle(Theme.textPrimary)
              .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            Text(cost)
              .font(Typography.meta)
              .tabularNumbers()
              .foregroundStyle(Theme.falsePositive)
              .layoutPriority(1)
          }
          // §7's caption belongs on the **row**, not inside the peek: the whole point
          // of the nudge is to be read by a player who has not opened this row yet.
          if let nudge, !isPeeked {
            Text(nudge)
              .font(Typography.quietLog)
              .foregroundStyle(Theme.falsePositive.opacity(0.85))
              .transition(.opacity)
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: Theme.Hit.row, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(PressableStyle(showsFill: false))
      // §3's second way in. 350 ms — long enough not to fire on a scroll, short
      // enough that a player who knows the case does not wait on the deck.
      .simultaneousGesture(
        LongPressGesture(minimumDuration: Motion.sourceLongPress)
          .onEnded { _ in
            longPressed = true
            onPull()
          })
      .accessibilityLabel(spokenLabel)
      .accessibilityHint(spokenHint ?? "")

      if isPeeked {
        peek
      }
    }
    .panelCard(fill: Theme.panel, stroke: strokeTone)
    .leadingRule(nudge == nil ? nil : Theme.falsePositive)
    .overlay(alignment: .leading) { nudgeGlow }
    .animation(Motion.gated(Motion.peek, reduceMotion: reduceMotion), value: isPeeked)
    .animation(Motion.gated(Motion.worthALookGlow, reduceMotion: reduceMotion), value: nudge)
  }

  /// The question, and the commit. Present only while this row is the peeked one.
  private var peek: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(question)
        .font(Typography.metaProse)
        .foregroundStyle(Theme.textQuiet)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onPull) {
        Text(pullTitle)
          .font(Typography.metaStrong)
          .foregroundStyle(Theme.falsePositive)
          .padding(.horizontal, 14)
          .frame(minHeight: Theme.Hit.minimum)
          .background {
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
              .fill(Theme.falsePositive.opacity(0.10))
          }
          .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
              .strokeBorder(Theme.falsePositive.opacity(0.45), lineWidth: 1)
          }
          .contentShape(Rectangle())
      }
      .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
      .accessibilityIdentifier("source.pull")

      if let nudge {
        Text(nudge)
          .font(Typography.quietLog)
          .foregroundStyle(Theme.falsePositive.opacity(0.85))
      }
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .transition(.opacity.combined(with: .move(edge: .top)))
  }

  /// §7's pulse: the row's left rule lights, and the caption rides under the name
  /// when the row is not peeked (when it is, the caption sits with the button).
  @ViewBuilder private var nudgeGlow: some View {
    if nudge != nil {
      RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        .fill(Theme.falsePositive.opacity(0.06))
        .allowsHitTesting(false)
    }
  }

  private var strokeTone: Color {
    if nudge != nil { return Theme.falsePositive.opacity(0.45) }
    return isPeeked ? Theme.falsePositive.opacity(0.30) : Theme.hairline
  }

  // MARK: - After the pull

  /// One dim line: a tick, the name, and what it surfaced (§3). Still a control — a
  /// spent source re-opens read-only, because the board is a record of what you
  /// looked at.
  private var spent: some View {
    Button(action: onPull) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(Glyph.correct)
          .font(Typography.meta)
          .foregroundStyle(Theme.benign.opacity(0.8))

        Text(label)
          .font(Typography.meta)
          .foregroundStyle(Theme.textQuiet)
          .lineLimit(1)
          .truncationMode(.tail)

        Spacer(minLength: 8)

        if let pulledLabel {
          Text(pulledLabel)
            .font(Typography.quietLog)
            .foregroundStyle(Theme.textDisabled)
            .layoutPriority(1)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, minHeight: Theme.Hit.minimum, alignment: .leading)
      .panelCard(fill: Theme.panel.opacity(0.4), stroke: Theme.hairline.opacity(0.5))
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      pulledLabel.map { "\(spokenLabel) \($0)" } ?? spokenLabel)
    .accessibilityAddTraits([.isButton, .isSelected])
  }
}

#Preview("SourceRow · rest, peek, spent") {
  VStack(spacing: 8) {
    SourceRow(
      label: "EDR — process tree & lineage",
      question: "what spawned this, and what did it do after?",
      cost: "10m",
      pullTitle: "Pull the log · 10m",
      spokenLabel: "EDR — process tree & lineage. Costs 10 shift-minutes.",
      spokenHint: "Pulls this log",
      onTap: {}, onPull: {})

    SourceRow(
      label: "Decode the command",
      question: "what does the encoded blob actually say?",
      cost: "10m",
      pullTitle: "Pull the log · 10m",
      isPeeked: true,
      nudge: "worth a look",
      spokenLabel: "Decode the command. Costs 10 shift-minutes.",
      onTap: {}, onPull: {})

    SourceRow(
      label: "Change tickets / asset register",
      question: "is there a change window that explains this?",
      cost: "6m",
      isPulled: true,
      pulledLabel: "✓ 2 findings",
      spokenLabel: "Change tickets. Pulled. 2 findings.",
      onTap: {}, onPull: {})
  }
  .padding(20)
  .frame(width: 390)
  .background(Theme.ground)
}
