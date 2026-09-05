import SwiftUI

/// The panel every sheet is painted on — `DESIGN.md` §2.5, §2.7, §2.9; `SPEC.md` §4.2.
///
/// `PhaseHost` presents sheets with `.presentationBackground(.clear)` so the ground
/// and the edge glow read through; this is the hand-painted panel that replaces the
/// system material. It owns the 16 pt radius, the hairline, the tracked eyebrow row
/// and the optional pinned footer, so no screen re-invents sheet chrome and none of
/// them drift apart.
///
/// The grabber is the system's (`.presentationDragIndicator(.visible)`), which is why
/// swipe-to-dismiss needs no code here.
struct SheetChrome<Content: View, Footer: View>: View {
  let eyebrow: String
  /// The trailing read-out on the eyebrow line — the shift clock on the board, the
  /// spend on a source.
  var trailing: String?
  var tone: Color = Theme.falsePositive
  /// `false` for a sheet whose content scrolls itself.
  var scrolls: Bool = true

  @ViewBuilder var content: Content
  @ViewBuilder var footer: Footer

  var body: some View {
    VStack(spacing: 0) {
      header

      if scrolls {
        ScrollView { body_ }
          .scrollBounceBehavior(.basedOnSize)
      } else {
        body_
        // The flexible element in the scrolling form is the ScrollView; without a
        // spacer here a short sheet would float its CTA mid-panel instead of
        // pinning it to the bottom edge where the thumb is.
        Spacer(minLength: 0)
      }

      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background {
      // The scrim carries the ground through at 85 % (§2.16) — the case underneath
      // stays visible, which is the whole reason a sheet was chosen over a push.
      Theme.scrim.opacity(0.85)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
    }
  }

  private var body_: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 14)
      .padding(.bottom, 20)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(eyebrow)
        .trackedLabel(tone)

      Spacer(minLength: 8)

      if let trailing {
        Text(trailing)
          .font(Typography.meta)
          .tabularNumbers()
          .foregroundStyle(Theme.textQuiet)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 12)
    .accessibilityElement(children: .combine)
  }
}

extension SheetChrome where Footer == EmptyView {
  init(
    eyebrow: String, trailing: String? = nil, tone: Color = Theme.falsePositive,
    scrolls: Bool = true, @ViewBuilder content: () -> Content
  ) {
    self.init(
      eyebrow: eyebrow, trailing: trailing, tone: tone, scrolls: scrolls,
      content: content, footer: { EmptyView() })
  }
}

#Preview("SheetChrome · board") {
  SheetChrome(eyebrow: "Alert queue · Shift 1", trailing: "22m") {
    VStack(alignment: .leading, spacing: 12) {
      Text("SHIFT PRESSURE").trackedLabel()
      MeterView(
        label: "BREACH RISK", valueText: "30", fraction: 0.30, status: .alert,
        fear: "a real threat you closed is dwelling undetected",
        spokenValue: "30 percent, ALERT")
      MeterView(
        label: "NOISE / FATIGUE", valueText: "0", fraction: 0, status: .calm,
        fear: "crying wolf — Tier-2 stops trusting your tickets",
        spokenValue: "0 percent, CALM")
    }
  } footer: {
    Dock(title: "Open alert 3", tone: Theme.falsePositive, action: {})
  }
  .frame(width: 390, height: 420)
  .background(Theme.ground)
}
