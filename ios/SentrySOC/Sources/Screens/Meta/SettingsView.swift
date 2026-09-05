import SentryCore
import SwiftUI

/// Where a drill-down goes. Two rows deep, which is exactly §5.11's
/// Settings → About → Licences.
enum MetaRoute: Hashable {
  case about
  case licences
}

/// **Settings** — `DESIGN.md` §2.13; `SPEC.md` §5.11. View `.settings`.
///
/// **The one `NavigationStack` in the app** (D16). Everywhere else a stack would hand
/// the player a swipe-back out of a completed debrief into the call sheet; here a
/// drill-down is exactly what Settings → About → Licences is, and swipe-back is the
/// right gesture. Nothing in the shift loop is reachable from inside it.
///
/// Every switch goes through `GameModel.settingBinding(_:)` → `send(.setSetting)` →
/// the reducer → `Effect.setFlag`, so a `Toggle` writes storage no more directly than
/// a queue row does.
struct SettingsView: View {
  let model: GameModel

  @State private var path: [MetaRoute] = []
  @State private var confirmingReset = false
  /// D19: five taps on the version line. Debug-only state; the row it reveals does
  /// not compile into Release.
  @State private var versionTaps = 0
  @State private var showingQAJumps = false

  private var content: ContentPack { model.content }
  private var copy: CopyPack { content.copy }

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          saveNotice
          feelSection
          deskSection
          aboutSection
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
      }
      .scrollBounceBehavior(.basedOnSize)
      .background(Theme.ground.ignoresSafeArea())
      .metaNavigationChrome(copy.chromeText("settingsTitle")) {
        Button(copy.chromeText("close")) { model.send(.closeView) }
          .font(Typography.meta)
          .foregroundStyle(Theme.falsePositive)
          .accessibilityIdentifier("settings.close")
      }
      .navigationDestination(for: MetaRoute.self) { route in
        switch route {
        case .about: AboutScreen(model: model)
        case .licences: LicencesScreen(model: model)
        }
      }
    }
    // **An `.alert`, not a `.confirmationDialog`** (P1-7). Measured on this
    // simulator, not assumed: inside a sheet, iOS 26 presents a `confirmationDialog`
    // as the compact centred dialog and that presentation **omits a `.cancel`-role
    // button entirely** — the system takes a tap on the dimmed ground as the cancel.
    // A destructive confirmation whose only way out is an undiscoverable tap outside
    // is not a confirmation. The previous fix here was a second button with no role,
    // which survived the presentation but left the deck relying on a workaround for a
    // system control that has a correct one: `.alert` draws both buttons in both
    // presentations, gives the destructive role its red, and gives Cancel the bold
    // default and the Escape/outside-tap behaviour for free.
    .alert(
      copy.chromeText("settingsResetTitle"),
      isPresented: $confirmingReset
    ) {
      Button(copy.chromeText("settingsResetConfirm"), role: .destructive) {
        model.resetCareer()
      }
      Button(copy.chromeText("settingsCancel"), role: .cancel) {}
    } message: {
      Text(copy.chromeText("settingsResetBody"))
    }
    .accessibilityIdentifier("settings.root")
  }

  // MARK: - The one-shot save notice

  /// `SaveStore` sets this aside when `career.json` did not decode and the backup did
  /// not either. Shown once, then acknowledged — the file is kept on the device.
  @ViewBuilder private var saveNotice: some View {
    if model.saveWasCorrupt {
      VStack(alignment: .leading, spacing: 10) {
        Text(copy.chromeText("settingsSaveNotice")).prose(Theme.textSecondary)
        Button(copy.chromeText("close")) { model.acknowledgeSaveNotice() }
          .font(Typography.meta)
          .foregroundStyle(Theme.pressure)
          .frame(minHeight: Theme.Hit.minimum)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .panelCard(fill: Theme.panel, stroke: Theme.pressure.opacity(0.35))
      .leadingRule(Theme.pressure)
      .accessibilityIdentifier("settings.saveNotice")
    }
  }

  // MARK: - FEEL

  private var feelSection: some View {
    MetaSection(eyebrow: copy.chromeText("settingsFeel")) {
      MetaPanel {
        toggleRow(copy.chromeText("settingsHaptics"), .haptics)
        MetaDivider()
        toggleRow(copy.chromeText("settingsHoldToFile"), .holdToFile)
        MetaDivider()
        toggleRow(copy.chromeText("settingsCoaching"), .coaching)
        MetaDivider()
        // Motion is the system's to decide (§2.14 / D18): Reduce Motion stops the
        // deck's visual motion and deliberately does NOT touch haptics, so there is
        // nothing here to switch — only something to state.
        MetaRow(title: copy.chromeText("settingsMotion")) {
          Text(copy.chromeText("settingsMotionValue"))
            .font(Typography.meta)
            .foregroundStyle(Theme.textDisabled)
        }
      }
    }
  }

  private func toggleRow(_ title: String, _ key: SettingKey) -> some View {
    MetaRow(title: title) {
      Toggle(title, isOn: model.settingBinding(key))
        .labelsHidden()
        .tint(Theme.benign)
        .accessibilityIdentifier("settings.toggle")
    }
  }

  // MARK: - DESK

  private var deskSection: some View {
    MetaSection(eyebrow: copy.chromeText("settingsDesk")) {
      MetaPanel {
        MetaRow(title: deskLine, titleColor: Theme.textPrimary)

        MetaDivider()

        // §5.11: destructive, so it is a text button **outside the thumb arc** — it
        // sits high in the read zone, at the top of a scroll region, and it is behind
        // a confirmation. Nothing about it is one thumb-stretch away.
        Button {
          confirmingReset = true
        } label: {
          MetaRow(title: copy.chromeText("settingsReset"), titleColor: Theme.truePositive) {
            EmptyView()
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("settings.reset")
      }
    }
  }


  private var deskLine: String {
    copy.render(
      copy.chromeText("settingsDeskLine"),
      [
        "rank": model.rules.rankFor(model.career.standing).label,
        "standing": "\(model.career.standing)",
        "cash": "\(model.career.cash)",
        "clean": "\(model.career.shiftsCleaned)",
      ])
  }

  // MARK: - ABOUT (and the QA reveal)

  private var aboutSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      // The version line, and the five taps that reveal the jumps (§5.11). The
      // gesture is on the line itself and not on the section: an `onTapGesture`
      // wrapped around the About row would eat the tap that opens it.
      Text(versionLine)
        .trackedLabel(Theme.textQuiet)
        .frame(maxWidth: .infinity, minHeight: Theme.Hit.minimum, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { registerVersionTap() }
        .accessibilityIdentifier("settings.version")

      MetaPanel {
        NavigationLink(value: MetaRoute.about) {
          MetaRow(title: copy.chromeText("hubAbout"), titleColor: Theme.textSecondary) {
            Text(Glyph.forward)
              .font(Typography.meta)
              .foregroundStyle(Theme.textQuiet)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("settings.about")
      }

      qaJumps
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var versionLine: String {
    copy.render(copy.chromeText("aboutEyebrow"), ["version": MetaID.version])
  }

  private func registerVersionTap() {
    #if SENTRY_QA
      versionTaps += 1
      if versionTaps >= 5 {
        versionTaps = 0
        withAnimation(Motion.gated(Motion.screenPush)) { showingQAJumps.toggle() }
      }
    #endif
  }

  /// The screen-jump row `ios/scripts/shots.sh` drives (D19). Compiled **only** under
  /// `SENTRY_QA`, which `project.yml` sets on Debug alone, so the release guard can
  /// prove its absence by grepping the Release binary for the launch argument.
  @ViewBuilder private var qaJumps: some View {
    #if SENTRY_QA
      if showingQAJumps {
        MetaPanel {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(MetaID.qaScreens, id: \.self) { name in
              Button(name) { jump(to: name) }
                .font(Typography.meta)
                .foregroundStyle(Theme.crossover)
                .frame(maxWidth: .infinity, minHeight: Theme.Hit.minimum, alignment: .leading)
                .contentShape(Rectangle())
            }
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 6)
        }
        .accessibilityIdentifier("settings.qaJumps")
        .transition(.opacity)
      }
    #endif
  }

  #if SENTRY_QA
    private func jump(to name: String) {
      guard let destination = QAJump.destination(named: name, content: content) else { return }
      model.send(.closeView)
      model.applyQAJump(destination)
    }
  #endif
}

// MARK: - About

/// **About** — the fiction disclaimer, privacy, the promise, and the credits.
///
/// The fiction block is the **same** block as the first-run gate (§5.11) — the two
/// exported keys are byte-identical and `MetaComposition` asserts it in DEBUG, so
/// they cannot drift apart into two different disclaimers.
private struct AboutScreen: View {
  let model: GameModel

  @State private var showingPrivacy = false

  private var copy: CopyPack { model.content.copy }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Amber, not rose: §2.16 spends rose on a true positive, and a disclaimer
        // that borrows the breach hue claims an authority it does not have. Same
        // choice as the first-run gate, which prints the same block.
        block(copy.chromeText("aboutFictionTitle"), copy.about.fiction, tone: Theme.pressure)

        // **5.1.1(i) is satisfied by this screen, not by the link** (P1-4). The policy
        // summary is exported copy and prints here whether or not the network, the
        // host or `SFSafariViewController` cooperate — an app that collects nothing
        // should be able to say so without asking to go online first. The link is
        // corroboration; the address under it is printed as text so a reviewer with a
        // dead link can still read the URL and open it themselves.
        VStack(alignment: .leading, spacing: 12) {
          block(copy.chromeText("aboutPrivacyTitle"), copy.about.privacy)

          // The app's ONLY outbound link, and an `SFSafariViewController` rather than
          // a `WKWebView` on purpose: an embedded browser alone forces a 16+ age
          // rating (§8), and leaving the app to Safari loses the session.
          Button {
            showingPrivacy = true
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 8) {
                Text(copy.chromeText("aboutPrivacyLink"))
                  .font(Typography.meta)
                  .foregroundStyle(Theme.falsePositive)
                Spacer(minLength: 8)
              }
              // An address, not copy (`MetaID`) — and legible rather than hidden
              // behind a tap, which is the whole point of printing it.
              Text(MetaID.privacyPolicy)
                .font(Typography.quietLog)
                .foregroundStyle(Theme.textDisabled)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Hit.minimum, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(PressableStyle())
          .accessibilityIdentifier("about.privacyLink")
        }

        block(copy.chromeText("aboutPromiseTitle"), copy.about.promise, tone: Theme.benign)

        VStack(alignment: .leading, spacing: 12) {
          block(copy.chromeText("aboutCreditsTitle"), copy.about.credits)

          MetaPanel {
            NavigationLink(value: MetaRoute.licences) {
              MetaRow(title: copy.chromeText("licencesTitle"), titleColor: Theme.textSecondary) {
                Text(Glyph.forward)
                  .font(Typography.meta)
                  .foregroundStyle(Theme.textQuiet)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("about.licences")
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 20)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(Theme.ground.ignoresSafeArea())
    // §2.13 heads this screen with the build it is about — `About · SENTRY — SOC
    // 1.0 (1)` — not with the name of its first block.
    .metaNavigationChrome(
      copy.render(copy.chromeText("aboutEyebrow"), ["version": MetaID.version]))
    .sheet(isPresented: $showingPrivacy) {
      if let safari = SafariView.make(MetaID.privacyPolicy) {
        safari.ignoresSafeArea()
      }
    }
    .accessibilityIdentifier("about.root")
  }

  private func block(_ title: String, _ body: String, tone: Color = Theme.textQuiet) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).trackedLabel(tone)
      Text(body).prose(Theme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Licences

/// **Licences** — MITRE ATT&CK® attribution and both SIL Open Font Licence texts,
/// read out of the two `.txt` files `project.yml` ships beside the six TTFs.
///
/// The licence text is never transcribed into Swift: it is the shipped file, so what
/// a reviewer reads here is byte-for-byte what the fonts came with. Each section's
/// heading is that file's own first line — the copyright notice — for the same
/// reason: a font swap cannot leave a stale attribution behind.
private struct LicencesScreen: View {
  let model: GameModel

  private var copy: CopyPack { model.content.copy }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        Text(copy.chromeText("aboutCreditsTitle")).trackedLabel(Theme.textQuiet)
        Text(copy.about.credits).prose(Theme.textSecondary)

        ForEach(MetaID.Licence.allCases) { licence in
          let text = Self.text(of: licence)
          VStack(alignment: .leading, spacing: 10) {
            // Not `trackedLabel()`: Space Grotesk's copyright line is 100 characters
            // and carries a URL, and a tracked uppercase run clamped to one line
            // turns it into `COPYRIGHT 2020 THE SPACE GROTESK…`. Attribution that
            // ellipsises is not attribution.
            Text(Self.heading(of: text))
              .font(Typography.metaStrong)
              .foregroundStyle(Theme.textTertiary)
              .fixedSize(horizontal: false, vertical: true)
            Text(Self.body(of: text))
              .font(Typography.quietLog)
              .foregroundStyle(Theme.textQuiet)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
          .panelCard()
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 20)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(Theme.ground.ignoresSafeArea())
    .metaNavigationChrome(copy.chromeText("licencesTitle"))
    .accessibilityIdentifier("licences.root")
  }

  private static func text(of licence: MetaID.Licence) -> String {
    guard
      let url = Bundle.main.url(
        forResource: licence.rawValue, withExtension: MetaID.licenceExtension),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      assertionFailure("\(licence.rawValue) is not in the bundle — check project.yml Resources")
      return ""
    }
    return text
  }

  /// The copyright notice — the file's first non-empty line.
  ///
  /// Split on `isNewline`, never on `"\n"`: both OFL files ship with **CRLF**
  /// endings, and Swift folds `\r\n` into a single `Character`, so
  /// `firstIndex(of: "\n")` finds nothing at all and the "first line" silently
  /// becomes the whole 93-line licence. It shipped that way once and the screenshot
  /// is what caught it.
  private static func heading(of text: String) -> String {
    text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
  }

  private static func body(of text: String) -> String {
    guard let firstBreak = text.firstIndex(where: \.isNewline) else { return text }
    return String(text[text.index(after: firstBreak)...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

// MARK: - Navigation chrome

extension View {

  /// The inline nav bar the three settings screens share: the deck's tracked eyebrow
  /// in the principal slot and the ground painted behind it, so the system bar does
  /// not float a translucent grey strip over `#010409`.
  ///
  /// The **system** back control is kept deliberately. This is the one place a stack
  /// is correct (D16) and the interactive swipe-back is the point of having it; a
  /// hand-drawn `‹` header that disables that gesture would be a worse screen with a
  /// better glyph.
  func metaNavigationChrome(_ title: String) -> some View {
    metaNavigationChrome(title, trailing: { EmptyView() })
  }

  func metaNavigationChrome<Trailing: View>(
    _ title: String, @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    self
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Theme.ground, for: .navigationBar)
      .toolbarBackgroundVisibility(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text(title).trackedLabel(Theme.textTertiary)
        }
        ToolbarItem(placement: .topBarTrailing) { trailing() }
      }
  }
}

#Preview("Settings") {
  SettingsView(model: GameModel())
}
