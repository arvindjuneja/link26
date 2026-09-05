import SwiftUI

/// One figure from the 16:00 scoreline — `DESIGN.md` §2.11; `SPEC.md` §10 C7 #4.
///
/// 28 pt mono tabular over an 11 pt tracked label, counted up with
/// `.contentTransition(.numericText(value:))`. The tone is the judgement: `0 missed
/// threats` is emerald and `1 missed threat` is rose, and that is the whole point of
/// showing the number at all.
struct StatTile: View {
  let value: String
  let label: String
  var tone: Color = Theme.textPrimary
  /// What the odometer keys off — the raw count behind `value`.
  var numericKey: Double = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(value)
        .font(Typography.gradeNumeral)
        .tabularNumbers()
        .foregroundStyle(tone)
        .contentTransition(.numericText(value: numericKey))
        .lineLimit(1)
        .minimumScaleFactor(0.6)

      Text(label)
        .trackedLabel(Theme.textDisabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .panelCard()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
    .accessibilityValue(value)
  }
}

/// The four tiles of the shift summary, in the grid §5.9 asks for — and the
/// **one-column reflow above `.xxLarge`** that keeps a 28 pt numeral legible at
/// accessibility sizes without clamping it (§4.5, risk X11).
struct StatTileGrid: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  struct Item: Identifiable {
    let id: String
    let value: String
    let label: String
    var tone: Color = Theme.textPrimary
    var numericKey: Double = 0

    init(
      id: String, value: String, label: String, tone: Color = Theme.textPrimary,
      numericKey: Double = 0
    ) {
      self.id = id
      self.value = value
      self.label = label
      self.tone = tone
      self.numericKey = numericKey
    }
  }

  let items: [Item]

  private var columns: Int { dynamicTypeSize > .xxLarge ? 1 : 2 }

  var body: some View {
    let rows = stride(from: 0, to: items.count, by: columns).map { start in
      Array(items[start..<min(start + columns, items.count)])
    }

    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        GridRow {
          ForEach(row) { item in
            StatTile(
              value: item.value, label: item.label, tone: item.tone,
              numericKey: item.numericKey)
          }
          if row.count < columns {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
          }
        }
      }
    }
  }
}

#Preview("StatTile · the summary grid") {
  VStack(spacing: 18) {
    StatTileGrid(items: [
      .init(id: "acc", value: "100%", label: "Accuracy", tone: Theme.benign, numericKey: 1),
      .init(id: "calls", value: "7/7", label: "Calls", numericKey: 7),
      .init(id: "missed", value: "0", label: "Missed threats", tone: Theme.benign),
      .init(id: "false", value: "0", label: "False escalations", tone: Theme.benign),
    ])

    StatTileGrid(items: [
      .init(id: "acc", value: "86%", label: "Accuracy", tone: Theme.pressure, numericKey: 0.86),
      .init(id: "calls", value: "7/7", label: "Calls", numericKey: 7),
      .init(id: "missed", value: "1", label: "Missed threats", tone: Theme.truePositive, numericKey: 1),
      .init(id: "false", value: "1", label: "False escalations", tone: Theme.truePositive, numericKey: 1),
    ])
  }
  .padding(24)
  .frame(width: 390)
  .background(Theme.ground)
}
