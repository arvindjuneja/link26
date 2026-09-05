import SwiftUI

/// The promotion — `DESIGN.md` §2.12; `SPEC.md` §5.10.
///
/// A 140 pt hexagon whose stroke draws itself over 900 ms, then fills to 10 %. The
/// hexagon is the `⬢` the whole economy is denominated in, at the one size where it
/// stops being a glyph and becomes a badge — this is the single cinematic beat in a
/// game that otherwise refuses decorative motion, and it is spent once per rank.
///
/// `Path.trim` is the native `stroke-dashoffset`. Under Reduce Motion it renders
/// finished, instantly: the beat is a reward, not a gate.
struct RankBadge: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var drawn: CGFloat = 0
  @State private var filled: Double = 0

  /// `TIER-1 ANALYST`, already the rank's label.
  let label: String
  var tone: Color = Theme.benign
  var size: CGFloat = 140
  /// `false` on a re-render that is not the moment — the badge stays finished.
  let animates: Bool

  /// Finished at init when there is nothing to play, for the same reason as
  /// `StampView`: a badge whose only path to "drawn" runs through `onAppear` is
  /// invisible in any static rasterisation and pops on a re-entry.
  init(
    label: String, tone: Color = Theme.benign, size: CGFloat = 140, animates: Bool = true
  ) {
    self.label = label
    self.tone = tone
    self.size = size
    self.animates = animates
    let finished = !animates || Motion.isReduced
    _drawn = State(initialValue: finished ? 1 : 0)
    _filled = State(initialValue: finished ? 1 : 0)
  }

  var body: some View {
    ZStack {
      Hexagon()
        .fill(tone.opacity(0.10 * filled))

      Hexagon()
        .trim(from: 0, to: drawn)
        .stroke(tone, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

      // Not `trackedLabel()`: that clamps to one line, and "TIER-1 ANALYST" does
      // not fit one line inside a hexagon. Same 11 pt tracked step, two lines.
      Text(label)
        .font(Typography.label)
        .tracking(Typography.labelTracking)
        .textCase(.uppercase)
        .foregroundStyle(tone)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, size * 0.13)
        .opacity(filled)
    }
    .frame(width: size, height: size)
    .onAppear(perform: play)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
  }

  private func play() {
    guard animates, let draw = Motion.gated(Motion.rankBadgeDraw) else {
      drawn = 1
      filled = 1
      return
    }
    withAnimation(draw) { drawn = 1 }
    // Gated explicitly rather than relying on the guard above: the fill is
    // unreachable under Reduce Motion either way, but a reader — and `verify.sh`'s
    // grep — should not have to prove that from the enclosing control flow.
    withAnimation(Motion.gated(Motion.rankBadgeFill.delay(Motion.rankBadgeDrawDuration))) {
      filled = 1
    }
  }
}

/// A **flat-top** regular hexagon — the `⬢` of the standing economy, at the one size
/// where it stops being a glyph and becomes a badge. Flat-top because that is the
/// orientation the glyph draws in, and the badge and the ladder track sit on the
/// same screen (§2.12).
struct Hexagon: Shape {
  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    var path = Path()
    for corner in 0..<6 {
      let angle = Angle.degrees(Double(corner) * 60).radians
      let point = CGPoint(
        x: center.x + radius * cos(angle),
        y: center.y + radius * sin(angle))
      if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
  }
}

/// The `●────●────○────○` ladder under the badge (§2.12), built from the exported
/// ranks so it can never disagree with `CareerRules.rankFor`.
struct LadderTrack: View {
  struct Rung: Identifiable {
    let id: String
    let label: String
    /// `0`, `40`, `150`, `210` — formatted by the screen.
    let threshold: String
    let held: Bool
  }

  let rungs: [Rung]
  var tone: Color = Theme.benign

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(Array(rungs.enumerated()), id: \.element.id) { index, rung in
        VStack(spacing: 6) {
          ZStack {
            if index < rungs.count - 1 {
              Rectangle()
                .fill(rungs[index + 1].held ? tone.opacity(0.6) : Theme.Zinc.z700)
                .frame(height: 1)
                .offset(x: 0)
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(rung.held ? Glyph.standingFilled : Glyph.standingEmpty)
              .font(Typography.meta)
              .foregroundStyle(rung.held ? tone : Theme.textDisabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(height: 16)

          // Two lines reserved whether or not the rung needs them, so every
          // threshold sits on one baseline instead of stepping with the labels.
          Text(rung.label)
            .font(Typography.quietLog)
            .foregroundStyle(rung.held ? Theme.textSecondary : Theme.textDisabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(2, reservesSpace: true)

          Text(rung.threshold)
            .font(Typography.quietLog)
            .tabularNumbers()
            .foregroundStyle(Theme.textDisabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview("RankBadge · promotion and finale") {
  VStack(spacing: 30) {
    RankBadge(label: "TIER-1 ANALYST")
    RankBadge(label: "TIER-2 LEAD", tone: Theme.crossover, size: 110)
    LadderTrack(rungs: [
      .init(id: "trainee", label: "Trainee", threshold: "0", held: true),
      .init(id: "t1", label: "Tier-1", threshold: "40", held: true),
      .init(id: "senior", label: "Senior", threshold: "150", held: false),
      .init(id: "t2", label: "Tier-2", threshold: "210", held: false),
    ])
  }
  .padding(24)
  .frame(width: 390)
  .background(Theme.ground)
}
