import Foundation
import SentryCore

/// **`SocCue` → a file in `Resources/Sounds/`** (`FEEL.md` §9).
///
/// §9's rule, verbatim: "a single `SoundBank` enum maps `SocCue` → file, so cues and
/// sounds stay one vocabulary". There is therefore no second list of sound names
/// anywhere in the app — a screen fires a cue, the same cue reaches the hand and the
/// ear, and a cue that gains a sound gains it here and nowhere else.
///
/// **Variants.** Three cues are one sound at several pitches: `findingLand` and
/// `landCard` cycle three mallet pitches so four cards in a row are a phrase rather
/// than a stutter, and `ping` walks seven semitones so a filling queue is audible as
/// a rising line (§1: "pitch stepping up slightly"). The caller passes an index — the
/// card's position, the alert's slot — and the bank wraps it, so an index it did not
/// expect is a different pitch and never a crash.
///
/// **Reuse is deliberate, not laziness.** The three `shift*` grades take the three
/// verdict chords, and `destructive` takes `denied`: §9 authors no asset for them, and
/// inventing one would be inventing sound design the document did not sign off.
/// Writing the reuse here, once, is what stops it being re-decided per screen.
enum SoundBank {

  /// Every asset ships as 44.1 kHz mono 16-bit PCM WAV, written by
  /// `ios/scripts/render-sfx.swift`.
  static let fileExtension = "wav"

  /// The loop under an open shift (§9's last row). Not a cue: it is a *state*, so it
  /// has no `SocCue` and is started and stopped by `SoundService` rather than fired.
  static let roomTone = "room-tone"

  /// The files for a cue, in variant order. Empty means the cue is silent — which is
  /// not a case any cue is in today, and is why the switch below is total: a
  /// twenty-third cue stops the build here rather than going quiet in the player's
  /// ear.
  static func files(for cue: SocCue) -> [String] {
    switch cue {
    case .select: ["select"]
    case .holdTick: ["hold-tick"]
    // The mallet, three pitches cycling (§9).
    case .findingLand, .landCard: ["finding-land-1", "finding-land-2", "finding-land-3"]
    case .commitSoft: ["commit-soft"]
    case .file: ["file"]
    case .verdictGood: ["verdict-good"]
    case .verdictOff: ["verdict-off"]
    case .verdictWrong: ["verdict-wrong"]
    case .breachThud: ["breach-thud"]
    // The 16:00 stamp reads like the 08:00 one: the shift is a call about the shift.
    case .shiftClean: ["verdict-good"]
    case .shiftRough: ["verdict-off"]
    case .shiftBreached: ["verdict-wrong"]
    case .rankup: ["rankup"]
    case .denied: ["denied"]
    // A refusal and a destruction are the same knock; the difference is what the
    // screen says next, and §9 authors no second knock.
    case .destructive: ["denied"]
    // Behind the "Heartbeat sound" toggle, default off (§9). The lub and the dub are
    // one cue natively — `SoundService` plays the dub `tuning.heartbeat.dubOffsetMs`
    // after the lub, the way `CHPatternSpec` does.
    case .heartbeat: ["beat-lub", "beat-dub"]
    case .arrive: ["arrive"]
    case .queryStart: ["query-start"]
    case .tick: ["tick"]
    case .stamp: ["stamp"]
    case .ping: ["ping-1", "ping-2", "ping-3", "ping-4", "ping-5", "ping-6", "ping-7"]
    }
  }

  /// The file for a cue at `variant`, wrapped into range. `nil` only for a cue with
  /// no assets at all.
  static func file(for cue: SocCue, variant: Int = 0) -> String? {
    let names = files(for: cue)
    guard !names.isEmpty else { return nil }
    // `%` on a negative index is negative in Swift, and a negative index here would
    // be an out-of-bounds crash on a cue count nobody would ever look at again.
    let index = ((variant % names.count) + names.count) % names.count
    return names[index]
  }

  /// Every distinct file the bank can ask for, plus the room tone — what
  /// `SoundService` pre-loads, and what a test can check is actually in the bundle.
  static var allFiles: [String] {
    var seen: [String] = [roomTone]
    for cue in SocCue.allCases {
      for name in files(for: cue) where !seen.contains(name) { seen.append(name) }
    }
    return seen
  }
}
