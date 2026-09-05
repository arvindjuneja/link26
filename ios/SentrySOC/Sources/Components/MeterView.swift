import SentryCore
import SwiftUI

/// A pressure meter — `DESIGN.md` §2.5, §2.10; `SPEC.md` §10 C7 #4.
///
/// The bar sweeps over 600 ms while the number counts with
/// `.contentTransition(.numericText(value:))` — the native odometer, not a manual
/// timer, so it is correct at any Dynamic Type size and free under Reduce Motion.
///
/// The two `fear` strings are `title=` tooltips on the web, which a phone can never
/// show. Here they are **visible 11 pt captions and** the VoiceOver hint (§5.3): the
/// meter says what it costs you, not what it computes.
struct MeterView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let label: String
  /// Already formatted by the screen — `30`, `30%`, `22 / 90 shift-min`.
  let valueText: String
  /// 0…1. The screen divides; the meter never does arithmetic on a metered value
  /// (D8 makes that a compile error outside `SentryCore` anyway).
  let fraction: Double
  let status: TraceStatus
  var fear: String?
  /// `"30 percent, ALERT"` — resolved by the screen, because it is copy.
  let spokenValue: String
  /// The value the odometer keys off. Defaults to the fraction, which is enough
  /// whenever the number and the bar move together.
  var numericKey: Double?

  var body: some View {
    let palette = Theme.status(status)

    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(label)
          .trackedLabel(Theme.textQuiet)
        Spacer(minLength: 12)
        Text(valueText)
          .font(Typography.metaStrong)
          .tabularNumbers()
          .foregroundStyle(palette.text)
          .contentTransition(.numericText(value: numericKey ?? fraction))
      }

      track(palette: palette)

      if let fear {
        Text(fear)
          .quietLog()
      }
    }
    .gatedAnimation(Motion.meterSweep, value: fraction)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
    .accessibilityValue(spokenValue)
    .accessibilityHint(fear ?? "")
  }

  private func track(palette: Theme.StatusPalette) -> some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule(style: .continuous)
          .fill(Theme.Zinc.z800.opacity(0.55))

        Capsule(style: .continuous)
          .fill(palette.bar)
          .frame(width: max(0, min(1, fraction)) * geometry.size.width)
          .shadow(
            color: palette.glow.opacity(palette.glowOpacity * 2),
            radius: 6, x: 0, y: 0)
      }
    }
    .frame(height: 4)
  }
}

#Preview("MeterView · the three meters across the ramp") {
  VStack(alignment: .leading, spacing: 22) {
    MeterView(
      label: "BREACH RISK", valueText: "0", fraction: 0, status: .calm,
      fear: "a real threat you closed is dwelling undetected",
      spokenValue: "0 percent, CALM")
    MeterView(
      label: "BREACH RISK", valueText: "30", fraction: 0.30, status: .alert,
      fear: "a real threat you closed is dwelling undetected",
      spokenValue: "30 percent, ALERT")
    MeterView(
      label: "NOISE / FATIGUE", valueText: "56", fraction: 0.56, status: .hunt,
      fear: "crying wolf — Tier-2 stops trusting your tickets",
      spokenValue: "56 percent, HUNT")
    MeterView(
      label: "BREACH RISK", valueText: "90", fraction: 0.90, status: .lockdown,
      fear: "a real threat you closed is dwelling undetected",
      spokenValue: "90 percent, LOCKDOWN")
    MeterView(
      label: "TIME", valueText: "22 / 90 shift-min", fraction: 22.0 / 90.0, status: .calm,
      fear: "a soft budget — surfaced, never scored",
      spokenValue: "22 of 90 shift-minutes")
  }
  .padding(24)
  .frame(width: 390)
  .background(Theme.ground)
}
