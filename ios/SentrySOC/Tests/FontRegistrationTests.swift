import SwiftUI
import Testing
import UIKit

@testable import SentrySOC

/// D21 / acceptance #6. The failure mode of a missing custom face is *silent*: iOS
/// falls back to system-ui, the deck looks almost right, and nobody notices until a
/// screenshot review. So the registration is asserted, not assumed.
@Suite("Font registration")
struct FontRegistrationTests {

  @Test("every declared face resolves through UIFont(name:)", arguments: Typography.registeredFaceNames)
  func faceResolves(_ name: String) {
    let font = UIFont(name: name, size: 17)
    #expect(font != nil, "\(name) did not register — check UIAppFonts and Resources/")
    // A fallback would answer to a *different* name; a real registration answers to
    // its own, which is what makes this assertion worth writing.
    #expect(font?.fontName == name)
  }

  @Test("the roster is the six faces of FONTS.md")
  func rosterIsComplete() {
    #expect(Typography.registeredFaceNames.count == 6)
    #expect(Set(Typography.registeredFaceNames) == [
      "IBMPlexMono-Regular", "IBMPlexMono-Medium", "IBMPlexMono-SemiBold",
      "SpaceGrotesk-Regular", "SpaceGrotesk-Medium", "SpaceGrotesk-Bold",
    ])
  }

  /// A face nothing draws with is dead weight: registered at launch, shipped in the
  /// bundle, drawn never. `SwiftUI.Font` exposes no name to read back, so the
  /// invariant is pinned at the other end — **what the bundle registers must be
  /// exactly what `Typography` declares**, and `Typography` declares only the faces
  /// its `Mono`/`Grotesk` cases carry, one step each (see `Resources/FONTS.md`).
  @Test("the bundle registers exactly the faces the scale declares")
  func bundleRosterMatchesTheScale() throws {
    let entries = try #require(
      Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String])
    let bundled = Set(entries.map { ($0 as NSString).deletingPathExtension })

    #expect(
      bundled == Set(Typography.registeredFaceNames),
      """
      UIAppFonts and Typography.registeredFaceNames disagree: \
      \(bundled.symmetricDifference(Typography.registeredFaceNames).sorted()). \
      A face is shipped that the scale never asks for, or asked for and never shipped.
      """)
  }

  @Test("UIAppFonts lists six BARE filenames (D21)")
  func appFontsAreBareFilenames() throws {
    let entries = try #require(
      Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String])
    #expect(entries.count == 6)
    for entry in entries {
      #expect(!entry.contains("/"), "\(entry) is a path — resources flatten into the bundle root")
      #expect(entry.hasSuffix(".ttf"))
      #expect(
        Bundle.main.url(forResource: (entry as NSString).deletingPathExtension, withExtension: "ttf") != nil,
        "\(entry) is declared but not in the bundle")
    }
  }

  @Test("both OFL texts ship beside the faces")
  func licencesShip() {
    #expect(Bundle.main.url(forResource: "OFL-IBMPlex", withExtension: "txt") != nil)
    #expect(Bundle.main.url(forResource: "OFL-SpaceGrotesk", withExtension: "txt") != nil)
  }

  @Test("the launch screen is the ground colour, so there is no white flash (S7)")
  func launchScreenIsGround() throws {
    let launch = try #require(
      Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any])
    #expect(launch["UIColorName"] as? String == "LaunchGround")
    #expect(UIColor(named: "LaunchGround") != nil)
  }
}
