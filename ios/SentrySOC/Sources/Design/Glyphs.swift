import Foundation

/// The glyph vocabulary — `DESIGN.md` §2.16.
///
/// Glyphs, never emoji, and never SF Symbols in the game chrome: a symbol reads as
/// iOS, and this deck has to read as a terminal. The set is closed; anything not
/// listed here does not go on screen.
enum Glyph {
  /// Standing. A filled cell — access you hold.
  static let standingFilled = "⬢"
  /// Standing, unearned. The same cell, empty.
  static let standingEmpty = "⬡"
  /// Cash. Cents, because the money in this world is small and countable.
  static let cash = "¢"
  /// Correct.
  static let correct = "✓"
  /// Wrong.
  static let wrong = "✗"
  /// Forward — the CTA caret.
  static let forward = "▸"
  /// Back.
  static let back = "‹"
  /// A resolved alert on the board strip.
  static let resolved = "◉"
  /// A partially investigated alert.
  static let partial = "◔"
  /// An outbound link — Settings → About, and `learn.pointer`.
  static let external = "↗"
  /// Settings. The `⚙` every SystemBar wireframe draws in its trailing slot
  /// (§2.3, §2.5, §2.6, §2.8, §2.10, §2.11) — present in the wireframes and missing
  /// from the §2.16 roster, so it is added here rather than reached for as an SF
  /// Symbol, which would read as iOS in the one strip that has to read as a
  /// terminal. Text presentation, no variation selector, no emoji fallback.
  static let settings = "⚙"
  /// A live channel — the tone dot on an inbox card, a coach bubble, the selected
  /// tab. Small, and the only decoration in the set.
  static let dot = "●"
  /// A decisive finding you **did not** pull (§2.10: "✓ emerald = you pulled it ·
  /// ○ zinc = you missed it"). Deliberately not `standingEmpty`: `⬡` carries the
  /// standing economy's meaning everywhere else, and a missed log is not an
  /// unearned rank.
  static let missed = "○"

  /// Every glyph the deck may draw. `verify.sh` (C11) uses this roster to prove no
  /// emoji reached a player-facing string.
  static let all: [String] = [
    standingFilled, standingEmpty, cash, correct, wrong,
    forward, back, resolved, partial, external, settings, dot, missed,
  ]
}
