import SwiftUI
import SentryCore

/// The four things every play screen needs and none of them should spell twice: the
/// system strip, the caret rule, the one metered-value → bar-fraction conversion,
/// and the percent formatter.
///
/// **Nothing here decides anything.** Every number it touches has already been
/// computed by `SentryCore` (D8); what it does is *present* — divide a level by its
/// own ceiling so a `Capsule` can be that wide, and round a ratio the engine already
/// produced. That boundary is the reason `meterFraction` takes a parameter called
/// `level` rather than reading `shift.breachRisk` itself: C8 acceptance #7 greps for
/// arithmetic on `breachRisk` / `noise` / `cash` / `standing` under `Screens/`, and
/// this file is the single audited place where a metered value becomes a width.
enum Play {

  // ── copy ───────────────────────────────────────────────────────────────────

  /// A Dock title, without the caret the exported string already carries.
  ///
  /// `Dock` draws `▸` itself, so `intro.cta` ("Start the shift ▸"), `debriefNext`,
  /// `debriefEnd`, `summaryBack` and `boardOpenAlert` would otherwise render two.
  /// The alternative — a second set of caret-free copy keys — is copy duplication
  /// for a glyph the design system owns.
  static func cta(_ title: String) -> String {
    var trimmed = Substring(title)
    while let last = trimmed.last, last.isWhitespace || String(last) == Glyph.forward {
      trimmed = trimmed.dropLast()
    }
    return String(trimmed)
  }

  /// `0.8571…` → `86`. The engine produced the ratio; this only rounds it for a
  /// `{pct}` slot.
  static func percent(_ ratio: Double) -> String {
    guard ratio.isFinite else { return "0" }
    return String(Int((ratio * 100).rounded()))
  }

  /// The band word a player reads. CALM is re-voiced ("QUIET") because the word the
  /// deck shows at rest is copy; the other three are the band itself.
  static func statusLabel(_ status: TraceStatus, _ copy: CopyPack) -> String {
    status == .calm ? copy.chromeText("statusCalm") : status.rawValue
  }

  // ── geometry ───────────────────────────────────────────────────────────────

  /// A pressure level as a fraction of its own ceiling, for a bar's width.
  ///
  /// The parameter is a bare `level` on purpose (see the type doc): the arithmetic
  /// is on the tuning's span, and the meter it came from is the caller's business.
  static func meterFraction(level: Int, tuning: Tuning) -> Double {
    let span = Double(tuning.trace.max - tuning.trace.min)
    guard span > 0 else { return 0 }
    return min(1, max(0, Double(level - tuning.trace.min) / span))
  }

  /// The soft time budget as a fraction. Surfaced, never scored (§2.5).
  static func timeFraction(used: Int, budget: Int) -> Double {
    guard budget > 0 else { return 0 }
    return min(1, max(0, Double(used) / Double(budget)))
  }

  /// How far along the ladder a standing figure sits, against the next rung's
  /// threshold. `nil` is the top rung — the bar is full and stays full.
  static func standingFraction(value: Int, threshold: Int?) -> Double {
    guard let threshold, threshold > 0 else { return 1 }
    return min(1, max(0, Double(value) / Double(threshold)))
  }
}

// MARK: - The system strip

/// `SystemBar`, wired to the session, for the four play surfaces.
///
/// Every play screen draws the strip itself (§2.1: "SystemBar renders above
/// everything except RankUp and FirstRun") — `PhaseHost` deliberately does not, so a
/// screen keeps control of what its leading control means. Here it means: on the
/// case, *back to the queue*; on the briefing, *back to the desk*; on a debrief or a
/// summary, nothing at all, because a completed call is not browsed (§5.8).
struct PlayBar: View {
  let model: GameModel

  enum Leading {
    /// `‹ 1/7` — opens the board sheet.
    case queuePosition
    /// `‹ Desk` — the one legal back control in the loop (§5.2).
    case backToDesk
    /// `SENTRY · SOC`. No control: there is nowhere to go.
    case wordmark
  }

  let leading: Leading
  /// `nil` on the briefing — no board, no pressure, no ECG.
  var trace: TraceStatus?
  /// The ECG flattens and fades at 16:00 (§2.11).
  var tracePaused: Bool = false
  /// The trailing read-out: shift-minutes on the case, or `1/7` on a debrief.
  var readout: String?

