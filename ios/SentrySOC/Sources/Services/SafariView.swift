import SafariServices
import SwiftUI

/// An in-app browser for the two links the deck offers: `learn.pointer` on a debrief
/// and the privacy line in Settings → About.
///
/// **Unused inside C6, on purpose.** Its consumers are C8's debrief (`learn.pointer`)
/// and C9's About/Licences, and neither may add a file to `Sources/Services/` — the
/// §10 ownership is disjoint. It ships here so those tickets have the seam on day
/// one, the same way `SessionStubs.swift` names C5.
///
/// `SFSafariViewController` rather than `openURL`: leaving the app mid-shift to a
/// full browser loses the board, and the sheet keeps the reading inside the session.
/// It also carries its own reader affordances and a visible domain, which is the
/// honest way to show a player where a "learn it for real" pointer is sending them.
struct SafariView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let configuration = SFSafariViewController.Configuration()
    configuration.entersReaderIfAvailable = false
    let controller = SFSafariViewController(url: url, configuration: configuration)
    controller.preferredControlTintColor = UIColor(Theme.falsePositive)
    controller.preferredBarTintColor = UIColor(Theme.ground)
    controller.dismissButtonStyle = .close
    return controller
  }

  func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension SafariView {

  /// `SFSafariViewController` accepts http(s) only and traps on anything else, so
  /// every call site goes through this instead of forcing a `URL`.
  static func make(_ string: String) -> SafariView? {
    guard let url = URL(string: string),
          let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http"
    else { return nil }
    return SafariView(url: url)
  }
}
