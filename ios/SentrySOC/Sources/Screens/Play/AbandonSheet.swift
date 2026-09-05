import SwiftUI
import SentryCore

/// Abandon shift (`DESIGN.md` §2.5, `SPEC.md` §5.3).
///
/// A deliberate loss, behind a deliberate confirmation: the queue's progress goes,
/// the career is not touched (R23). The snapshot is deleted by the reducer's
/// `.clearSession`, so the hub does not go on offering a board nobody is playing.
///
/// Both answers sit in the thumb arc, in the order a `confirmationDialog` uses them:
/// the destructive one above, and **"keep working" closest to the thumb**, because
/// the easiest target on the sheet should be the one that changes nothing.
///
/// **A sheet, not a `confirmationDialog` — open for the lead to ratify.** The two
/// documents disagree, and this is the only place where they do: `SPEC.md` §4.2 and
/// §5.3 call abandon a `.confirmationDialog`, while `DESIGN.md` §2.1's render map
/// and §2.5's wireframe both name an `AbandonSheet` (so does `SPEC.md`'s own C8 file
/// roster, §10 and §5.3's component list). The sheet form is what the machine can
/// actually express: `.abandon` is one of the seven `ViewID`s, `PhaseHost` presents
/// every non-full-screen `ViewID` as a sheet, and `QAJump`'s `abandon` destination
/// opens it with no board underneath — a `confirmationDialog` would have to hang off
/// a specific screen and would leave that `ViewID` rendering a placeholder. The
/// alternative the reviewer offered (move the confirm into `BoardSheet`) trades a
/// documented state for a local `@State` and breaks the QA jump, so it is not taken
/// unilaterally. If the lead prefers §4.2's letter, the `ViewID` has to go with it.
///
/// The reviewer's other objection to the sheet — that it was unreachable in normal
/// play — was a `PhaseHost` binding defect (a late `nil` write cleared the `.abandon`
/// the board had just opened), not a property of this form; with that guard in place
/// the board's `Abandon shift` control opens this sheet.
struct AbandonSheet: View {
  let model: GameModel

  /// See `SourceSheet`: `PhaseHost`'s sheet binding is what sends `CLOSE_VIEW`.
  @Environment(\.dismiss) private var dismiss
  private var copy: CopyPack { model.content.copy }

  var body: some View {
    SheetChrome(
      eyebrow: copy.chromeText("abandonTitle"), tone: Theme.truePositive
    ) {
      Text(copy.chromeText("abandonBody"))
        .prose(Theme.textTertiary)
    } footer: {
      VStack(spacing: 6) {
        Dock(
          title: copy.chromeText("abandonConfirm"),
          tone: Theme.truePositive,
          action: { model.send(.abandon) })

        Button {
          dismiss()
        } label: {
          Text(copy.chromeText("abandonCancel"))
            .font(Typography.rowTitle)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: Theme.Hit.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(weight: .control, showsFill: false))
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .accessibilityIdentifier("abandon.cancel")
      }
    }
    .accessibilityIdentifier("sheet.abandon")
  }
}