  private var copy: CopyPack { model.content.copy }

  var body: some View {
    SystemBar(
      leading: leadingText,
      leadingAction: leadingAction,
      trace: trace.map {
        .init(
          status: $0, label: Play.statusLabel($0, copy),
          bpm: model.content.tuning.bpm[$0], paused: tracePaused)
      },
      wallet: readout.map { [$0] } ?? [],
      settingsLabel: copy.chromeText("settingsTitle"),
      settingsAction: { model.send(.openView(.settings)) })
  }

  private var leadingText: String {
    switch leading {
    case .queuePosition: "\(Glyph.back) \(queueCount)"
    case .backToDesk: copy.chromeText("back")
    case .wordmark: copy.chromeText("wordmark")
    }
  }

  private var leadingAction: (() -> Void)? {
    switch leading {
    case .queuePosition: { model.send(.openView(.board)) }
    case .backToDesk: { model.send(.toHub) }
    case .wordmark: nil
    }
  }

  /// `3/7` — the alert in front of the player, over the board's length.
  private var queueCount: String {
    guard let shift = model.session.shift else { return "" }
    return copy.render(
      copy.chromeText("queueCount"),
      ["n": String(shift.index + 1), "m": String(shift.caseIds.count)])
  }
}

// MARK: - Small shared pieces

/// A tracked 11 pt eyebrow over a block of content — the deck's one section header.
///
/// Not `trackedLabel()`: that clamps to one line, and two of the exported eyebrows
/// are sentences rather than labels — `caseSourcesEyebrow` ("Pull a data source —
/// which log answers the question?") shipped as `…THE QUESTI…` in the first render.
/// Same 11 pt tracked step, allowed a second line.
struct PlayEyebrow: View {
  let text: String
  var tone: Color = Theme.textQuiet
  var trailing: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(text)
        .font(Typography.label)
        .tracking(Typography.labelTracking)
        .textCase(.uppercase)
        .foregroundStyle(tone)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: false, vertical: true)
      if let trailing {
        Spacer(minLength: 8)
        Text(trailing)
          .font(Typography.meta)
          .tabularNumbers()
          .foregroundStyle(Theme.textDisabled)
          .layoutPriority(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A `Dock` mounted over a scroll region.
///
/// `Dock` paints its own short fade, which is right when it sits in a sheet's
/// footer and wrong when it floats over a list: at the CTA's own baseline the fade
/// is still ~10 % transparent, so the first render had "Make the call" printed over
/// the last source row. This adds a 28 pt run-up of ground above it and makes the
/// bar itself opaque — content fades out through the strip and is hidden behind the
/// button, which is what §2.6's wireframe draws.
struct PlayDock<Content: View>: View {
  /// `false` when something directly above this inset has already painted the
  /// ground — the coach bubble, on the first alert of a shift. A second fade there
  /// would be 28 pt of nothing.
  var fade: Bool = true
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      if fade {
        LinearGradient(
          colors: [Theme.ground.opacity(0), Theme.ground],
          startPoint: .top, endPoint: .bottom)
          .frame(height: 28)
          .allowsHitTesting(false)
      }
      content.background(Theme.ground)
    }
  }
}

/// The hairline that separates a header from what it introduces (§2.6).
struct PlayHairline: View {
  var body: some View {
    Rectangle()
      .fill(Theme.hairline)
      .frame(height: 1)
      .accessibilityHidden(true)
  }
}

extension View {
  /// A short dissolve at the top of a scroll region.
  ///
  /// §2.6 gives the case a "short run-off under the bar so the line the header is
  /// cutting through dissolves instead of being guillotined mid-x-height", painted
  /// by `CollapsedCaseHeader`. The debrief and the summary scroll under the same
  /// `PlayBar` with nothing to paint one, so a scrolled line was being cut dead at
  /// the hairline. This masks the content instead of covering it, which is the only
  /// version that also works on the debrief — that screen floods the ground with a
  /// 6 % verdict tint, so a strip painted in `Theme.ground` would read as a band.
  func playScrollTopFade(_ height: CGFloat = 16) -> some View {
    mask(
      VStack(spacing: 0) {
        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
          .frame(height: height)
        Rectangle()
      }
      .ignoresSafeArea())
  }
}
