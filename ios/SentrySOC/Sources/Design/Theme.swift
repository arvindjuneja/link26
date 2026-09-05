import SwiftUI
import SentryCore

/// The colour system — `DESIGN.md` §2.16, dark only.
///
/// This file and `Typography.swift` are the ONLY places a hex value or a font name
/// may appear (`SPEC.md` §4.6); `ios/scripts/verify.sh` greps for violations. The
/// ramps are the project's Tailwind v4 defaults, converted from their `oklch()`
/// definitions in `node_modules/tailwindcss/theme.css` so the two seats read as one
/// product rather than as two hand-picked palettes.
///
/// Dark only, deliberately: `UIUserInterfaceStyle = Dark` in the plist **and**
/// `.preferredColorScheme(.dark)` on the root, so there is no light flash on launch
/// and no second palette to keep honest.
enum Theme {

  // ── ground ─────────────────────────────────────────────────────────────────

  /// `--background` in `app/globals.css`. Also the `LaunchGround` asset, so the
  /// native splash and the first frame are the same colour and the launch is seamless.
  static let ground = hex(0x010409)
  /// Cards and the debrief panel.
  static let panel = hex(0x05080c)
  /// The sheet scrim, used at 85 %.
  static let scrim = hex(0x020408)
  /// `zinc-800/60` — every hairline in the deck.
  static let hairline = Zinc.z800.opacity(0.60)

  // ── text ───────────────────────────────────────────────────────────────────
  // Nothing meaningful is drawn below zinc-600.

  static let textPrimary = Zinc.z100
  static let textSecondary = Zinc.z300
  static let textTertiary = Zinc.z400
  static let textQuiet = Zinc.z500
  /// The floor. Dividers and disabled glyphs only — never a word the player must read.
  static let textDisabled = Zinc.z600

  // ── the ramps ──────────────────────────────────────────────────────────────

  enum Zinc {
    static let z100 = hex(0xf4f4f5)
    static let z200 = hex(0xe4e4e7)
    static let z300 = hex(0xd4d4d8)
    static let z400 = hex(0x9f9fa9)
    static let z500 = hex(0x71717b)
    static let z600 = hex(0x52525c)
    static let z700 = hex(0x3f3f46)
    static let z800 = hex(0x27272a)
    static let z900 = hex(0x18181b)
  }

  enum Rose {
    static let c200 = hex(0xffccd3)
    static let c300 = hex(0xffa1ad)
    static let c400 = hex(0xff637e)
    static let c500 = hex(0xff2056)
    static let c600 = hex(0xec003f)
  }

  enum Cyan {
    static let c200 = hex(0xa2f4fd)
    static let c300 = hex(0x53eafd)
    static let c400 = hex(0x00d3f2)
    static let c500 = hex(0x00b8db)
    static let c600 = hex(0x0092b8)
  }

  enum Emerald {
    static let c200 = hex(0xa4f4cf)
    static let c300 = hex(0x5ee9b5)
    static let c400 = hex(0x00d492)
    static let c500 = hex(0x00bc7d)
  }

  enum Amber {
    static let c200 = hex(0xfee685)
    static let c300 = hex(0xffd230)
    static let c500 = hex(0xfe9a00)
    static let c600 = hex(0xe17100)
  }

  enum Orange {
    static let c300 = hex(0xffb86a)
    static let c500 = hex(0xff6900)
    static let c600 = hex(0xf54900)
  }

  enum Fuchsia {
    static let c300 = hex(0xf4a8ff)
    static let c400 = hex(0xed6aff)
    static let c500 = hex(0xe12afb)
  }

  // ── the five semantic accents ──────────────────────────────────────────────
  // One meaning per hue, held across both seats. Never decorate with these.

  /// True Positive · breach risk · isolate.
  static let truePositive = Rose.c400
  /// False Positive · neutral action · system chrome.
  static let falsePositive = Cyan.c400
  /// Benign True Positive · a good call · progress · the primary CTA.
  static let benign = Emerald.c400
  /// Pressure · the Tier-2 hand-up.
  static let pressure = Amber.c500
  /// The Shift 4 crossover · a milestone · an unlock.
  static let crossover = Fuchsia.c400

