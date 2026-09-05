import SwiftUI

/// A shift on the desk — `DESIGN.md` §2.3; `SPEC.md` §5.1.
///
/// 64 pt, the whole row tappable, and a **visible reason** on a locked row
/// (`⬡ LOCKED · opens at ⬢ 120`) rather than a tooltip. A phone has no hover, so a
/// `title=` is an explanation the player can never reach — and a locked row with no
/// stated price is just a wall.
///
/// A locked row stays **tappable on purpose**: §5.1 asks for the `denied` cue once
/// per hub visit, and a `.disabled(true)` `Button` never fires its action, so the
/// lock is expressed as tone, the reason line and an accessibility hint while the
/// screen decides what a tap means. Documented divergence from §5.1's literal
/// `.disabled(true)`.
struct QueueRow: View {

  enum State {
    /// Played and passed. Replayable.
    case cleared
    /// Open, unplayed — the one with the emerald rule.
    case open
    /// Standing not yet earned.
    case locked
    /// Today's board.
    case daily
    /// Today's board, already played.
    case dailyDone
  }

  let title: String
  /// `7 alerts` — formatted by the screen.
  let count: String
  /// `cleared · replay` / `open` / `⬡ LOCKED · opens at ⬢ 120` / `a fresh board every day`.
  let statusLine: String
  /// `Start ▸`. `nil` on a locked or finished row, where there is nothing to start.
  var cta: String?
  let state: State
  /// What VoiceOver adds after the label on a locked row.
  var spokenHint: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(Typography.rowTitle)
            .foregroundStyle(titleColor)
            .fixedSize(horizontal: false, vertical: true)

          Text(statusLine)
            .font(Typography.meta)
            .foregroundStyle(statusColor)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 10)

        VStack(alignment: .trailing, spacing: 4) {
          Text(count)
            .font(Typography.meta)
            .tabularNumbers()
            .foregroundStyle(Theme.textQuiet)

          if let cta {
            Text(cta)
              .font(Typography.meta)
              .foregroundStyle(rule ?? Theme.textTertiary)
          }
        }
        .layoutPriority(1)
      }
      .padding(.leading, rule == nil ? 14 : 14 + Theme.ruleWidth)
      .padding(.trailing, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .panelCard(
        fill: state == .locked ? .clear : Theme.panel,
        stroke: state == .locked ? Theme.Zinc.z700.opacity(0.7) : Theme.hairline,
        dashed: state == .locked)
      .leadingRule(rule)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
    .accessibilityElement(children: .combine)
    .accessibilityHint(spokenHint ?? "")
    .accessibilityIdentifier("hub.queueRow")
  }

  private var rule: Color? {
    switch state {
    case .open: Theme.benign
    case .daily: Theme.falsePositive
    case .cleared, .locked, .dailyDone: nil
    }
  }

  private var titleColor: Color {
    switch state {
    case .locked: Theme.textDisabled
    case .cleared, .dailyDone: Theme.textTertiary
    case .open, .daily: Theme.textPrimary
    }
  }

  private var statusColor: Color {
    switch state {
    case .locked: Theme.textDisabled
    case .open: Theme.benign
    case .daily: Theme.falsePositive
    case .cleared, .dailyDone: Theme.textQuiet
    }
  }
}

#Preview("QueueRow · the whole ladder") {
  VStack(spacing: 8) {
    QueueRow(
      title: "Shift 1 · fundamentals", count: "7 alerts", statusLine: "cleared · replay",
      cta: "Start ▸", state: .cleared, action: {})
    QueueRow(
      title: "Shift 2 · phishing · identity", count: "8 alerts", statusLine: "open",
      cta: "Start ▸", state: .open, action: {})
    QueueRow(
      title: "Shift 3 · the lockout queue", count: "3 alerts",
      statusLine: "⬡ LOCKED · opens at ⬢ 80", state: .locked,
      spokenHint: "Locked. Opens at 80 standing.", action: {})
    QueueRow(
      title: "Shift 4 · the other chair", count: "3 alerts",
      statusLine: "⬡ LOCKED · opens at ⬢ 120", state: .locked,
      spokenHint: "Locked. Opens at 120 standing.", action: {})
    QueueRow(
      title: "Daily shift · Fri 05 Sep", count: "5 alerts",
      statusLine: "a fresh board every day", cta: "Start ▸", state: .daily, action: {})
    QueueRow(
      title: "Daily shift · Fri 05 Sep", count: "5 alerts", statusLine: "done today ✓",
      state: .dailyDone, action: {})
  }
  .padding(20)
  .frame(width: 390)
  .background(Theme.ground)
}
