import SentryCore
import SwiftUI

/// The 44 pt strip under the notch — `DESIGN.md` §2.2, §2.3, §2.5, §2.6, §2.10.
///
/// Two modes, one component. On the hub it is identity and wealth
/// (`SENTRY · SOC   ⬢ 80   ¢ 650   ⚙`) and has **no ECG**, because nothing is under
/// pressure at the desk. In a shift it is position and pressure
/// (`‹ 1/7   ~~/\~~~   ALERT   26m   ⚙`) and the ECG carries the band.
///
/// Every string is a parameter: the bar is drawn on six screens and each of them
/// resolves its own copy from `CopyPack` (S1).
struct SystemBar: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// The live trace half — absent on the hub.
  struct Trace: Equatable {
    let status: TraceStatus
    /// `copy.chrome.statusCalm` at CALM, the raw band elsewhere. Resolved by the
    /// screen, never here.
    let label: String
    /// `tuning.bpm[status]` (D7).
    let bpm: Int
    /// `true` off `.investigating`, or when the scene is not active.
    var paused: Bool = false
    /// A pinned instant for a deterministic render — the snapshot suite's only
    /// use (P1-9). `nil` everywhere in the app.
    var now: Date?
    /// **The blip** (`FEEL.md` §2, §5). A monotonic counter: every change spikes the
    /// trace once and flashes the position. An alert arriving bumps it; so does a
    /// live-board reveal. It is a *counter* rather than a `Bool` because two blips in
    /// a row are two events, and a boolean that is already `true` is one.
    var pulse: Int = 0

    init(
      status: TraceStatus, label: String, bpm: Int, paused: Bool = false,
      now: Date? = nil, pulse: Int = 0
    ) {
      self.status = status
      self.label = label
      self.bpm = bpm
      self.paused = paused
      self.now = now
      self.pulse = pulse
    }
  }

  /// The trailing read-out: the queue pill (`QUEUE 3/7`, which opens the board) or
  /// the shift clock (`26m`, which does not).
  struct Pill {
    let text: String
    /// The spoken form, when the glyph-dense text does not read aloud well.
    var spoken: String?
    var action: (() -> Void)?

    init(text: String, spoken: String? = nil, action: (() -> Void)? = nil) {
      self.text = text
      self.spoken = spoken
      self.action = action
    }
  }

  /// `copy.chrome.wordmark` on the hub, `‹ 1/7` in a shift.
  let leading: String
  /// Set only where a back control is legal (§5.2: the briefing, nowhere else).
  var leadingAction: (() -> Void)?
  var trace: Trace?
  var pill: Pill?
  /// Hub only: `⬢ 80` and `¢ 650`, already formatted by the screen.
  var wallet: [String] = []
  /// Spoken label for the gear — the one control here that carries no words.
  let settingsLabel: String
  let settingsAction: () -> Void

  /// §2's ECG spike, live for one beat. Driven by `Trace.pulse`, never by a timer.
  @State private var spiking = false

  var body: some View {
    HStack(spacing: 10) {
      leadingControl
        .opacity(spiking ? 0.55 : 1)

      if let trace {
        // The trace is the first thing to go and the last thing to matter: it is
        // decoration for a band the status word states outright (which is exactly
        // why `ECGCanvas` hides itself from VoiceOver). So it yields all the way to
        // zero before the pill loses a character, and above `.xxLarge` it is not
        // drawn at all — at that size the words need every point of the strip.
        if showsTrace {
          ECGCanvas(status: trace.status, bpm: trace.bpm, paused: trace.paused, now: trace.now)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: 22)
            // "amplitude x3 for one beat" (§2, row 2). A scale on the canvas rather
            // than a second trace generator: the canvas draws a 22 pt band and the
            // spike is that band, briefly taller — which is what an ECG spike is.
            .scaleEffect(y: spiking ? 3 : 1, anchor: .center)
            .layoutPriority(-1)
        } else {
          Spacer(minLength: 0)
        }

        Text(trace.label)
          .trackedLabel(Theme.status(trace.status).text, scale: shrinkFloor)
          // §4: "the SystemBar band word pulses once" behind a decisive finding. The
          // same blip the trace spikes on, because it is the same event.
          .opacity(spiking ? 0.55 : 1)
          .layoutPriority(1)
      } else {
        Spacer(minLength: 8)
      }

      ForEach(Array(wallet.enumerated()), id: \.offset) { _, entry in
        Text(entry)
          .font(Typography.meta)
          .tabularNumbers()
          .foregroundStyle(Theme.textTertiary)
          .lineLimit(1)
          .minimumScaleFactor(shrinkFloor)
          .layoutPriority(1)
      }

      if let pill { pillView(pill) }

      settingsButton
    }
    .padding(.horizontal, 16)
    // `minHeight`, not `height`: 44 pt is the floor of the §2.2 thumb band, not a
    // ceiling the content is clipped against. At 320 pt with a large type setting
    // the strip is allowed to grow instead of pushing the queue capsule out of it.
    .frame(minHeight: Theme.Hit.minimum)
    .frame(maxWidth: .infinity)
    .background(alignment: .bottom) {
      Rectangle()
        .fill(Theme.hairline)
        .frame(height: 1)
    }
    // The band tints the strip itself as pressure rises — the edge glow of §2.14,
    // at the one place it can live without a second full-screen layer.
    .background(traceWash)
    .onChange(of: trace?.pulse ?? 0) { _, _ in blip() }
  }

  /// One spike, then back. 260 ms out and 220 ms back is a beat of the ECG at ALERT,
  /// which is why the spike reads as the trace doing something rather than as the bar
  /// animating.
  private func blip() {
    withAnimation(Motion.gated(Motion.beatArrive)) { spiking = true }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120), tolerance: .zero)
      withAnimation(Motion.gated(Motion.beatArrive)) { spiking = false }
    }
  }

  // MARK: - Dynamic Type

  /// How far the strip's words may shrink before they would truncate.
  ///
  /// `trackedLabel`'s own 0.9 is a notch, not a budget: `QUEUE 3/7` at
  /// `.xxxLarge` — a *standard* slider position, not an accessibility one — is
  /// already wider than the room a 44 pt bar with an ECG, a status word and a gear
  /// can give it, and at `.accessibility1` (the §4.5 ceiling) it collapsed to `QU…`.
  /// A shrunk `QUEUE 3/7` is legible; an ellipsised one is a stub, and this bar is
  /// where the player reads which alert they are on and how many are left on six
  /// separate screens.
  ///
  /// The floor is deeper at the accessibility sizes only, and it is chosen so the
  /// **rendered** size never falls under §2.16's 11 pt. `.caption2` is 11 pt at
  /// `.large` — where nothing shrinks, because nothing is tight — ~15 pt at
  /// `.xxxLarge`, 0.75 of which is 11 pt, and ~23 pt at `.accessibility1`, where 0.5
  /// is 11.5 pt. Shrinking here never draws smaller than the deck's own floor.
  private var shrinkFloor: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 0.5 : 0.75
  }

  /// The ECG is drawn only while the type is small enough that it is not stealing
  /// width from a word. Above `.xxLarge` the status word alone carries the band.
  private var showsTrace: Bool { dynamicTypeSize <= .xxLarge }

  // MARK: - Parts

  @ViewBuilder private var leadingControl: some View {
    if let leadingAction {
      Button(action: leadingAction) {
        Text(leading)
          .trackedLabel(Theme.textTertiary, scale: shrinkFloor)
          .padding(.trailing, 6)
          .minimumHitTarget()
      }
      .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
      .accessibilityIdentifier("systemBar.back")
      // Same priority as the pill and the status word: the back control carries
      // both the affordance and the position, so it is not the item that gets
      // squeezed to `‹ …` while a band word the wash already states stays whole.
      .layoutPriority(1)
    } else {
      Text(leading)
        .trackedLabel(Theme.textTertiary, scale: shrinkFloor)
        .accessibilityIdentifier("systemBar.wordmark")
        .layoutPriority(1)
    }
  }

  @ViewBuilder private func pillView(_ pill: Pill) -> some View {
    let label = Text(pill.text)
      .font(Typography.meta)
      .tabularNumbers()
      .foregroundStyle(Theme.falsePositive)
      .lineLimit(1)
      .minimumScaleFactor(shrinkFloor)
      .padding(.horizontal, 10)
      .frame(minHeight: 26)
      .background {
        Capsule(style: .continuous)
          .fill(Theme.falsePositive.opacity(0.10))
      }
      .overlay {
        Capsule(style: .continuous)
          .strokeBorder(Theme.falsePositive.opacity(0.35), lineWidth: 1)
      }

    if let action = pill.action {
      Button(action: action) {
        label.minimumHitTarget()
      }
      .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
      .accessibilityLabel(pill.spoken ?? pill.text)
      .accessibilityIdentifier("systemBar.queue")
      // Priority 1, the same as the leading control and the status word — not
      // higher. Ranking the pill above them makes it refuse to shrink at all and
      // spends the whole deficit on `‹ 3…` and `LOCK…` instead, which is worse in
      // aggregate: rendered at 320 pt / `.accessibility1`, one flat rank has every
      // word whole except the pill's last two characters, while a pill-first rank
      // truncates two of the three. Verified, both ways, in
      // `docs/screenshots/ios/components/SystemBar-320-accessibility1.png`.
      .layoutPriority(1)
    } else {
      label
        .accessibilityLabel(pill.spoken ?? pill.text)
        .accessibilityIdentifier("systemBar.clock")
        .layoutPriority(1)
    }
  }

  private var settingsButton: some View {
    Button(action: settingsAction) {
      Text(Glyph.settings)
        .font(Typography.metaStrong)
        .foregroundStyle(Theme.textTertiary)
        .frame(width: Theme.Hit.minimum, height: Theme.Hit.minimum)
        .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
    .accessibilityLabel(settingsLabel)
    .accessibilityIdentifier("systemBar.settings")
    // The 44 pt square already covers the target; trim the row padding it would
    // otherwise add on the trailing edge.
    .padding(.trailing, -10)
  }

  @ViewBuilder private var traceWash: some View {
    if let trace {
      let palette = Theme.status(trace.status)
      LinearGradient(
        colors: [palette.glow.opacity(palette.glowOpacity), .clear],
        startPoint: .top, endPoint: .bottom)
    }
  }
}

#Preview("SystemBar · hub and the four bands") {
  VStack(spacing: 0) {
    SystemBar(
      leading: "SENTRY · SOC",
      wallet: ["⬢ 80", "¢ 650"],
      settingsLabel: "Settings",
      settingsAction: {})

    ForEach(
      [
        (TraceStatus.calm, "QUIET", 50, "QUEUE 1/7"),
        (.alert, "ALERT", 76, "QUEUE 3/7"),
        (.hunt, "HUNT", 112, "QUEUE 5/7"),
        (.lockdown, "LOCKDOWN", 150, "QUEUE 6/7"),
      ], id: \.0
    ) { status, label, bpm, queue in
      SystemBar(
        leading: "‹ 1/7",
        leadingAction: {},
        trace: .init(status: status, label: label, bpm: bpm),
        pill: .init(text: queue, action: {}),
        settingsLabel: "Settings",
        settingsAction: {})
    }
  }
  .frame(width: 390)
  .background(Theme.ground)
}
