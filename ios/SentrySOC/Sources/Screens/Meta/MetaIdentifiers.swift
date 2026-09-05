import Foundation

/// **Addresses, not copy** — the one S1 exception this ticket needs, gathered in one
/// file so the grep has a single documented allowance instead of six scattered ones.
///
/// S1 forbids a string literal containing a letter anywhere under `Sources/Screens/**`
/// outside `#Preview` blocks and the `accessibilityIdentifier` / `Image(systemName:)` /
/// `Font.custom` arguments, because a literal *word* on a screen is player copy that
/// escaped the exporter. Nothing below is player copy:
///
/// - two bundled licence filenames (§5.11 asks Licences to carry both OFL texts, and
///   the texts are the shipped `.txt` files, not something `copy.json` could hold);
/// - two `Info.plist` keys, which is where the version in `chrome.aboutEyebrow`'s
///   `{version}` run comes from;
/// - the privacy-policy URL (`SPEC.md` §8 — a founder/web task, see below);
/// - the QA jump names, which are `-SentryQAScreen` arguments and compile only under
///   `SENTRY_QA`.
///
/// They have nowhere else to live: `copy.json` is player text (C1's), and
/// `Sources/Services/` is C6's. **REQUEST TO THE LEAD:** have `verify.sh`'s S1 grep
/// skip this one file (or treat `MetaID.` the way it treats `accessibilityIdentifier`).
enum MetaID {

  // MARK: - Bundled licence texts

  /// The two OFL files `project.yml` copies into the bundle root beside the six TTFs.
  /// Their first line is the copyright line, which is what the Licences screen uses
  /// as each section's heading — read out of the file rather than re-typed here, so
  /// a font swap cannot leave a stale attribution on screen.
  enum Licence: String, CaseIterable, Identifiable {
    case plex = "OFL-IBMPlex"
    case grotesk = "OFL-SpaceGrotesk"

    var id: String { rawValue }
  }

  static let licenceExtension = "txt"

  // MARK: - The version line

  static let shortVersionKey = "CFBundleShortVersionString"
  static let buildVersionKey = "CFBundleVersion"

  /// `1.0 (1)` — the `{version}` run of `chrome.aboutEyebrow`, and the line five taps
  /// on reveals the QA jumps (§5.11, D19).
  static var version: String {
    let info = Bundle.main.infoDictionary
    let short = info?[shortVersionKey] as? String ?? ""
    let build = info?[buildVersionKey] as? String ?? ""
    return build.isEmpty ? short : "\(short) (\(build))"
  }

  // MARK: - The app's one outbound link

  /// Settings → About → **Privacy policy** (§5.11). Guideline 5.1.1(i) needs this link
  /// inside the app even at zero collection, and the page it opens is now real:
  /// `app/privacy/page.tsx` — a static route in this repo's own Next app, written for
  /// this game (P1-4).
  ///
  /// **Why this host.** The previous value was the founder's own domain, and it was
  /// measured broken: `link26.oumm.pl` and `oumm.pl` both resolve to `2.57.137.2`,
  /// which presents a `CN=*.zenbox.pl` certificate (Certum DV TLS G2 R39, SAN
  /// `*.zenbox.pl, zenbox.pl`) — shared-hosting parking, not the Cloudflare deploy —
  /// so **any** URL on it opens Safari's "This Connection Is Not Private"
  /// interstitial. Re-measured today: unchanged. The app's ONE outbound link must not
  /// read as a phishing warning.
  ///
  /// The Worker `link26` is deployed on this account (`wrangler deployments list`
  /// shows versions through 2026-07-07) and the account's workers.dev subdomain is
  /// `arvind` — verified on the wire, not guessed: `*.arvind.workers.dev` resolves
  /// with valid Cloudflare TLS, while a made-up subdomain does not resolve at all.
  ///
  /// **FOUNDER STEP, and the last one on this link.** `link26.arvind.workers.dev`
  /// currently answers `404 · error code 1042` — the Worker has no workers.dev route
  /// enabled, and `/privacy` has not been deployed yet either. One deploy of the web
  /// app with workers.dev routing on fixes both. Until then the link resolves to a
  /// page that is not there — which is why the About screen prints the privacy
  /// **summary inline** and the address in full beneath it (`AboutScreen`), so 5.1.1
  /// is satisfied by the app itself and the link is corroboration rather than the
  /// whole claim. Changing the host is this one line.
  static let privacyPolicy = "https://link26.arvind.workers.dev/privacy"

  // MARK: - QA

  #if SENTRY_QA
    /// Every name `QAJump.destination(named:content:)` answers to (C5's file, which
    /// publishes no roster). Order is the order of the deck, so the reveal row reads
    /// like a table of contents.
    static let qaScreens: [String] = [
      "hub", "firstrun", "settings", "kit",
      "intro", "board", "case", "source", "call", "abandon",
      "debrief", "debrief-readonly", "summary", "rankup",
    ]
  #endif
}
