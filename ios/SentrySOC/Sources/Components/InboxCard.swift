import SwiftUI

/// Vale in your inbox — `DESIGN.md` §2.3, §2.12.
///
/// The handler is the only voice in the game that speaks to *you* rather than about
/// the alert, so the card carries a tone dot rather than a severity: warm, warn, tip
/// or milestone. The body clamps to two lines and **expands in place** on tap —
/// there is no message screen, because a shift lead does not need a mail client.
struct InboxCard: View {
  @State private var expanded = false

  /// `VALE · YOUR SHIFT LEAD`. Composed by the screen from `handler.senders`, not
  /// here: the separator between a name and a role is copy, and copy is exported.
  let eyebrow: String
  let subject: String
  let body_: String
  var tone: Color = Theme.benign
  /// `1/3` — position in the inbox, when there is more than one.
  var counter: String?
  /// What VoiceOver reads for the whole card — the card is one element, because
  /// four separate ones make the hub a maze to swipe through.
  let spokenLabel: String

  var body: some View {
    Button {
      withAnimation(Motion.gated(Motion.screenPush)) { expanded.toggle() }
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Text(Glyph.dot)
            .font(Typography.quietLog)
            .foregroundStyle(tone)

          Text(eyebrow)
            .trackedLabel(tone)

          Spacer(minLength: 8)

          if let counter {
            Text(counter)
              .font(Typography.meta)
              .tabularNumbers()
              .foregroundStyle(Theme.textDisabled)
          }
        }

        Text(subject)
          .font(Typography.rowTitle)
          .foregroundStyle(Theme.textPrimary)
          .fixedSize(horizontal: false, vertical: true)

        Text(body_)
          .prose(Theme.textTertiary)
          .lineLimit(expanded ? nil : 2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .panelCard()
      .leadingRule(tone.opacity(0.55))
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spokenLabel)
    .accessibilityIdentifier("hub.inbox")
  }
}

#Preview("InboxCard · the four tones") {
  VStack(spacing: 10) {
    InboxCard(
      eyebrow: "VALE · YOUR SHIFT LEAD", subject: "Clean shift — nice work",
      body_:
        "Sharp reads all the way through. +40 standing. Keep them clean and you're 70 off Senior Analyst.",
      tone: Theme.benign, counter: "1/3",
      spokenLabel: "Vale, your shift lead. Clean shift — nice work.")

    InboxCard(
      eyebrow: "VALE · YOUR SHIFT LEAD", subject: "Something dwelt",
      body_:
        "A real one got closed and sat there. Re-read that debrief — the misses are where the learning is.",
      tone: Theme.truePositive, counter: "2/3",
      spokenLabel: "Vale, your shift lead. Something dwelt.")

    InboxCard(
      eyebrow: "VALE · YOUR SHIFT LEAD", subject: "Kit is worth the cash",
      body_: "You've got ¢650 sitting idle. The kit shaves shift-minutes off every pull.",
      tone: Theme.falsePositive, counter: "3/3",
      spokenLabel: "Vale, your shift lead. Kit is worth the cash.")

    InboxCard(
      eyebrow: "VALE · YOUR SHIFT LEAD", subject: "That's Tier-1 Analyst",
      body_:
        "I flagged you to the lead. This is the ladder, and you're climbing it the right way — by being right.",
      tone: Theme.crossover,
      spokenLabel: "Vale, your shift lead. That's Tier-1 Analyst.")
  }
  .padding(20)
  .frame(width: 390)
  .background(Theme.ground)
}
