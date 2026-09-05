import SwiftUI
import UIKit

/// The composition root and the only `@main`.
///
/// Order matters and is deliberate: install the screen factories, then build the
/// model — whose `init` hydrates the save synchronously — then hand the finished
/// model to the first frame. Nothing in the app awaits anything before drawing.
@main
struct SentrySOCApp: App {

  @State private var model: GameModel

  init() {
    // B6: resolves to C8/C9/C10's installers when they exist, and to the protocol's
    // no-op defaults until then, with no edit to this file either way.
    Composition.installAll()

    #if DEBUG
      Self.assertFontsRegistered()
    #endif

    let model = GameModel()

    #if SENTRY_QA
      if let destination = QAJump.requestedDestination(content: model.content) {
        model.applyQAJump(destination)
      }
    #endif

    _model = State(initialValue: model)
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
    }
  }

  #if DEBUG
    /// A silent fallback to system-ui is the worst failure mode a custom face has
    /// (R8): the app looks *almost* right and nobody notices for a week. So in Debug
    /// it is fatal, and it names the file that did not register.
    ///
    /// `FontRegistrationTests` asserts the same roster in CI, which is what catches
    /// it in Release builds too.
    private static func assertFontsRegistered() {
      let missing = Typography.registeredFaceNames.filter { UIFont(name: $0, size: 12) == nil }
      guard missing.isEmpty else {
        fatalError(
          """
          Fonts did not register: \(missing.joined(separator: ", ")).
          Check UIAppFonts in ios/project.yml and the TTFs in \
          ios/SentrySOC/Resources (see FONTS.md).
          """)
      }
    }
  #endif
}
