import SwiftUI

/// The shift lead in your ear — `DESIGN.md` §2.6; `SPEC.md` §5.4.
///
/// It docks **above** the Dock as the second of two stacked
/// `.safeAreaInset(edge: .bottom)`s, which is why it can never again overlap the
/// alert header (`PLAYTEST-lookandfeel.md` P2 — fixed by construction, not by a
/// z-index). It is present on the first alert of the first shift only, and it can
/// always be dismissed: coaching that cannot be switched off is a tutorial, and this
/// is a job.
struct CoachBubble: View {
  /// `copy.chrome.coachEyebrow` — "Shift lead · in your ear".
  let eyebrow: String
  /// `copy.chrome.coachStepCount` rendered — `1/3`.
  var counter: String?
  let title: String
  let body_: String
  /// The step's own button, when it advances on a button (S4).
  var buttonTitle: String?
  /// `copy.chrome.coachSkip`.
  let skipTitle: String
  var onButton: (() -> Void)?
  let onSkip: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(Glyph.dot)
          .font(Typography.quietLog)
          .foregroundStyle(Theme.benign)

        Text(eyebrow)
          .trackedLabel(Theme.benign)

        Spacer(minLength: 8)

        if let counter {
          Text(counter)
            .font(Typography.meta)
            .tabularNumbers()
            .foregroundStyle(Theme.textDisabled)
        }
      }

      Text(title)
        .font(Typography.rowTitle)
        .foregroundStyle(Theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text(body_)
        .prose(Theme.textTertiary)

      // The 44 pt targets below already carry ~14 pt of air above their text, so the
      // stack's own 8 pt would read as a hole under a step that has no button.
      HStack(spacing: 14) {
        if let buttonTitle, let onButton {
          Button(action: onButton) {
            Text(buttonTitle)
              .font(Typography.metaStrong)
              .foregroundStyle(Theme.benign)
              .padding(.horizontal, 12)
              .minimumHitTarget()
          }
          .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
          .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
              .strokeBorder(Theme.benign.opacity(0.40), lineWidth: 1)
              .allowsHitTesting(false)
          }
          .accessibilityIdentifier("coach.advance")
        }

        Spacer(minLength: 0)

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
      .padding(.top, -6)
      .padding(.bottom, -6)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .panelCard()
    .leadingRule(Theme.benign.opacity(0.55))
    .padding(.horizontal, 20)
    .accessibilityElement(children: .contain)
  }
}

#Preview("CoachBubble · the three steps") {
  VStack(spacing: 18) {
    CoachBubble(
      eyebrow: "Shift lead · in your ear", counter: "1/3",
      title: "Pull the log that answers the question",
      body_:
        "Each source shows the question it answers — start with the process tree. Tap it.",
      skipTitle: "skip coaching", onSkip: {})

    CoachBubble(
      eyebrow: "Shift lead · in your ear", counter: "2/3",
      title: "Read the finding, not the label",
      body_:
        "Findings land here — the evidence, not the tool's 'High' guess. Not sure yet? Pull more logs from SOURCES. When you can justify a call, hit Got it.",
      buttonTitle: "Got it", skipTitle: "skip coaching", onButton: {}, onSkip: {})
  }
  .padding(.vertical, 24)
  .frame(width: 390)
  .background(Theme.ground)
}
