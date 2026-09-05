import SwiftUI
import SentryCore

/// The call sheet — hold to file (`DESIGN.md` §2.9, `SPEC.md` §5.7).
///
/// The four rows are built from `copy.dispositionMeta` **in the exported
/// `dispositions` order**, so the FP-vs-Benign-TP taxonomy fix
/// (`docs/DECISION-soc-taxonomy.md`) propagates with no Swift edit at all: the
/// labels and the subtitles are data.
///
/// There is deliberately **no thin/thorough hint here** (§2.9) — grading the
/// investigation is the debrief's job, and a warning before the commit would turn a
/// judgement call into a hint system. And one `MAKE_CALL` per case is guaranteed by
/// the reducer's re-entrancy guard, not by disabling this button.
struct CallSheet: View {
  let model: GameModel

  /// Dismissing the presentation, not sending `CLOSE_VIEW`: `PhaseHost`'s sheet
  /// binding sends that itself when the sheet goes away, and sending it here too
  /// lands a second one with nothing open — which the reducer reads as the coach's
  /// "Got it" (S4).
  @Environment(\.dismiss) private var dismiss

  private var copy: CopyPack { model.content.copy }
  private var session: SessionState { model.session }
  private var socCase: SocCase? { session.currentCase(model.content) }

  var body: some View {
    SheetChrome(
      eyebrow: copy.chromeText("callSheetTitle"), tone: Theme.textTertiary
    ) {
      VStack(alignment: .leading, spacing: 18) {
        header
        dispositions
        keepInvestigating
      }
    } footer: {
      footer
    }
    .accessibilityIdentifier("sheet.call")
  }

  // MARK: - Parts

  @ViewBuilder private var header: some View {
    if let socCase {
      VStack(alignment: .leading, spacing: 6) {
        Text(socCase.alertTitle)
          .font(Typography.body)
          .foregroundStyle(Theme.textTertiary)
          .fixedSize(horizontal: false, vertical: true)

        // BLOCKED ON C1/F1: `callSheetMeta` is `{n} sources pulled · {t}m` with no
        // singular — `1 sources pulled` on a one-pull call. See `EvidenceBoard`.
        Text(
          copy.render(
            copy.chromeText("callSheetMeta"),
            [
              "n": String(pulledCount(socCase)),
              "t": String(session.timeSpentOnCurrentCase(model.content)),
            ])
        )
        .font(Typography.meta)
        .tabularNumbers()
        .foregroundStyle(Theme.textDisabled)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
    }
  }

  private var dispositions: some View {
    VStack(spacing: 8) {
      ForEach(model.content.dispositions, id: \.self) { disposition in
        let meta = copy.dispositionMeta[disposition]
        DispositionRow(
          label: meta?.label ?? disposition.rawValue,
          sub: meta?.sub ?? "",
          tone: Theme.disposition(disposition),
          isSelected: session.pendingDisposition == disposition,
          isDimmed: session.pendingDisposition != nil
            && session.pendingDisposition != disposition,
          action: { model.send(.pickDisposition(disposition)) })
      }
    }
  }

  /// §2.9: close the sheet, keep the selection. `CLOSE_VIEW` does exactly that —
  /// `pendingDisposition` is not cleared until a call is filed.
  private var keepInvestigating: some View {
    Button {
      dismiss()
    } label: {
      Text(copy.chromeText("callKeepInvestigating"))
        .font(Typography.meta)
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 8)
        .minimumHitTarget()
    }
    .buttonStyle(PressableStyle(weight: .control, cornerRadius: Theme.Radius.chip))
    .accessibilityIdentifier("call.keepInvestigating")
  }

  /// The stamp. It appears **only after a pick**, because a hold with nothing chosen
  /// has nothing to file.
  @ViewBuilder private var footer: some View {
    if let picked = session.pendingDisposition {
      let label = copy.dispositionMeta[picked]?.label ?? picked.rawValue
      HoldToFileButton(
        title: holdTitle(label),
        confirmTitle: copy.chromeText("callConfirm"),
        actionLabel: copy.chromeText("callFileAction"),
        tone: Theme.disposition(picked),
        holdEnabled: model.settings.holdToFile,
        onTick: { _ in model.feel(.holdTick) },
        onFile: { model.send(.makeCall(picked)) })
      .padding(.horizontal, 20)
      .padding(.top, 8)
      .padding(.bottom, 10)
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  private func holdTitle(_ label: String) -> String {
    model.settings.holdToFile
      ? copy.render(copy.chromeText("callHoldToFile"), ["disposition": label])
      : Play.cta(copy.chromeText("callFile"))
  }

  private func pulledCount(_ socCase: SocCase) -> Int {
    socCase.sources.filter { session.queried.contains($0.id) }.count
  }
}

// MARK: - One disposition

/// A 68 pt call row (§2.9): a 3 pt rule in the verdict's hue, the label, and the
/// taxonomy subtitle that is the whole teaching.
///
/// Selection is 8 % fill plus a 1 px ring; the other three dim to 55 % rather than
/// disappearing, because the comparison between the four is the decision.
struct DispositionRow: View {
  let label: String
  let sub: String
  let tone: Color
  let isSelected: Bool
  let isDimmed: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(label)
            .font(Typography.rowTitle)
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)

          Text(sub)
            .font(Typography.metaProse)
            .foregroundStyle(Theme.textQuiet)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 8)

        if isSelected {
          Text(Glyph.resolved)
            .font(Typography.metaStrong)
            .foregroundStyle(tone)
        }
      }
      .padding(.leading, 14 + Theme.ruleWidth)
      .padding(.trailing, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: Theme.Hit.dispositionRow, alignment: .leading)
      .panelCard(
        fill: isSelected ? tone.opacity(0.08) : Theme.panel,
        stroke: isSelected ? tone.opacity(0.85) : Theme.hairline)
      .leadingRule(tone.opacity(isSelected ? 1 : 0.75))
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
    .opacity(isDimmed ? 0.55 : 1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label). \(sub)")
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("call.disposition")
  }
}
