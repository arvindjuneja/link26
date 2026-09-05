import Foundation
import SentryCore

#if SENTRY_QA

  /// Screen jumps for the screenshot runs and for hand QA (D19).
  ///
  /// Compiled **only** under the `SENTRY_QA` compilation condition, which
  /// `project.yml` sets on the **Debug** configuration alone. A named condition is
  /// greppable, which is the point: the release guard proves the jump is absent by
  /// looking for the launch-argument literal below in the Release binary, with the
  /// Debug binary as a positive control (B7).
  ///
  /// **Where the guard must look, measured on Xcode 26.2:** `ENABLE_DEBUG_DYLIB`
  /// defaults to `YES`, so a Debug build puts the app's code in
  /// `SentrySOC.app/SentrySOC.debug.dylib` and leaves a ~40 KB stub as
  /// `SentrySOC.app/SentrySOC`. `strings` on the stub finds nothing and the positive
  /// control fails as "grep broken" even though the jump is compiled in. Release
  /// builds have no debug dylib, so the guard reads:
  ///
  /// - positive control (Debug): `strings SentrySOC.app/SentrySOC.debug.dylib`
  /// - the assertion (Release):  `strings SentrySOC.app/SentrySOC`
  ///
  /// Usage: launch with `-SentryQAScreen debrief`.
  enum QAJump {

    /// The launch-argument literal B7's release guard greps for. It exists in
    /// exactly one place, inside this `#if`.
    static let launchArgument = "-SentryQAScreen"

    /// Where a named screen puts the session.
    struct Destination: Sendable, Hashable {
      var phase: Phase
      var view: ViewID?
      /// Jumps into the shift need a board; this is the shift to open.
      var shiftID: String?
    }

    /// Every jumpable name. Kept flat and lowercase so a shell script can pass one
    /// without quoting.
    ///
    /// Both ids are **derived from the bundle**, never spelled: a content rename
    /// used to leave the jump pointing at a shift that no longer starts, and the
    /// symptom was a blank hub with no diagnostic. Now it trips the assertion below.
    static func destination(named name: String, content: ContentPack) -> Destination? {
      let shiftID = firstShiftID(content)
      let sourceID = firstSourceID(content)

      switch name.lowercased() {
      case "hub": return Destination(phase: .hub, view: nil, shiftID: nil)
      case "kit": return Destination(phase: .hub, view: .kit, shiftID: nil)
      case "settings": return Destination(phase: .hub, view: .settings, shiftID: nil)
      case "firstrun": return Destination(phase: .hub, view: .firstRun, shiftID: nil)
      default: break
      }

      // Everything below opens a board, so a bundle with no shifts has no answer.
      guard let shiftID else {
        assertionFailure("content.shifts is empty — no QA jump can open a board")
        return nil
      }

      switch name.lowercased() {
      case "intro", "briefing": return Destination(phase: .briefing, view: nil, shiftID: shiftID)
      case "case", "investigating": return Destination(phase: .investigating, view: nil, shiftID: shiftID)
      case "board": return Destination(phase: .investigating, view: .board, shiftID: shiftID)
      case "source":
        guard let sourceID else {
          assertionFailure("the first alert of \(shiftID) has no sources — `source` cannot jump")
          return nil
        }
        return Destination(phase: .investigating, view: .source(sourceID), shiftID: shiftID)
      case "call": return Destination(phase: .investigating, view: .call, shiftID: shiftID)
      case "abandon": return Destination(phase: .investigating, view: .abandon, shiftID: shiftID)
      case "debrief": return Destination(phase: .debrief(readOnly: false), view: nil, shiftID: shiftID)
      case "debrief-readonly": return Destination(phase: .debrief(readOnly: true), view: nil, shiftID: shiftID)
      case "summary", "complete": return Destination(phase: .complete, view: nil, shiftID: shiftID)
      case "rankup", "milestone": return Destination(phase: .milestone, view: nil, shiftID: shiftID)
      default: return nil
      }
    }

    /// The name passed on this launch, if any.
    static func requestedName(
      arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> String? {
      guard let index = arguments.firstIndex(of: launchArgument),
            arguments.index(after: index) < arguments.endIndex
      else { return nil }
      return arguments[arguments.index(after: index)]
    }

    static func requestedDestination(
      content: ContentPack,
      arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Destination? {
      guard let name = requestedName(arguments: arguments) else { return nil }
      return destination(named: name, content: content)
    }

    /// Shift 1 — the only board every jump can rely on, because it is first on the
    /// ladder and unlocks at standing 0.
    static func firstShiftID(_ content: ContentPack) -> String? {
      content.shifts.first?.id
    }

    /// The first source of Shift 1's first alert, so the `source` jump opens a sheet
    /// with something in it.
    static func firstSourceID(_ content: ContentPack) -> String? {
      guard let caseID = content.shifts.first?.caseIds.first else { return nil }
      return content.case(caseID)?.sourceIds.first
    }
  }

#endif
