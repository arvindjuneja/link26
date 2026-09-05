// ─────────────────────────────────────────────────────────────────────────────
//  TEMPORARY — REPLACED BY `SentryCore.Session` / `SentryCore.Feel` IN C5.
//
//  Every declaration below is a placeholder for a type C5 owns and ships inside the
//  package (`SPEC.md` §1, §3.2, §3.3, D9):
//
//      Phase · ViewID · SessionState · SocAction · SettingKey · Effect
//                                              → Sources/SentryCore/Session/
//      SocCue · HeartbeatPlan · heartbeatPlan  → Sources/SentryCore/Feel/
//      reduce(_:_:content:career:)             → Session/SessionReducer.swift
//
//  It exists so C6 can ship the shell — `GameModel.send(_:)`, `EffectRunner`,
//  `PhaseHost`, `ScreenRegistry` — against a real surface instead of against
//  nothing, and so C7/C8/C9/C10 compile against the names C5 will publish. Shapes
//  are copied from **`SPEC.md` §3.3 verbatim** so the swap is a deletion, not a
//  refactor.
//
//  **When C5 lands: DELETE THIS WHOLE FILE.** Nothing else in `Sources/App`,
//  `Sources/State` or `Sources/Services` declares any of these names.
//
//  **Why that deletion has to be an acceptance item, not a habit.** Swift resolves an
//  unqualified name to the CURRENT module first, so once C5 publishes the public
//  versions inside `SentryCore` these declarations keep winning and the app keeps
//  calling this reducer — with no compile error anywhere. The failure would be
//  silent. `SessionStubTripwireTests` is the loud half: it asks the runtime whether
//  `SentryCore.SessionState` exists yet and fails, naming this file, the moment it
//  does. C5's paths_owned does not currently include this directory, so the lead has
//  to grant the deletion (reported as a request by C6).
//
//  Grading is done by C3's real `SOCEngine` — `MAKE_CALL` calls `applyCall`, so the
//  meters, the ordered results and the shift status are all `SentryCore`'s
//  arithmetic and never the app's. What is deliberately NOT here is C5's own work:
//  the graded `last` result carried on `SessionState`, the coach cursor, the kit
//  pre-pull (`initialQueried`), and `complete → milestone`, which needs the rank-up
//  the settlement produced.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SentryCore

// MARK: - Phase and view (DESIGN.md §2.1, SPEC.md §3.3)

/// Where you are in the shift. `readOnly` rides on `.debrief` because a debrief
/// opened from the board's done rows must return whence it came (Appendix A G5).
nonisolated enum Phase: Codable, Sendable, Hashable {
  case hub, briefing, investigating
  case debrief(readOnly: Bool)
  case complete, milestone

  /// For the DEBUG jump list and the placeholder labels.
  var name: String {
    switch self {
    case .hub: "hub"
    case .briefing: "briefing"
    case .investigating: "investigating"
    case .debrief(let readOnly): readOnly ? "debrief (read-only)" : "debrief"
    case .complete: "complete"
    case .milestone: "milestone"
    }
  }

  var isDebrief: Bool { if case .debrief = self { true } else { false } }
}

/// What is on top of the phase. `nil` is the web's `"none"` — an `Optional` so
/// `.sheet(item:)` and `.fullScreenCover(item:)` bind to it directly (§4.2).
nonisolated enum ViewID: Identifiable, Codable, Sendable, Hashable {
  case board
  case source(String)
  case call, kit, settings, abandon, firstRun

  var id: String {
    switch self {
    case .board: "board"
    case .source(let sourceID): "source:\(sourceID)"
    case .call: "call"
    case .kit: "kit"
    case .settings: "settings"
    case .abandon: "abandon"
    case .firstRun: "firstRun"
    }
  }

  /// FirstRun is a `.fullScreenCover` with `interactiveDismissDisabled` — the
  /// disclaimer is not dismissible by accident. Everything else is a sheet.
  var isFullScreen: Bool { self == .firstRun }

  var sourceID: String? { if case .source(let id) = self { id } else { nil } }
}

// MARK: - Session state

/// The board in flight plus what is on top of it. C5's version also carries the
/// graded `last` result and the coach cursor.
nonisolated struct SessionState: Codable, Sendable, Hashable {
  var phase: Phase = .hub
  var view: ViewID?
  var shift: ShiftState?
  /// Source ids pulled on the case currently in front of the player.
  var queried: [String] = []
  /// Picked on the call sheet, not yet filed.
  var pendingDisposition: Disposition?
  /// C3's `overallShiftStatus` drives this. CALM until the engine lands.
  var status: TraceStatus = .calm

  /// The case in front of the player, if any.
  func currentCase(_ content: ContentPack) -> SocCase? {
    guard let shift, shift.index < shift.caseIds.count else { return nil }
    return content.case(shift.caseIds[shift.index])
  }
}

// MARK: - Actions (Appendix A §C: seventeen)

