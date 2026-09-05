// The 29 numbers the engine branches on, transcribed from the READ-ONLY web tree
// (D1) and shipped as data so `Sources/SentryCore/Engine/` contains no numeric
// literal (D7). A designer retune is a zero-Swift-change operation.
//
// Count (S8): trace 5 · bpm 4 · timeBudgetDefault 1 · grade 8 · shift 2 · career 6
//           · heartbeat 3 = 29. `TuningExpectationTests` enumerates exactly these.
//
// Source of every value:
//   trace.*                app/lib/game/trace.ts:3-8   (statusThresholds, clampLevel bounds)
//   bpm.*                  app/components/soc/SocConsole.tsx:50
//   timeBudgetDefault      app/lib/soc/engine.ts        (DEFAULT_TIME_BUDGET)
//   grade.*                app/lib/soc/engine.ts        (gradeCall's deltas)
//   shift.*                app/lib/soc/engine.ts        (scoreShift's clean/breached rule)
//   career.*               app/lib/career/state.ts      (awardForShift, RED_RUN_CUT)
//   heartbeat.*            docs/ios/DESIGN.md §2.15     (the pure scheduler's caps)

import type { ExportedTuning } from "@/app/lib/soc/exporter/schema";

export const TUNING: ExportedTuning = {
  trace: { min: 0, max: 100, alert: 25, hunt: 50, lockdown: 80 },
  bpm: { CALM: 50, ALERT: 76, HUNT: 112, LOCKDOWN: 150 },
  timeBudgetDefault: 90,
  grade: {
    tpMissedBreach: 30,
    tpUnderContainBreach: 10,
    tpOverContainNoise: 12,
    fpEscalateT2Noise: 12,
    fpEscalateIsolateNoise: 20,
    btpClosedAsFpNoise: 4,
    btpEscalateT2Noise: 14,
    btpIsolateNoise: 24,
  },
  shift: { cleanAccuracy: 0.8, breachedMissedDetections: 2 },
  career: {
    cashPerCorrect: 50,
    cleanBonus: 150,
    standingClean: 40,
    standingRough: 15,
    standingBreached: 5,
    redRunCut: 150,
  },
  heartbeat: { minPeriodMs: 400, autoSuspendMs: 40000, dubOffsetMs: 120 },
};

/** Every tuning number, flattened — the exporter asserts there are exactly 29. */
export function tuningNumbers(t: ExportedTuning = TUNING): number[] {
  const out: number[] = [];
  const walk = (v: unknown): void => {
    if (typeof v === "number") {
      out.push(v);
      return;
    }
    if (v && typeof v === "object") {
      for (const k of Object.keys(v as Record<string, unknown>).sort()) {
        walk((v as Record<string, unknown>)[k]);
      }
    }
  };
  walk(t);
  return out;
}

export const TUNING_NUMBER_COUNT = 29;
