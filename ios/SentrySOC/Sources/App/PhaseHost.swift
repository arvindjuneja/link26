import SwiftUI

/// The navigation of the whole app (§4.2, D16): a `ZStack` that switches on
/// `session.phase`, with overlays as sheets and covers. No stack, no back gesture.
///
/// Screens are resolved through `ScreenRegistry` (B6): the play factory first, then
/// the meta factory, then a labelled `PlaceholderScreen`. With no other ticket
/// present every phase and every sheet renders a placeholder — which is the state
/// this ticket ships in, and the state its screenshot shows.
struct PhaseHost: View {
  @Environment(GameModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var registry: ScreenRegistry { .shared }

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
      set: { if $0 == nil { model.send(.closeView) } })
  }

  private var coverBinding: Binding<ViewID?> {
    Binding(
      get: { model.session.view.flatMap { $0.isFullScreen ? $0 : nil } },
      set: { if $0 == nil { model.send(.closeView) } })
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
    case .source(let id): "Source — \(id)"
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