/// The fifteen actions of `DESIGN.md` §2.1, minus `CONTINUE` (G6), plus
/// `VIEW_RESULT` (G5) and `ACK_FIRSTRUN` (G19).
nonisolated enum SocAction: Sendable, Hashable {
  case hydrate
  case startShift(String)
  case begin
  /// **Deviation from `SPEC.md` §3.3, reported to the lead as a proposed amendment.**
  /// The spec types this `case resume` with no payload, which forces whoever holds
  /// the snapshot to assign `session` behind the reducer's back — and that is the
  /// one thing `send(_:)` being the single entry point is supposed to prevent. The
  /// restored state travels as the payload instead, so the reducer stays the only
  /// thing that decides what a restore means. `SessionState` is C5's own type, so
  /// the shape survives the swap.
  case resume(SessionState)
  case openView(ViewID)
  case closeView
  case pullSource(String)
  case pickDisposition(Disposition)
  case makeCall(Disposition)
  case nextCase
  case viewResult(String)
  case ackMilestone
  case ackFirstRun
  case toHub
  case abandon
  case buy(String)
  case setSetting(SettingKey, Bool)
}

/// The three player-controlled switches, as a key the reducer can carry without
/// knowing what storage is.
nonisolated enum SettingKey: String, Codable, Sendable, Hashable, CaseIterable {
  case haptics = "sentry.haptics"
  case holdToFile = "sentry.holdToFile"
  case coaching = "sentry.coaching"
}

// MARK: - Effects

/// What a transition asks the app to *do*. `EffectRunner` is the only interpreter
/// (§4.1): views never touch storage and never fire a haptic themselves.
nonisolated enum Effect: Equatable, Sendable, Hashable {
  case haptic(SocCue)
  /// Snapshot the in-flight shift. Coalesced by the runner to ≤1 write per 250 ms.
  case persistSession
  /// The shift settled or was abandoned — the snapshot is gone.
  case clearSession
  /// The 16:00 chain: `scoreShift → awardForShift → unlock diff → HandlerEvent →
  /// persistCareer → clearSession`. C3 and C4 own every link.
  case settleShift
  case persistCareer
  /// One of the five launch-critical `UserDefaults` flags.
  case setFlag(String, Bool)
  /// The daily board paid out; stamp `career.dailyDoneOn` (Appendix A G7).
  case markDailyDone(String)
}

// MARK: - Feel

/// The cue vocabulary of `DESIGN.md` §2.15 / `SPEC.md` §4.4. Twelve route to
/// SwiftUI `.sensoryFeedback`; `file`, `breachThud` and `rankup` get bespoke
/// `CHHapticPattern`s, and `heartbeat` is the looping player (C10).
nonisolated enum SocCue: Sendable, Hashable {
  case select
  case holdTick
  case findingLand
  case commitSoft
  case file
  case verdictGood
  case verdictOff
  case verdictWrong
  case breachThud
  case shiftClean
  case shiftRough
  case shiftBreached
  case rankup
  case denied
  case destructive
  case heartbeat(TraceStatus)
}

/// The looping heartbeat, from the pure scheduler.
nonisolated struct HeartbeatPlan: Sendable, Hashable {
  struct Beat: Sendable, Hashable {
    let atMs: Int
    let intensity: Float
    let sharpness: Float
  }

  let periodMs: Int
  let beats: [Beat]
}

/// `nil` at CALM and ALERT — **silence is the reward** (§2.15). Every number comes
/// from `tuning` (D7): the period is `60000 / bpm[status]` with the 400 ms floor.
nonisolated func heartbeatPlan(status: TraceStatus, tuning: Tuning) -> HeartbeatPlan? {
  guard status == .hunt || status == .lockdown else { return nil }
  let period = max(60_000 / max(tuning.bpm[status], 1), tuning.heartbeat.minPeriodMs)
  let lub = HeartbeatPlan.Beat(atMs: 0, intensity: 0.75, sharpness: 0.30)
  let dub = HeartbeatPlan.Beat(
    atMs: tuning.heartbeat.dubOffsetMs, intensity: 0.55 * 0.75, sharpness: 0.20)
  let peak = HeartbeatPlan.Beat(atMs: 0, intensity: 1.00, sharpness: 0.55)
  let peakDub = HeartbeatPlan.Beat(
    atMs: tuning.heartbeat.dubOffsetMs, intensity: 0.55, sharpness: 0.45)
  return HeartbeatPlan(
    periodMs: period, beats: status == .lockdown ? [peak, peakDub] : [lub, dub])
}

// MARK: - The stub reducer

