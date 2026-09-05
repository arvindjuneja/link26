import SentryCore
import SwiftUI

/// **The analyst kit** — `DESIGN.md` §2.3; `SPEC.md` §5.11. View `.kit`.
///
/// The cash sink: earn ¢ by completing work, spend it on gear that makes you faster.
/// One item today (the threat-intel feed, which pre-pulls the enrichment on every
/// case), and the sheet is built from `content.kit` so a second one costs no Swift.
///
/// **The purchase goes through `CareerRules.buyKit` and nowhere else** (§5.11). The
/// button is live even when the item is unaffordable, on purpose: `buyKit` returns the
/// career untouched, the reducer turns that into a `denied` cue and writes nothing, and
/// the player feels the refusal instead of pressing a control that ignores them. An
/// owned item has nothing left to buy, so it shows its state and no button at all.
struct KitSheet: View {
  let model: GameModel

  private var content: ContentPack { model.content }
  private var copy: CopyPack { content.copy }

  var body: some View {
    SheetChrome(
      eyebrow: copy.chromeText("kitTitle"),
      trailing: "\(copy.chromeText("cashUnit")) \(model.career.cash)"
    ) {
      VStack(alignment: .leading, spacing: 16) {
        Text(copy.chromeText("kitSpend")).prose(Theme.textTertiary)

        ForEach(content.kit) { item in
          row(item)
        }
      }
    } footer: {
      Dock(title: copy.chromeText("close"), tone: Theme.falsePositive) {
        model.send(.closeView)
      }
    }
    .accessibilityIdentifier("kit.root")
  }

  @ViewBuilder private func row(_ item: KitItem) -> some View {
    let owned = model.rules.owns(model.career, item.id)
    let affordable = model.career.cash >= item.cost

    VStack(alignment: .leading, spacing: 10) {
      Text(item.label)
        .font(Typography.rowTitle)
        .foregroundStyle(owned ? Theme.textTertiary : Theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text(item.blurb).prose(Theme.textTertiary)

      HStack(spacing: 10) {
        Spacer(minLength: 0)

        if owned {
          Chip(text: copy.chromeText("hubKitOwned"), tone: Theme.benign, style: .filled)
        } else {
          Button {
            model.buy(item)
          } label: {
            Text(copy.render(copy.chromeText("hubKitBuy"), ["cost": "\(item.cost)"]))
              .font(Typography.metaStrong)
              .tabularNumbers()
              .foregroundStyle(Theme.benign)
              .padding(.horizontal, 16)
              .frame(minHeight: Theme.Hit.minimum)
              .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                  .fill(Theme.benign.opacity(0.10))
              }
              .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                  .strokeBorder(Theme.benign.opacity(0.45), lineWidth: 1)
              }
              .contentShape(Rectangle())
          }
          .buttonStyle(PressableStyle(weight: .control, showsFill: false))
          // Not `.disabled`: the refusal is the reducer's, and a control that says
          // nothing back teaches nothing. Dimmed to say it will not take today.
          .opacity(affordable ? 1 : 0.45)
          .accessibilityIdentifier("kit.buy")
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .panelCard()
    .leadingRule(owned ? Theme.benign.opacity(0.55) : nil)
  }
}

#Preview("KitSheet") {
  KitSheet(model: GameModel())
    .frame(height: 420)
    .background(Theme.ground)
}
