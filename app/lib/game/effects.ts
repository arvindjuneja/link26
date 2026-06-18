// The effects channel — how the PURE reducer expresses staged, time-based
// presentation (terminal drama + map animation) without itself calling
// setTimeout or set(). The reducer computes the final game state synchronously
// and returns a declarative timeline of TimedEffects; the store's view layer
// plays that timeline. Effects are presentation only — they never change game
// state (it is already final by the time effects play).

import type { TerminalLine } from "@/types/game";

/** Map animation state driving the world-map scan/connect visualization. */
export interface ScanAnimation {
  fromNode: string | null; // last proxy hop, or "player"
  toNode: string; // target host id
  throughProxies: string[]; // route hops
  phase: "routing" | "scanning" | "complete";
  progress: number; // 0..1
  startTime: number;
}

/** Coarse execution state used to gate terminal input + show a busy indicator. */
export type ExecutionPhase = "idle" | "initiating" | "routing" | "executing" | "complete";

/** How an effect mutates the current scan animation. */
export type ScanAnimationOp =
  | { type: "set"; value: ScanAnimation }
  | { type: "patch"; value: Partial<ScanAnimation> }
  | { type: "clear" };

/** One scheduled step of presentation, `atMs` after the command was dispatched. */
export interface TimedEffect {
  atMs: number;
  lines?: TerminalLine[];
  anim?: ScanAnimationOp;
  executionPhase?: ExecutionPhase;
  isExecuting?: boolean;
}
