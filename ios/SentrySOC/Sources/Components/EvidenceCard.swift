import SwiftUI

/// A finding on the board — `DESIGN.md` §2.7, §2.8.
///
/// **`decisive`, `supporting`, `neutral` and `noise` render identically** (§5.6).
/// That is the mechanic, not an omission: over a 24-case corpus a weight badge would
/// let a player pattern-match the answer without reading the log, and weight is
/// therefore a debrief reveal only. This view takes no weight parameter at all, so
/// the rule cannot be broken by a screen that forgets it.
///
/// `detail` is **never clamped** — it is the puzzle (§2.7). The card grows; the list
/// scrolls.
struct EvidenceCard: View {
  let label: String
  let detail: String
  /// The debrief's `✓` / `○` marker — pulled or missed. `nil` during play, where a
  /// marker would be exactly the weight tell the design removes.
  var marker: (glyph: String, tone: Color)?

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if let marker {
        Text(marker.glyph)
          .font(Typography.metaStrong)
          .foregroundStyle(marker.tone)
          .padding(.top, 1)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text(label)
          .font(Typography.bodyMono)
          .foregroundStyle(Theme.Zinc.z200)
          .fixedSize(horizontal: false, vertical: true)

        Text(detail)
          .prose(Theme.textTertiary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .panelCard()
    .accessibilityElement(children: .combine)
  }
}

/// The dashed empty state — *"You can't make the call blind."* (§2.8). It is the one
/// place the deck tells the player what the game is about in the second person.
struct EvidenceEmptyState: View {
  let title: String
  let line: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(Typography.body)
        .foregroundStyle(Theme.textQuiet)
      Text(line)
        .font(Typography.body)
        .foregroundStyle(Theme.textTertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .panelCard(fill: .clear, stroke: Theme.Zinc.z700.opacity(0.7), dashed: true)
    .accessibilityElement(children: .combine)
  }
}

#Preview("EvidenceCard · a pull, a debrief line, the empty board") {
  VStack(spacing: 10) {
    EvidenceCard(
      label: "Parent is WINWORD.EXE",
      detail:
        "Lineage: WINWORD.EXE → cmd.exe → powershell.exe. A document spawned a shell — not how IT runs scripts.")

    EvidenceCard(
      label: "Decodes to a download-cradle",
      detail:
        "Decoded blob is an in-memory downloader: pull a follow-on script from a remote host and run it without writing to disk.",
      marker: (Glyph.correct, Theme.benign))

    EvidenceCard(
      label: "Immediate outbound to a fresh domain",
      detail: "Beacon to a domain registered three days ago. No proxy category, no business use.",
      marker: (Glyph.missed, Theme.textDisabled))

    EvidenceEmptyState(
      title: "Pull a source to surface findings.",
      line: "You can't make the call blind.")
  }
  .padding(20)
  .frame(width: 390)
  .background(Theme.ground)
}
