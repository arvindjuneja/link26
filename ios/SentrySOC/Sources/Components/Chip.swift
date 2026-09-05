import SwiftUI

/// A small tone-tagged label — the severity chip (§2.6), the truth chip (§2.10), the
/// MITRE id (§2.10), an unlock chip (§2.11).
///
/// A chip is a **claim about a value**, never decoration: it exists so a reader can
/// tell at a glance whether the thing it labels is the tool's guess (`HIGH · as
/// flagged`, orange because §5's `severityMeta.High.tone` is orange — R2) or the
/// ground truth (`True Positive`, rose). Same shape, opposite authority, and the
/// hue is the only thing that says which.
struct Chip: View {

  enum Style {
    /// Outline on the ground — the tool's own label.
    case outline
    /// Tinted fill — a decided value.
    case filled
    /// Text only with a tracked cap — inside a card that already has a border.
    case bare
  }

  let text: String
  var tone: Color = Theme.falsePositive
  var style: Style = .outline
  /// `true` renders 11 pt tracked caps; `false` renders 13 pt mono as authored.
  var tracked: Bool = true

  var body: some View {
    label
      .padding(.horizontal, style == .bare ? 0 : 8)
      .padding(.vertical, style == .bare ? 0 : 4)
      .background {
        if style == .filled {
          RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            .fill(tone.opacity(0.12))
        }
      }
      .overlay {
        if style != .bare {
          RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            .strokeBorder(tone.opacity(style == .filled ? 0.30 : 0.45), lineWidth: 1)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder private var label: some View {
    if tracked {
      Text(text).trackedLabel(tone)
    } else {
      Text(text)
        .font(Typography.meta)
        .foregroundStyle(tone)
        .lineLimit(1)
    }
  }
}

#Preview("Chip · every tone, every style") {
  let tones: [(String, Color)] = [
    ("CRITICAL", Theme.truePositive),
    ("HIGH · as flagged", Theme.Orange.c300),
    ("MEDIUM", Theme.Amber.c300),
    ("LOW", Theme.textQuiet),
    ("True Positive", Theme.truePositive),
    ("False Positive", Theme.falsePositive),
    ("Benign True Positive", Theme.benign),
    ("↔ red-team run", Theme.crossover),
  ]

  return VStack(alignment: .leading, spacing: 14) {
    ForEach(Array(tones.enumerated()), id: \.offset) { _, entry in
      HStack(spacing: 10) {
        Chip(text: entry.0, tone: entry.1, style: .outline)
        Chip(text: entry.0, tone: entry.1, style: .filled)
        Spacer(minLength: 0)
      }
    }
    HStack(spacing: 10) {
      Chip(text: "T1059.001 · PowerShell", tone: Theme.textTertiary, style: .filled, tracked: false)
      Spacer(minLength: 0)
    }
  }
  .padding(24)
  .frame(width: 390)
  .background(Theme.ground)
}
