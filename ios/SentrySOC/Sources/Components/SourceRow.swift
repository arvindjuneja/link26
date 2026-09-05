import SwiftUI

/// A log you can pull — `DESIGN.md` §2.6; `SPEC.md` §5.4.
///
/// 72 pt, and the **question is never truncated**. That is the teaching: the row is
/// not "EDR logs, 10 minutes", it is "*what spawned this, and what did it do after?*"
/// — the analyst picks a source because of the question it answers, and a clipped
/// question turns the screen back into a menu of tools.
///
/// A pulled source stays listed and inert (§2.7): the board is a record of what you
/// looked at, so removing spent rows would erase the shape of the investigation.
struct SourceRow: View {
  let label: String
  let question: String
  /// `10m` — formatted by the screen.
  let cost: String
  var isPulled: Bool = false
  /// `copy.chrome.caseSourcePulled` — shown in place of the cost once spent.
  var pulledLabel: String?
  /// `copy.chrome.caseSourceSpoken` rendered: "EDR — process tree & lineage.
  /// Answers: what spawned this…. Costs 10 shift-minutes."
  let spokenLabel: String
  /// `copy.chrome.caseSourceHint`.
  var spokenHint: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(label)
            .font(Typography.bodyMono)
            .foregroundStyle(isPulled ? Theme.textQuiet : Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

          // §2.6 asks for "13 pt Grotesk **italic**". No italic cut of Space Grotesk
          // is registered (the roster is Regular / Medium / Bold — `FONTS.md`) and
          // `.italic()` on a face without one is a silent no-op, so the distinction
          // is carried where it actually reads: the **voice** changes. The label is
          // the machine naming a log; the question is a person asking something.
          Text(question)
            .font(Typography.metaProse)
            .foregroundStyle(isPulled ? Theme.textDisabled : Theme.textQuiet)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 10)

        Text(isPulled ? (pulledLabel ?? cost) : cost)
          .font(Typography.meta)
          .tabularNumbers()
          .foregroundStyle(isPulled ? Theme.textDisabled : Theme.falsePositive)
          .layoutPriority(1)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
      .panelCard(
        fill: isPulled ? Theme.panel.opacity(0.5) : Theme.panel,
        stroke: isPulled ? Theme.hairline.opacity(0.5) : Theme.hairline)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
    .disabled(isPulled)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spokenLabel)
    .accessibilityHint(spokenHint ?? "")
    .accessibilityAddTraits(isPulled ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("case.source")
  }
}

#Preview("SourceRow · fresh and spent") {
  VStack(spacing: 8) {
    SourceRow(
      label: "EDR — process tree & lineage",
      question: "what spawned this, and what did it do after?",
      cost: "10m",
      spokenLabel:
        "EDR — process tree & lineage. Answers: what spawned this, and what did it do after? Costs 10 shift-minutes.",
      spokenHint: "Pulls this log",
      action: {})

    SourceRow(
      label: "Decode the command",
      question: "what does the encoded blob actually say?",
      cost: "10m",
      isPulled: true,
      pulledLabel: "pulled",
      spokenLabel:
        "Decode the command. Answers: what does the encoded blob actually say? Costs 10 shift-minutes.",
      action: {})

    SourceRow(
      label: "Mail gateway — sender reputation & headers",
      question:
        "who really sent this, and has the domain ever been seen before today?",
      cost: "8m",
      spokenLabel: "Mail gateway. Answers: who really sent this? Costs 8 shift-minutes.",
      spokenHint: "Pulls this log",
      action: {})
  }
  .padding(20)
  .frame(width: 390)
  .background(Theme.ground)
}
