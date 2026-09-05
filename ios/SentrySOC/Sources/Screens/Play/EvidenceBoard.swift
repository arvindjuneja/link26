import SwiftUI
import SentryCore

/// The evidence board — the EVIDENCE half of the case (`DESIGN.md` §2.8,
/// `SPEC.md` §5.6).
///
/// **Every finding renders identically.** `decisive`, `supporting`, `neutral` and
/// `noise` are the same card, in the same colour, at the same weight — that is the
/// anti-recognition mechanic over a 24-case corpus, and it is why `EvidenceCard`
/// takes no weight parameter at all (C7). Weight is a debrief reveal.
///
/// Findings are grouped by **pull order**, not by the case's authoring order: the
/// board is a record of what the player chose to look at, so re-reading it is
/// re-reading their own investigation.
struct EvidenceBoard: View {
  let model: GameModel
  let socCase: SocCase
  /// §2.8: tapping a `FROM` header jumps back to that row in SOURCES.
  let onJumpToSource: (String) -> Void

  private var copy: CopyPack { model.content.copy }

  /// The sources the player has pulled *on this case*, in the order they pulled
  /// them, each with the findings it surfaced. A pulled source that answers nothing
  /// contributes no group — the board shows evidence, not receipts.
  private var groups: [(source: DataSource, findings: [SocEvidence])] {
    model.session.queried.compactMap { sourceID in
      let findings = socCase.findings(from: sourceID)
      guard !findings.isEmpty, let source = model.content.sourcesByID[sourceID] else {
        return nil
      }
      return (source, findings)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      let groups = groups
      let count = groups.reduce(0) { $0 + $1.findings.count }

      // `1 finding` on the first pull. The pair is data (P1-5): `chromePlurals`
      // carries both arms and `CopyPack.plural` picks one, so a screen never has to
      // author the singular S1 forbids it from authoring.
      PlayEyebrow(
        text: copy.chromeText("caseEvidenceEyebrow"),
        trailing: count > 0 ? copy.plural("caseFindingsCount", count) : nil)

      if groups.isEmpty {
        EvidenceEmptyState(
          title: copy.chromeText("caseEmptyBoard"),
          line: copy.chromeText("caseEmptyBoardBlind"))
      } else {
        ForEach(groups, id: \.source.id) { group in
          VStack(alignment: .leading, spacing: 8) {
            Button {
              onJumpToSource(group.source.id)
            } label: {
              HStack(spacing: 6) {
                Text(
                  copy.render(
                    copy.chromeText("caseEvidenceFrom"), ["source": group.source.label])
                )
                .trackedLabel(Theme.textDisabled, scale: 0.8)
                Text(Glyph.back)
                  .font(Typography.quietLog)
                  .foregroundStyle(Theme.textDisabled)
                  .rotationEffect(.degrees(180))
                Spacer(minLength: 0)
              }
              .minimumHitTarget()
            }
            .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
            .accessibilityHint(copy.chromeText("caseSourceHint"))
            .accessibilityIdentifier("evidence.fromHeader")

            ForEach(group.findings) { finding in
              EvidenceCard(label: finding.label, detail: finding.detail)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