  /// The accent a verdict is drawn in. The taxonomy teaches through colour (D5), so
  /// this mapping is the same everywhere a verdict appears.
  static func verdict(_ verdict: SocVerdict) -> Color {
    switch verdict {
    case .truePositive: truePositive
    case .falsePositive: falsePositive
    case .benignTruePositive: benign
    }
  }

  /// The accent a disposition is drawn in — `DISPOSITION_META[…].tone` in the web.
  static func disposition(_ disposition: Disposition) -> Color {
    switch disposition {
    case .closeFalsePositive: falsePositive
    case .closeBenign: benign
    case .escalateTier2: pressure
    case .escalateIRIsolate: truePositive
    }
  }

  /// A `RichSegment` / `DispositionMeta` / `severityMeta` / `handlerToneMeta` run.
  /// `Tone` is lenient (D10), so a tone authored after this build renders as body
  /// text rather than blanking the paragraph.
  static func tone(_ tone: Tone) -> Color {
    switch tone {
    case .cyan: Cyan.c300
    case .emerald: Emerald.c300
    case .rose: Rose.c300
    case .amber: Amber.c300
    case .fuchsia: Fuchsia.c300
    case .strong: textPrimary
    case .em: textSecondary
    case .muted: textQuiet
    default: textSecondary
    }
  }

  // ── the status ramp ────────────────────────────────────────────────────────

  /// One pressure band's four surfaces.
  ///
  /// `glowOpacity` is the inset edge-glow from the §2.14 table: ALERT .08 ·
  /// HUNT .14 · LOCKDOWN .22, and **nothing at CALM** — colour is spent as tension
  /// rises, and quiet is the reward.
  struct StatusPalette: Equatable, Sendable {
    let bar: Color
    let text: Color
    let border: Color
    let glow: Color
    let glowOpacity: Double
  }

  /// CALM **cyan** → ALERT amber → HUNT orange → LOCKDOWN rose.
  ///
  /// Deliberately *not* `--trace-calm: #10b981`, which is the **red seat's** token:
  /// design doc §10 requires a low-saturation cyan at CALM, "explicitly not bright
  /// green". Documented divergence, `DESIGN.md` §2.16.
  static func status(_ status: TraceStatus) -> StatusPalette {
    switch status {
    case .calm:
      StatusPalette(bar: Cyan.c500.opacity(0.60), text: Cyan.c300,
                    border: Cyan.c500.opacity(0.25), glow: Cyan.c500, glowOpacity: 0)
    case .alert:
      StatusPalette(bar: Amber.c500.opacity(0.70), text: Amber.c300,
                    border: Amber.c500.opacity(0.35), glow: Amber.c500, glowOpacity: 0.08)
    case .hunt:
      StatusPalette(bar: Orange.c500.opacity(0.80), text: Orange.c300,
                    border: Orange.c500.opacity(0.40), glow: Orange.c500, glowOpacity: 0.14)
    case .lockdown:
      StatusPalette(bar: Rose.c500.opacity(0.90), text: Rose.c300,
                    border: Rose.c500.opacity(0.50), glow: Rose.c500, glowOpacity: 0.22)
    }
  }

  /// How far non-focal panels dim at LOCKDOWN — the "tunnel vision" of §2.14.
  static let lockdownDimming: Double = 0.40

  // ── geometry ───────────────────────────────────────────────────────────────

  enum Radius {
    static let card: CGFloat = 10
    static let sheet: CGFloat = 16
    static let chip: CGFloat = 6
  }

  /// §2.2 thumb-zone rules: nothing interactive is smaller than this.
  enum Hit {
    static let minimum: CGFloat = 44
    static let row: CGFloat = 56
    static let primaryCTA: CGFloat = 56
    static let holdToFile: CGFloat = 64
    static let dispositionRow: CGFloat = 68
    static let gap: CGFloat = 8
  }

  // ── the one hex decoder ────────────────────────────────────────────────────

  /// sRGB from a 24-bit literal. Private on purpose: a hex value that is not one of
  /// the tokens above has no business existing.
  private static func hex(_ value: UInt32) -> Color {
    Color(
      .sRGB,
      red: Double((value >> 16) & 0xff) / 255,
      green: Double((value >> 8) & 0xff) / 255,
      blue: Double(value & 0xff) / 255,
      opacity: 1)
  }
}
