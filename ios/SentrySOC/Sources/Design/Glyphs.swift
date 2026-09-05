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

  /// Every glyph the deck may draw. `verify.sh` (C11) uses this roster to prove no
  /// emoji reached a player-facing string.
  static let all: [String] = [
    standingFilled, standingEmpty, cash, correct, wrong,
    forward, back, resolved, partial, external,
  ]
}
