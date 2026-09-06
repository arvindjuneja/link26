import SwiftUI
import SentryCore

/// The navigation of the whole app (§4.2, D16): a `ZStack` that switches on
/// `session.phase`, with overlays as sheets and covers. No stack, no back gesture.
///
/// Screens are resolved through **the model's** `ScreenRegistry` (B6): the play
/// factory first, then the meta factory, then a labelled `PlaceholderScreen`. It is
/// the model's registry and not the singleton (R9) so that a preview or a test can
/// hand this view a model with its own factories installed and get its own screens
/// back, instead of whatever the process happens to have registered.
struct PhaseHost: View {
  @Environment(GameModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var registry: ScreenRegistry { model.registry }

  var body: some View {
    ZStack {
      phaseView
        .id(model.session.phase)
        .phaseTransition
    }
    .animation(Motion.gated(Motion.screenPush, reduceMotion: reduceMotion), value: model.session.phase)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sheet(item: sheetBinding) { view in
      sheetContent(for: view)
        .presentationDetents(detents(for: view))
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.sheet)
        // §4.2: `.clear` plus a hand-painted panel, so the ground and the edge glow
        // read through the sheet. C7's `SheetChrome` paints it; until then the
        // placeholder paints its own.
        .presentationBackground(.clear)
    }
    .fullScreenCover(item: coverBinding) { view in
      sheetContent(for: view)
        .interactiveDismissDisabled(view == .firstRun)
    }
    .safeAreaInset(edge: .bottom) { debugDock }
  }

  // MARK: - Phases

  @ViewBuilder private var phaseView: some View {
    let phase = model.session.phase
    if let view = registry.play?.view(for: phase, model: model) {
      view
    } else if let view = registry.meta?.view(for: phase, model: model) {
      view
    } else {
      PlaceholderScreen(name: label(for: phase), owner: owner(for: phase))
    }
  }

  private func label(for phase: Phase) -> String {
    switch phase {
    case .hub: "Hub — the desk"
    case .briefing: "Shift intro — handover 08:00"
    case .investigating: "Case — the read"
    case .debrief(let readOnly): readOnly ? "Debrief — read-only" : "Debrief"
    case .complete: "Shift summary — 16:00 handover"
    case .milestone: "Rank-up"
    }
  }

  private func owner(for phase: Phase) -> String {
    switch phase {
    case .hub, .complete, .milestone: "Screens/Meta · C9"
    case .briefing, .investigating, .debrief: "Screens/Play · C8"
    }
  }

  // MARK: - Overlays

  /// Sheets bind to everything except the full-screen views; dismissing one is an
  /// intent like any other, so it goes through `send(_:)`.
  private var sheetBinding: Binding<ViewID?> {
    Binding(
      get: { model.session.view.flatMap { $0.isFullScreen ? nil : $0 } },
      set: { if $0 == nil { PhaseHost.dismiss(model, fullScreen: false) } })
  }

  private var coverBinding: Binding<ViewID?> {
    Binding(
      get: { model.session.view.flatMap { $0.isFullScreen ? $0 : nil } },
      set: { if $0 == nil { PhaseHost.dismiss(model, fullScreen: true) } })
  }

  /// **One dismissal, one action** (P1-1).
  ///
  /// SwiftUI writes `nil` into an item binding when the presentation goes away — and
  /// it does that whether the player swiped it down or the *app* cleared the item.
  /// So a sheet that closes itself (`SourceSheet`'s "To the board", Settings' Close,
  /// a QA jump) used to send `CLOSE_VIEW` twice: once from the screen, once from the
  /// binding catching up.
  ///
  /// That is not a harmless repeat, because `CLOSE_VIEW` is overloaded on purpose:
  /// with nothing on top it is the coach bubble's "Got it" (S4's `advance: "button"`),
  /// which is how the machine stays at seventeen actions. The second dispatch
  /// therefore silently advanced — or ended — the Shift-1 coach, one step per sheet.
  ///
  /// The guard is on the **current view**, not on a `didDismiss` flag: two conditions,
  /// both readable from the model, and no state to get out of sync. A binding may only
  /// dismiss a presentation that is actually up *and* is its own kind — so the sheet
  /// binding never closes a cover, the cover binding never closes a sheet, and neither
  /// speaks when nothing is presented. `.closeView` reaches the reducer exactly once
  /// per dismissal, and its coach arm stays reachable from the one place that means it.
  static func dismiss(_ model: GameModel, fullScreen: Bool) {
    guard let current = model.session.view, current.isFullScreen == fullScreen else { return }
    model.send(.closeView)
  }

  @ViewBuilder private func sheetContent(for view: ViewID) -> some View {
    if let sheet = registry.play?.sheet(for: view, model: model) {
      sheet
    } else if let sheet = registry.meta?.sheet(for: view, model: model) {
      sheet
    } else {
      PlaceholderScreen(name: label(for: view), owner: owner(for: view)) {
        // FirstRun's acknowledgement is the one that writes a flag (G19); every
        // other overlay just closes.
        model.send(view == .firstRun ? .ackFirstRun : .closeView)
      }
    }
  }

  private func label(for view: ViewID) -> String {
    switch view {
    case .board: "Board — queue and pressure"
    case .source(let id, _): "Source — \(id)"
    case .call: "Call sheet — hold to file"
    case .kit: "Kit"
    case .settings: "Settings"
    case .abandon: "Abandon shift"
    case .firstRun: "First run"
    }
  }

  private func owner(for view: ViewID) -> String {
    switch view {
    case .board, .source, .call, .abandon: "Screens/Play · C8"
    case .kit, .settings, .firstRun: "Screens/Meta · C9"
    }
  }

  /// §4.2, verbatim: Board `[.fraction(0.92)]` · Source `[.height(320), .large]`
  /// so the sheet *grows on the pull* · Call `[.large]` · Kit `[.medium]`.
  private func detents(for view: ViewID) -> Set<PresentationDetent> {
    switch view {
    case .board: [.fraction(0.92)]
    case .source: [.height(320), .large]
    case .call: [.large]
    case .kit: [.medium]
    case .settings: [.large]
    case .abandon: [.medium]
    case .firstRun: [.large]
    }
  }

  // MARK: - The DEBUG way in

  /// Acceptance #8. Until C9 ships the hub there is no button that starts a shift,
  /// so this is the one. It disappears the moment a meta factory is installed.
  @ViewBuilder private var debugDock: some View {
    #if DEBUG
      if registry.meta == nil, model.session.phase == .hub, model.session.view == nil {
        Button {
          model.debugStartFirstShift()
        } label: {
          HStack(spacing: 8) {
            Text("Start Shift 1").font(Typography.rowTitle)
            Text(Glyph.forward).font(Typography.meta)
          }
          .foregroundStyle(Theme.benign)
          .frame(maxWidth: .infinity, minHeight: Theme.Hit.primaryCTA)
          .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
              .fill(Theme.benign.opacity(0.08))
              .stroke(Theme.benign.opacity(0.35), lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .accessibilityIdentifier("debug.startFirstShift")
      }
    #endif
  }
}
