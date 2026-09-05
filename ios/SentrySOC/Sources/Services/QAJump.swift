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
  ///
  /// **Every jump is a list of actions, not a pose** (C5). A destination is reached
  /// by *playing* the board through the reducer — start, begin, pull, call — so a QA
  /// screenshot shows a session the machine actually produced: the debrief jump has
  /// a real `CallGrade`, the summary jump has a real settlement and a real payout,
  /// and a screen that reads a field the reducer never fills fails here rather than
  /// on a reviewer's device.
  enum QAJump {

    /// The launch-argument literal B7's release guard greps for. It exists in
    /// exactly one place, inside this `#if`.
    static let launchArgument = "-SentryQAScreen"

    /// Where a named screen puts the session, and how to get there.
    struct Destination: Sendable, Hashable {
      var name: String
      /// What the jump claims to reach — checked against the session afterwards.
      var phase: Phase
      var view: ViewID?
      /// The actions that get there, in order. Every one of the seventeen.
      var actions: [SocAction]
    }

    /// Every jumpable name. Kept flat and lowercase so a shell script can pass one
    /// without quoting.
    ///
    /// Every id is **derived from the bundle**, never spelled: a content rename used
    /// to leave the jump pointing at a shift that no longer starts, and the symptom
    /// was a blank hub with no diagnostic. Now it trips the assertions below.
    static func destination(named name: String, content: ContentPack) -> Destination? {
      let key = name.lowercased()

      switch key {
      case "hub": return Destination(name: key, phase: .hub, view: nil, actions: [.toHub])
      case "kit", "settings", "firstrun":
        let view: ViewID = key == "kit" ? .kit : (key == "settings" ? .settings : .firstRun)
        return Destination(name: key, phase: .hub, view: view, actions: [.toHub, .openView(view)])
      default: break
      }

      // Everything below opens a board, so a bundle with no shifts has no answer.
      guard let shift = firstShift(content) else {
        assertionFailure("content.shifts is empty — no QA jump can open a board")
        return nil
      }
      // Standing enough to pass `isUnlocked` is not needed: the first board is the
      // one that opens at 0 (`unlockStanding == 0`), which the ladder guarantees.
      assert(shift.unlockStanding == 0, "the first board no longer opens at standing 0")

      let open: [SocAction] = [.startShift(shift.id), .begin, .closeView]

      switch key {
      case "intro", "briefing":
        return Destination(name: key, phase: .briefing, view: nil, actions: [.startShift(shift.id)])
      case "case", "investigating":
        return Destination(name: key, phase: .investigating, view: nil, actions: open)
      case "board":
        return Destination(
          name: key, phase: .investigating, view: .board,
          actions: [.startShift(shift.id), .begin])
      case "source":
        guard let sourceID = firstSourceID(content) else {
          assertionFailure("the first alert of \(shift.id) has no sources — `source` cannot jump")
          return nil
        }
        return Destination(
          name: key, phase: .investigating, view: .source(sourceID),
          actions: open + [.openView(.source(sourceID))])
      case "call":
        // The call sheet is guarded on revealed evidence (SocConsole.tsx:495), so the
        // jump has to earn it — which is the point of playing rather than posing.
        guard let revealing = revealingSourceID(content) else {
          assertionFailure("the first alert of \(shift.id) has no evidence — `call` cannot jump")
          return nil
        }
        return Destination(
          name: key, phase: .investigating, view: .call,
          actions: open + [.pullSource(revealing), .openView(.call)])
      case "abandon":
        return Destination(
          name: key, phase: .investigating, view: .abandon,
          actions: open + [.openView(.abandon)])
      case "debrief":
        return Destination(
          name: key, phase: .debrief(readOnly: false), view: nil,
          actions: open + investigateAndCall(content, shift.caseIds.first))
      case "debrief-readonly":
        guard let first = shift.caseIds.first else { return nil }
        return Destination(
          name: key, phase: .debrief(readOnly: true), view: nil,
          actions: open + investigateAndCall(content, first) + [.nextCase, .viewResult(first)])
      case "summary", "complete":
        return Destination(
          name: key, phase: .complete, view: nil, actions: open + playOut(shift, content))
      case "rankup", "milestone":
        // Lands on `.milestone` only if the played board earned a rank-up or an
        // unlock (§5.9). From a fresh career the first board does both.
        return Destination(
          name: key, phase: .milestone, view: nil,
          actions: open + playOut(shift, content) + [.nextCase])
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
      guard let destination = destination(named: name, content: content) else {
        assertionFailure("-SentryQAScreen \(name) is not a jumpable screen")
        return nil
      }
      return destination
    }

    // MARK: - Derived from the bundle

    /// Shift 1 — the only board every jump can rely on, because it is first on the
    /// ladder and unlocks at standing 0.
    static func firstShift(_ content: ContentPack) -> ShiftDef? { content.shifts.first }

    /// The first source of Shift 1's first alert, so the `source` jump opens a sheet
    /// with something in it.
    static func firstSourceID(_ content: ContentPack) -> String? {
      guard let caseID = firstShift(content)?.caseIds.first else { return nil }
      return content.case(caseID)?.sourceIds.first
    }

    /// A source of the first alert that actually carries a finding — the one the
    /// call sheet's guard will accept.
    static func revealingSourceID(_ content: ContentPack) -> String? {
      guard let caseID = firstShift(content)?.caseIds.first else { return nil }
      return content.case(caseID)?.evidence.first?.sourceId
    }

    /// Pull something that reveals a finding, then file the ideal call — so the
    /// debrief a jump lands on is a *good* one and the screenshot shows the stamp,
    /// the outcome and a moved meter.
    private static func investigateAndCall(
      _ content: ContentPack, _ caseID: String?
    ) -> [SocAction] {
      guard let caseID, let socCase = content.case(caseID) else { return [] }
      let pulls = socCase.evidence.prefix(2).map { SocAction.pullSource($0.sourceId) }
      return pulls + [.makeCall(socCase.correctDisposition)]
    }

    /// Work every alert of the board properly and walk off the end of it.
    ///
    /// The key sources are pulled before each call on purpose: a blind call can
    /// never grade `clean` (the grade rule counts blind calls), so a summary jump
    /// that skipped them would always screenshot `rough`, and the milestone jump
    /// behind it would never reach a rank-up. Pulling them makes the QA board the
    /// one a competent player would have played.
    private static func playOut(_ shift: ShiftDef, _ content: ContentPack) -> [SocAction] {
      shift.caseIds.flatMap { caseID -> [SocAction] in
        guard let socCase = content.case(caseID) else { return [] }
        return socCase.keySourceIds.map { SocAction.pullSource($0) }
          + [.makeCall(socCase.correctDisposition), .nextCase]
      }
    }
  }

#endif
