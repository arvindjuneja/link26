import SentryCore
import SwiftUI

/// Tone-run prose — `SPEC.md` D5, §5.2, §10 C7 #4.
///
/// The taxonomy, the severity paragraph and the ladder ship as `[RichSegment]` and
/// are folded here into **one** `AttributedString` with per-run `foregroundColor`.
/// One `Text`, not a `HStack` of them, so the paragraph wraps and justifies as
/// prose — a run-per-`Text` layout breaks mid-sentence at every colour change and
/// is the reason the web's colour runs could not simply be lifted.
///
/// The colour is the teaching. "True Positive" in rose next to "False Positive" in
/// cyan is the DEF-A lesson the taxonomy playtest showed players were missing when
/// the three verdicts were rendered in one grey.
struct RichTextView: View {
  let segments: [RichSegment]
  var font: Font = Typography.body
  var baseColor: Color = Theme.textSecondary
  var lineSpacing: CGFloat = Typography.bodyLineSpacing

  var body: some View {
    Text(attributed)
      .lineSpacing(lineSpacing)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var attributed: AttributedString {
    var out = AttributedString()
    for segment in segments {
      var run = AttributedString(segment.text)
      if let tone = segment.tone {
        run.foregroundColor = Theme.tone(tone)
        let emphasis = Theme.toneEmphasis(tone)
        var resolved = font
        if emphasis.bold { resolved = resolved.bold() }
        if emphasis.italic { resolved = resolved.italic() }
        run.font = resolved
      } else {
        run.foregroundColor = baseColor
        run.font = font
      }
      out.append(run)
    }
    return out
  }
}

/// A taxonomy row: a 3 pt verdict rule, the verdict, and what it means (§2.4). The
/// exported taxonomy paragraph carries the same words; this is the version with the
/// rules on it, for the briefing panel.
struct TaxonomyRow: View {
  let verdict: String
  let meaning: String
  let tone: Color

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        .fill(tone)
        .frame(width: Theme.ruleWidth)

      VStack(alignment: .leading, spacing: 3) {
        Text(verdict)
          .font(Typography.rowTitle)
          .foregroundStyle(tone)
        Text(meaning)
          .prose(Theme.textTertiary)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
  }
}

#Preview("RichTextView · the exported taxonomy and ladder") {
  let copy = ContentPack.bundled.copy

  return ScrollView {
    VStack(alignment: .leading, spacing: 22) {
      Text("TAXONOMY").trackedLabel()
      RichTextView(segments: copy.intro.taxonomy)

      Text("SEVERITY").trackedLabel()
      RichTextView(segments: copy.intro.severity)

      Text("THE ROWS").trackedLabel()
      VStack(alignment: .leading, spacing: 14) {
        TaxonomyRow(
          verdict: "True Positive", meaning: "a real threat", tone: Theme.truePositive)
        TaxonomyRow(
          verdict: "False Positive", meaning: "the detection misfired",
          tone: Theme.falsePositive)
        TaxonomyRow(
          verdict: "Benign True Positive",
          meaning: "the detection was right — the activity was authorized",
          tone: Theme.benign)
      }

      Text("THE LADDER").trackedLabel()
      RichTextView(segments: copy.ladder.body)
    }
    .padding(24)
  }
  .frame(width: 390)
  .background(Theme.ground)
}
