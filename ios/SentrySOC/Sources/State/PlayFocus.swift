import SwiftUI

/// Which half of the case the player is looking at.
///
/// It lives outside `CaseView` because two surfaces decide it: the case's own
/// segmented control, and the source sheet's two exits — "To the board" lands on
/// EVIDENCE (§2.7), "Pull another" goes back to SOURCES. A sheet cannot reach into
/// the phase underneath it, so the decision is one small observed value rather than a
/// callback chain.
///
/// **One per `GameModel`, not one per process** (P1-6). It shipped as
/// `PlayFocus.shared`, and a singleton is the wrong lifetime for it in three
/// concrete ways: a `#Preview` or a test that builds its own model shared the tab
/// with whatever ran before it and had to remember to reset it; two models in one
/// process (the QA harness previews, a snapshot suite) fought over one value; and it
/// was mutable global state on the main actor that nothing in the ownership diagram
/// accounted for. `GameModel` already is the thing whose lifetime this matches, so
/// the model holds it, and every screen reaches it the way it reaches everything
/// else — through the model it was handed.
///
/// It is deliberately **not** on `SessionState`: the reducer owns what the *game*
/// is doing, and which tab is showing is not that. It is never persisted, and coming
/// back to a restored board on SOURCES is correct.
@Observable @MainActor final class PlayFocus {
  var caseTab: CaseView.Tab = .sources
  init() {}
}
