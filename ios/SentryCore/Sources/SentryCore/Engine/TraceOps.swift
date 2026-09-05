import Foundation

// NOTE ON THE FILE NAME: SPEC §1 lists this file as `Engine/Trace.swift`. SwiftPM
// derives object-file names from the source basename, so a second `Trace.swift` in
// the `SentryCore` target collides with C2's `Model/Trace.swift` and the build fails
// with "multiple producers". Renamed to `TraceOps.swift`, mirroring `ShiftOps.swift`;
// reported to the lead as a forced deviation from the spec's file list.

/// `app/lib/game/trace.ts`, ported literally — the two functions the SOC engine
/// uses, and nothing else. `addTraceNoise` and `decayTrace` belong to the red seat
/// and are not part of this build.
///
/// Both pressure meters share one band table and one clamp. Every number comes
/// from `content.tuning.trace` (D7): the thresholds are the TypeScript
/// `statusThresholds` record, and the clamp bounds are its `Math.max(0, …)` /
/// `Math.min(100, …)`. **This file contains no numeric literal at all.**
public enum Trace {

  /// `getTraceStatus` — a descending threshold ladder, first match wins.
  ///
  /// The CALM threshold is never compared against: it is the fallthrough, exactly
  /// as in the TypeScript, which is why a negative level still reads CALM rather
  /// than trapping. `trace.json` pins every level from −5 to 105.
  public static func status(_ level: Int, _ t: Tuning) -> TraceStatus {
    if level >= t.trace.lockdown { return .lockdown }
    if level >= t.trace.hunt { return .hunt }
    if level >= t.trace.alert { return .alert }
    return .calm
  }

  /// `clampLevel` — `Math.max(min, Math.min(max, level))`, both bounds from tuning.
  /// Applied to both meters on every call so neither can leave the band table.
  public static func clamp(_ level: Int, _ t: Tuning) -> Int {
    max(t.trace.min, min(t.trace.max, level))
  }
}
