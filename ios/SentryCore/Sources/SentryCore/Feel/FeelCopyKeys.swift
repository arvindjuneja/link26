import Foundation

/// The chrome keys the feel pass added (F2a), as addresses.
///
/// **Why this file exists.** S1 says a word a player reads is authored in
/// `chrome.ts` and never in Swift; the *key* that indexes it is an address, which is
/// why `s1-allow.txt` lets `copy.chromeText("hubEyebrow")` through. But §4's log
/// pane needs a *roster* — four to six of six templates, picked by a seed — and a
/// screen cannot build `"queryLine\(i)"` without writing a literal S1 would (rightly)
/// refuse to distinguish from copy. So the roster lives here, in `Feel/`, next to the
/// sequence that reads it: one place that knows the query pane has six templates, and
/// no screen that knows what any of them say.
///
/// Every value below is a key into `CopyPack.chrome` or `CopyPack.chromePlurals`.
/// None of it is drawn.
public enum FeelCopyKey {

  // ── §4 · the pull ──────────────────────────────────────────────────────────

  /// `QUERYING · {source}` — the sheet's eyebrow while the log pane runs.
  public static let queryHeader = "queryHeader"

  /// The six log-line templates, in authored order. `Sequences.pullSequence` emits
  /// four to six `.logLine(i)` beats and `i` indexes **this** array, so the pane a
  /// seed produces is the same pane every time.
  ///
  /// Placeholders are the four §4 names and no others: `{asset}` `{source}` `{n}`
  /// `{window}`.
  public static let queryLines = [
    "queryLine1", "queryLine2", "queryLine3", "queryLine4", "queryLine5", "queryLine6",
  ]

  /// The window every log line quotes, so the pane stays coherent — `{window}`.
  public static let queryWindow = "queryWindow"

  /// `RESULTS · {n} findings` — a **plural** key (`CopyPack.plural`), not a chrome one.
  public static let queryResults = "queryResults"

  // ── §6 · Vale ──────────────────────────────────────────────────────────────

  /// Fires on the first pull of a shift-1 case, at most once per shift.
  public static let valeFirstPull = "valeFirstPull"
  /// Fires when the call sheet opens with only a noise-weight finding on the board,
  /// at most once per shift.
  public static let valeThinCall = "valeThinCall"

  // ── §7 · leads-to ──────────────────────────────────────────────────────────

  /// The one-shot caption under an unpulled key source after a decisive or
  /// supporting finding lands.
  public static let sourceWorthALook = "sourceWorthALook"

  // ── §9 · settings ──────────────────────────────────────────────────────────

  public static let settingsSound = "settingsSound"
  public static let settingsHeartbeatSound = "settingsHeartbeatSound"
}
