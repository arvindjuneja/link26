import SwiftUI

/// The stamp — `DESIGN.md` §2.10, §2.14; `SPEC.md` §5.8.
///
/// The single most important 180 ms in the app: it lands at `scale 1.4 → 1` with a
/// −3° rotation, once per call, and it is the moment the shift stops being a form
/// and starts being a decision you made. Double-ruled, in the heaviest machine cut
/// (Plex SemiBold — R11), because it has to read as *pressed into the page* rather
/// than typed onto it.
///
/// Under Reduce Motion it is simply there, at rest, already stamped.
struct StampView: View {
  @State private var landed = false

  /// `dispositionMeta[chosen].label`, uppercased by the screen or by the tracking here.
  let text: String
  var tone: Color = Theme.truePositive
  /// `copy.chrome.debriefFiled` rendered — `"Filed: Escalate → IR + isolate host"`.
  let spokenLabel: String
  /// `false` on a read-only re-open (`VIEW_RESULT`), where the ceremony already
  /// happened and replaying it would be a lie about what just occurred.
  let animates: Bool

  /// The rest state is decided **at init**, not in `onAppear`: a stamp that starts
  /// invisible and is only made visible by a lifecycle callback flickers on a
  /// re-open and renders blank in any static rasterisation of the view. Reduce
  /// Motion lands it immediately for the same reason.
  init(
    text: String, tone: Color = Theme.truePositive, spokenLabel: String,
    animates: Bool = true
  ) {
    self.text = text
    self.tone = tone
    self.spokenLabel = spokenLabel
    self.animates = animates
    _landed = State(initialValue: !animates || Motion.isReduced)
  }

  var body: some View {
    Text(text)
      .font(Typography.stamp)
      .tracking(Typography.labelTracking * 0.6)
      .textCase(.uppercase)
      .foregroundStyle(tone)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 18)
      .padding(.vertical, 10)
      .background {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(tone.opacity(0.06))
      }
      .overlay {
        // Two rules, 3 pt apart — the ╔═╗ of the wireframe, which is what makes it
        // a stamp rather than a chip.
        ZStack {
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(tone.opacity(0.85), lineWidth: 1.5)
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(tone.opacity(0.55), lineWidth: 1)
            .padding(3)
        }
      }
      .rotationEffect(Motion.stampRotation)
      .scaleEffect(landed ? 1 : Motion.stampScaleFrom)
      .opacity(landed ? 1 : 0)
      .onAppear {
        guard animates, let animation = Motion.gated(Motion.stamp) else {
          landed = true
          return
        }
        withAnimation(animation) { landed = true }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(spokenLabel)
  }
}

#Preview("StampView · the four calls") {
  VStack(spacing: 34) {
    StampView(
      text: "Escalate → IR + isolate host", tone: Theme.truePositive,
      spokenLabel: "Filed: Escalate → IR + isolate host")
    StampView(
      text: "Escalate → Tier 2", tone: Theme.pressure,
      spokenLabel: "Filed: Escalate → Tier 2")
    StampView(
      text: "Close · False Positive", tone: Theme.falsePositive,
      spokenLabel: "Filed: Close · False Positive")
    StampView(
      text: "Close · Benign (authorized)", tone: Theme.benign,
      spokenLabel: "Filed: Close · Benign (authorized)")
  }
  .padding(30)
  .frame(width: 390)
  .background(Theme.ground)
}
