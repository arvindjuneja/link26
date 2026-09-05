import SwiftUI

/// SOURCES / EVIDENCE — `DESIGN.md` §2.6, §2.8; `SPEC.md` §5.4.
///
/// Hand-built rather than a `.segmented` `Picker`, for one concrete reason: the
/// badges are live (`SOURCES 3/6`, `EVIDENCE 3`) and a segmented `Picker` cannot
/// carry a second value per segment. The badge is the whole point — it is how the
/// player knows there is something on the board worth switching to.
///
/// 44 pt, both halves, with a real pressed state.
struct SegmentedTabs<Tab: Hashable>: View {

  struct Item: Identifiable {
    let id: Tab
    let title: String
    /// `3/6` or `3`. `nil` renders the title alone.
    var badge: String?

    init(id: Tab, title: String, badge: String? = nil) {
      self.id = id
      self.title = title
      self.badge = badge
    }
  }

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let items: [Item]
  @Binding var selection: Tab
  var tone: Color = Theme.falsePositive

  /// **Wrap rather than clip** (P1-9). `SOURCES 3/6` and `EVIDENCE 3` are each wider
  /// than half a 320 pt track at the §4.5 ceiling, and the track was clipped to its
  /// own radius — so what a player at `.accessibility1` saw was a tab label cut off
  /// mid-word by a rounded corner, which reads as a rendering fault rather than as
  /// text that did not fit. Below the ceiling the two halves are side by side, as
  /// §2.6 draws them; at accessibility sizes the same two rows stack, keep their
  /// hairline, and every letter survives. Scaling further is not the answer: 0.7 of
  /// an 11 pt tracked label is already the floor of legible.
  private var wraps: Bool { dynamicTypeSize >= .accessibility1 }

  var body: some View {
    Group {
      if wraps {
        VStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 {
              Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 6)
            }
            segment(item)
          }
        }
      } else {
        HStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 {
              Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1)
                .padding(.vertical, 6)
            }
            segment(item)
          }
        }
      }
    }
    .frame(minHeight: Theme.Hit.minimum)
    .panelCard(fill: Theme.panel.opacity(0.7))
    .accessibilityElement(children: .contain)
  }

  private func segment(_ item: Item) -> some View {
    let isSelected = item.id == selection

    return Button {
      selection = item.id
    } label: {
      HStack(spacing: 8) {
        if isSelected {
          Text(Glyph.dot)
            .font(Typography.quietLog)
            .foregroundStyle(tone)
        }

        // A tab label is a word the player navigates by, so it shrinks rather than
        // ellipsises — `SOURCES` and `EVIDENCE` are both wider than half a 320 pt
        // track once Dynamic Type is at the §4.5 ceiling.
        Text(item.title)
          .trackedLabel(isSelected ? tone : Theme.textQuiet, scale: 0.7)

        if let badge = item.badge {
          Text(badge)
            .font(Typography.meta)
            .tabularNumbers()
            .foregroundStyle(isSelected ? tone : Theme.textDisabled)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: Theme.Hit.minimum)
      .background {
        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
          .fill(tone.opacity(isSelected ? 0.08 : 0))
          .padding(4)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle(weight: .control, showsFill: false))
    .accessibilityLabel(item.title)
    .accessibilityValue(item.badge ?? "")
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }
}

#Preview("SegmentedTabs · both halves selected") {
  struct Harness: View {
    @State private var sources = 0
    @State private var evidence = 1

    var body: some View {
      VStack(spacing: 18) {
        SegmentedTabs(
          items: [
            .init(id: 0, title: "SOURCES", badge: "0/6"),
            .init(id: 1, title: "EVIDENCE", badge: "0"),
          ], selection: $sources)

        SegmentedTabs(
          items: [
            .init(id: 0, title: "SOURCES", badge: "3/6"),
            .init(id: 1, title: "EVIDENCE", badge: "3"),
          ], selection: $evidence)
      }
      .padding(20)
      .frame(width: 390)
      .background(Theme.ground)
    }
  }
  return Harness()
}