/// The signature C5 ships (D9): pure, `(SessionState, [Effect])`, no I/O.
nonisolated func reduce(
  _ state: SessionState, _ action: SocAction, content: ContentPack, career: CareerState
) -> (SessionState, [Effect]) {
  var next = state
  var effects: [Effect] = []
  // Cheap: a value type over the already-decoded bundle. Built here rather than
  // captured so the reducer stays a free function with no stored state.
  let engine = SOCEngine(content: content)

  switch action {
  case .hydrate:
    break

  case .startShift(let shiftID):
    guard let def = content.shift(shiftID) ?? dailyShift(shiftID, content) else { break }
    next.shift = engine.assembleShift(def.id, def.caseIds)
    next.phase = .briefing
    next.view = nil
    next.queried = []
    next.pendingDisposition = nil
    next.status = .calm
    effects.append(.haptic(.commitSoft))

  case .begin:
    guard state.phase == .briefing else { break }
    next.phase = .investigating
    next.view = .board            // the board opens once per shift, then never again
    effects.append(.persistSession)

  case .resume(let restored):
    // The snapshot arrives as the payload, so the restore is a transition like any
    // other rather than an assignment the reducer never saw. An open sheet and a
    // half-picked disposition are deliberately not restored (§4.3).
    guard restored.shift != nil else { break }
    next = restored
    next.view = nil
    next.pendingDisposition = nil

  case .openView(let view):
    next.view = view
    effects.append(.haptic(.select))

  case .closeView:
    next.view = nil

  case .pullSource(let sourceID):
    guard state.phase == .investigating, !state.queried.contains(sourceID) else { break }
    next.queried.append(sourceID)
    effects.append(.haptic(.findingLand))
    effects.append(.persistSession)

  case .pickDisposition(let disposition):
    next.pendingDisposition = disposition
    effects.append(.haptic(.select))

  case .makeCall(let disposition):
    // The re-entrancy guard (`SocConsole.tsx:234`): one call per case, and the
    // second tap on a filed call does nothing at all.
    guard state.phase == .investigating,
          let shift = state.shift,
          let current = state.currentCase(content)
    else { break }
    // Lifted from `SocConsole.tsx:223` — the case's OWN sources, filtered by what
    // was pulled, summed by cost. `applyCall` does the rest: it grades, appends the
    // ordered result, moves both meters through `Trace.clamp` and advances the
    // index. No meter arithmetic exists in this app (D8).
    let timeSpent = current.sources
      .filter { state.queried.contains($0.id) }
      .reduce(0) { $0 + $1.cost }
    let filed = engine.applyCall(
      shift, current, disposition, queriedSourceIds: state.queried, timeSpent: timeSpent)
    next.shift = filed
    next.status = engine.overallShiftStatus(filed)
    next.phase = .debrief(readOnly: false)
    next.view = nil
    next.pendingDisposition = nil
    effects.append(.haptic(.file))
    // `SocConsole.tsx:241`, verbatim rule: the coach is done the moment the player
    // files their first real call, so it cannot re-fire on the next shift or reload.
    if shift.index == 0 { effects.append(.setFlag(SentryFlagKey.onboarding, true)) }
    effects.append(.persistSession)

  case .nextCase:
    guard let shift = state.shift else { break }
    if case .debrief(readOnly: true) = state.phase {
      // G5: a read-only debrief returns to the phase it was opened from.
      next.phase = engine.shiftComplete(shift) ? .complete : .investigating
      break
    }
    if state.phase == .complete {
      // G6: `complete → milestone | hub`. Choosing `.milestone` needs the rank-up
      // the settlement produced, which lives on C5's `SessionState.last`; until then
      // the rank beat is carried by the inbox and this returns to the desk.
      next.phase = .hub
      next.shift = nil
      next.queried = []
      next.status = .calm
      break
    }
    if engine.shiftComplete(shift) {
      next.phase = .complete
      // The 16:00 order C5's `EffectScheduleTests` pins:
      // `settleShift → persistCareer → clearSession`.
      effects.append(.settleShift)
      effects.append(.persistCareer)
      effects.append(.clearSession)
    } else {
      next.phase = .investigating
      next.queried = []
      effects.append(.persistSession)
    }

  case .viewResult(let caseID):
    guard state.shift?.result(for: caseID) != nil else { break }
    next.phase = .debrief(readOnly: true)
    next.view = nil

  case .ackMilestone:
    next.phase = .hub
    next.shift = nil
    next.status = .calm

  case .ackFirstRun:
    next.view = nil
    effects.append(.setFlag(SentryFlagKey.firstRun, true))

  case .toHub:
    next.phase = .hub
    next.view = nil
    next.shift = nil
    next.queried = []
    next.status = .calm

  case .abandon:
    next.phase = .hub
    next.view = nil
    next.shift = nil
    next.queried = []
    next.pendingDisposition = nil
    next.status = .calm
    effects.append(.haptic(.destructive))
    effects.append(.clearSession)

  case .buy:
    // The debit itself is `GameModel.buy(_:)`: `CareerRules.buyKit` returns a new
    // career and the reducer only sees the current one, so the wallet cannot be
    // moved from here. This schedules the write and the cue for it.
    effects.append(.haptic(.commitSoft))
    effects.append(.persistCareer)

  case .setSetting(let key, let value):
    effects.append(.setFlag(key.rawValue, value))
  }

  return (next, effects)
}

/// The two flag keys the reducer names. The other three are `SettingKey` raw values.
nonisolated enum SentryFlagKey {
  static let firstRun = "sentry.firstRun.v1"
  static let onboarding = "sentry.onboarding.v1"
}

/// The daily board is a `ShiftDef` built on demand, so it is not in `shiftsByID`.
private nonisolated func dailyShift(_ id: String, _ content: ContentPack) -> ShiftDef? {
  let today = content.dailyShift(on: Date())
  return today.id == id ? today : nil
}
