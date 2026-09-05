import SentryCore
import SwiftUI

/// The heartbeat you can see — `DESIGN.md` §2.14, `SPEC.md` §10 C7 #2.
///
/// `TimelineView(.animation(minimumInterval:paused:))` + `Canvas`: one redraw
/// schedule the OS owns, no `Timer`, no per-frame view diffing, and a `paused` flag
/// that costs nothing when the trace is not on screen. The waveform scrolls one full
/// beat per `60 / bpm` seconds, which is why the strip *is* the status — a player
/// reads the pressure band before they read the word.
///
/// **Reduce Motion** degrades it to a single still frame of the same path
/// (`ECGTrace`, below). The label half of "static `Path` glyph + label" lives in
/// `SystemBar`, which draws the status word beside this view in both modes — the
/// trace is never the only carrier of the band.
struct ECGCanvas: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let status: TraceStatus
  /// `tuning.bpm[status]` — never a literal (D7); the caller reads the bundle.
  let bpm: Int
  /// `true` when the phase is not `.investigating` or the scene is not active. The
  /// trace then stops **being redrawn at all** rather than being handed a paused
  /// schedule — see the note on `body`.
  var paused: Bool = false
  /// A fixed instant to draw, instead of the wall clock (P1-9).
  ///
  /// `nil` in the app, always. It exists for `ComponentSnapshotTests`, whose PNGs
  /// were otherwise a function of the second they were rendered in: eleven committed
  /// images changed on every run, so the one artefact that is supposed to make a
  /// visual regression obvious was noise. A pinned instant makes them byte-stable.
  var now: Date?

  var body: some View {
    Group {
      if reduceMotion || paused {
        // **`paused` means still, not "a schedule that has stopped"** (P1-9). It was
        // handed to `TimelineView(.animation(paused:))`, which stops the *updates*
        // but leaves a live `TimelineView` in the tree whose schedule SwiftUI still
        // owns — and the deck asks for this at 16:00 (§2.11: "the ECG flattens and
        // fades") and every time the phase leaves `.investigating`, which is most of
        // the app. A still frame of the same drawing is what a stopped trace is, and
        // it is a view that can be rendered — and reviewed in a screenshot — without
        // waiting for a schedule to not fire.
        ECGTrace(status: status, phase: stillPhase, showsHead: false)
      } else {
        TimelineView(.animation(minimumInterval: Motion.ecgFrameInterval)) { context in
          ECGTrace(status: status, phase: phase(at: now ?? context.date))
        }
      }
    }
    // The ECG is decoration for a value VoiceOver already reads out of the
    // SystemBar's status element (§4.5). Two voices for one fact is noise.
    .accessibilityHidden(true)
  }

  /// Where a still trace is caught: the pinned instant if there is one, else
  /// mid-beat, so a stopped trace shows the QRS spike rather than a flat line that
  /// reads as "no signal".
  private var stillPhase: Double {
    now.map(phase(at:)) ?? ECGTrace.restingPhase
  }

  /// 0…1 through one cardiac cycle at `date`.
  private func phase(at date: Date) -> Double {
    let period = Motion.ecgPeriod(bpm: bpm)
    return date.timeIntervalSinceReferenceDate
      .truncatingRemainder(dividingBy: period) / period
  }
}

/// **One frame** of the trace, at a given scroll phase.
///
/// Separated from `ECGCanvas` so the Reduce Motion degrade is a view that can be
/// rendered — and reviewed in a screenshot — without changing a system setting, and
/// so the moving and the still trace can never drift into two different drawings.
struct ECGTrace: View {
  /// Where the still frame is caught: mid-beat, so the degrade shows the QRS spike
  /// rather than a flat line that reads as "no signal".
  static let restingPhase: Double = 0.5

  let status: TraceStatus
  /// 0…1 through one cardiac cycle.
  let phase: Double
  /// The bright head that gives the trace a direction — only where there is motion
  /// to have a direction in.
  var showsHead: Bool = true

  var body: some View {
    Canvas { context, size in
      draw(in: &context, size: size)
    }
  }

  // MARK: - Drawing

  /// How much of the full waveform a band spends. CALM is "near-flat at 50 % opacity
  /// with one faint blip" (§2.14) — the quiet *is* the reward, so it is drawn as
  /// quiet, not as a smaller version of LOCKDOWN.
  private var gain: Double {
    switch status {
    case .calm: 0.30
    case .alert: 0.62
    case .hunt: 0.85
    case .lockdown: 1.0
    }
  }

  private var inkOpacity: Double {
    status == .calm ? 0.50 : 1.0
  }

  /// How many beats fit across the strip. More pressure, more trace on screen —
  /// the same 40 pt of glass gets busier as the shift gets worse.
  private var beatsAcross: Double {
    switch status {
    case .calm: 1.6
    case .alert: 2.0
    case .hunt: 2.6
    case .lockdown: 3.2
    }
  }

  private func draw(in context: inout GraphicsContext, size: CGSize) {
    guard size.width > 1, size.height > 1 else { return }
    let palette = Theme.status(status)
    let midY = size.height / 2
    let amplitude = size.height * 0.42 * gain

    var path = Path()
    let steps = max(Int(size.width), 2)
    for step in 0...steps {
      let x = Double(step) / Double(steps)
      var t = (x * beatsAcross - phase * beatsAcross).truncatingRemainder(dividingBy: 1)
      if t < 0 { t += 1 }
      let point = CGPoint(x: x * size.width, y: midY - waveform(at: t) * amplitude)
      if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }

    context.stroke(
      path,
      with: .color(palette.text.opacity(inkOpacity)),
      style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

    if showsHead {
      context.fill(
        Path(ellipseIn: CGRect(x: size.width - 5, y: midY - 2.5, width: 5, height: 5)),
        with: .color(palette.text.opacity(inkOpacity * 0.8)))
    }
  }

  /// One cardiac cycle over `t ∈ [0, 1)`, in −1…1. A sum of Gaussians: P wave, the
  /// QRS complex, T wave. It is not a medical trace and does not pretend to be —
  /// it is the shape a person recognises as a heartbeat at 30 pt tall.
  private func waveform(at t: Double) -> Double {
    func bump(_ center: Double, _ width: Double, _ height: Double) -> Double {
      let d = (t - center) / width
      return height * exp(-d * d)
    }
    return bump(0.16, 0.035, 0.18)
      + bump(0.300, 0.010, -0.30)
      + bump(0.340, 0.012, 1.00)
      + bump(0.385, 0.012, -0.42)
      + bump(0.560, 0.050, 0.28)
  }
}

#Preview("ECG · all four bands, live and degraded") {
  let bpm = ContentPack.bundled.tuning.bpm

  return VStack(alignment: .leading, spacing: 20) {
    Text("LIVE").trackedLabel()
    ForEach(TraceStatus.allCases, id: \.self) { status in
      HStack(spacing: 14) {
        Text(status.rawValue)
          .trackedLabel(Theme.status(status).text)
          .frame(width: 92, alignment: .leading)
        ECGCanvas(status: status, bpm: bpm[status]).frame(height: 26)
      }
    }

    Text("REDUCE MOTION").trackedLabel()
    ForEach(TraceStatus.allCases, id: \.self) { status in
      HStack(spacing: 14) {
        Text(status.rawValue)
          .trackedLabel(Theme.status(status).text)
          .frame(width: 92, alignment: .leading)
        ECGTrace(status: status, phase: ECGTrace.restingPhase, showsHead: false)
          .frame(height: 26)
      }
    }
  }
  .padding(24)
  .frame(width: 390)
  .background(Theme.ground)
}
