import Foundation
import Testing
import SentryCore

@testable import SentrySOC

/// **P1-1 · one dismissal, one action.**
///
/// `PhaseHost` binds `.sheet(item:)` and `.fullScreenCover(item:)` to
/// `session.view`. SwiftUI writes `nil` into an item binding when the presentation
/// goes away — including when it went away because the *app* cleared the item — so a
/// sheet that closes itself (`SourceSheet`'s "To the board", the settings Close, a
/// QA jump) got `CLOSE_VIEW` twice: once from the screen, once from the binding
/// catching up.
///
/// That is not harmless, because `CLOSE_VIEW` with nothing on top is a **different
/// transition**: it is the coach bubble's "Got it" (S4's `advance: "button"`). The
/// second dispatch therefore silently advanced — or ended — the Shift-1 coach.
@MainActor
@Suite("Sheet dismissal")
struct PhaseHostDismissTests {

  private static func temporaryDirectory() -> URL {
    let url = URL.temporaryDirectory
      .appending(path: "DismissTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func scratchFlags() -> (Flags, UserDefaults, String) {
    let name = "DismissTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (Flags(defaults: defaults), defaults, name)
  }

  private static func model(_ flags: Flags) -> GameModel {
    GameModel(
      save: SaveStore(directory: temporaryDirectory()), flags: flags,
      registry: ScreenRegistry())
  }

  /// A board opened, so the coach is live on the first alert. `BEGIN` leaves the
  /// board sheet up — which is the presentation these tests dismiss.
  private static func onFirstAlert(_ model: GameModel) {
    guard let shift = model.content.shifts.first else { return }
    model.send(.startShift(shift.id))
    model.send(.begin)
  }

  /// The coach on the step that a stray `CLOSE_VIEW` can actually move.
  ///
  /// Step 0 advances on the first pull, step 1 on its own "Got it" **button**, step 2
  /// is terminal. So the damage lands from step 1 onward, and reaching it takes a
  /// pull. Getting there also closes the board sheet, so the caller re-opens it.
  private static func onCoachButtonStep(_ model: GameModel) {
    onFirstAlert(model)
    model.send(.closeView)                      // the board sheet BEGIN opened
    if let source = model.session.currentCase(model.content)?.sourceIds.first {
      model.send(.pullSource(source))           // step 0 → step 1, the button step
    }
    model.send(.openView(.source(model.session.queried.first ?? "")))
  }

  // MARK: - Why the second dispatch is not harmless

  @Test("CLOSE_VIEW with nothing on top is the coach's button, not a dismissal")
  func closeViewWithNoViewAdvancesTheCoach() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = Self.model(flags)
    Self.onCoachButtonStep(model)

    model.send(.closeView)                      // the source sheet
    #expect(model.session.view == nil)
    #expect(model.session.coachStep == 1, "the coach is on its button step")

    model.send(.closeView)                      // nothing on top — the coach's "Got it"
    #expect(model.session.coachStep == 2, "CLOSE_VIEW is overloaded, and this is the other arm")
  }

  // MARK: - The guard

  @Test("a sheet dismissal dispatches CLOSE_VIEW exactly once")
  func sheetDismissalIsOneAction() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = Self.model(flags)
    Self.onCoachButtonStep(model)

    let coachBefore = model.session.coachStep
    #expect(model.session.view != nil, "a sheet is up to dismiss")

    // SwiftUI writing nil into the item binding, twice: once for the dismissal, and
    // once more because the item it was bound to is already gone. Both go through
    // the real dismissal rule, which is the thing under test.
    PhaseHost.dismiss(model, fullScreen: false)
    PhaseHost.dismiss(model, fullScreen: false)

    #expect(model.session.view == nil)
    #expect(model.session.coachStep == coachBefore, "the second dismissal ate a coach step")
  }

  @Test("a sheet dismissal never closes a full-screen cover, or the reverse")
  func dismissalMindsItsOwnPresentation() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = Self.model(flags)
    Self.onCoachButtonStep(model)
    let presented = model.session.view

    // A sheet is up. The cover's binding must not claim the dismissal — if it did,
    // the coach step would move on a presentation that never existed.
    let coachBefore = model.session.coachStep
    PhaseHost.dismiss(model, fullScreen: true)
    #expect(model.session.view == presented, "the cover binding dismissed a sheet")
    #expect(model.session.coachStep == coachBefore)

    PhaseHost.dismiss(model, fullScreen: false)
    #expect(model.session.view == nil)

    // And with nothing presented at all, neither binding may dispatch.
    PhaseHost.dismiss(model, fullScreen: false)
    PhaseHost.dismiss(model, fullScreen: true)
    #expect(model.session.coachStep == coachBefore, "a dismissal fired with nothing on top")
  }

  /// The screen's own exit and the binding's catch-up are the same dismissal: one
  /// `CLOSE_VIEW` between them, not two. This is the shape that actually shipped —
  /// `SourceSheet` closes itself, then SwiftUI writes `nil`.
  @Test("a sheet that closes itself is not closed twice")
  func selfClosingSheetIsNotDoubleCounted() {
    let (flags, defaults, suite) = Self.scratchFlags()
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = Self.model(flags)
    Self.onCoachButtonStep(model)

    let coachBefore = model.session.coachStep
    model.send(.closeView)                      // the screen's own exit
    PhaseHost.dismiss(model, fullScreen: false)  // SwiftUI catching up

    #expect(model.session.view == nil)
    #expect(model.session.coachStep == coachBefore)
  }
}
