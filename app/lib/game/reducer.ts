// The pure game reducer.
//
// This is Phase 0 of the GHOST26 re-architecture (see docs/GAME_DESIGN.md): the
// 967-line async `runCommand` in the store is being incrementally replaced by a
// pure function of (state, command, context). Pure means: no Date.now(), no
// Math.random(), no setTimeout, no `set()`, no I/O — every input arrives via
// arguments and the only output is the returned CommandResult. That is what makes
// the game deterministic, unit-testable, and (later) server-authoritative.
//
// Commands are migrated here one group at a time. Synchronous, drama-free
// commands live here now; the staged-animation commands (scan/connect/...) stay
// in the store until an effects channel exists. `reduceCommand` returns null for
// any command it does not (yet) own, so the store can fall back to its legacy
// switch — the strangler-fig pattern.

import type { GameState, TerminalLine, VfxEvent } from "@/types/game";
import type { CommandContext } from "@/app/lib/game/context";
import { helpOutput } from "@/app/lib/game/commands";
import { formatMissionDetail, missionSummaryLine } from "@/app/lib/game/formatting";
import { evaluateMission, setMissionStatus, syncInbox } from "@/app/lib/game/missionLogic";

export type SoundCue =
  | "click"
  | "beep"
  | "alert"
  | "scan"
  | "connect"
  | "success"
  | "routeAdd"
  | "fileOp"
  | null;

export interface ParsedCommand {
  key: string;
  args: string[];
  flags: string[];
  /** The raw trimmed input, for echo/vfx value. */
  raw: string;
}

export interface CommandResult {
  /** Next game state (input state is never mutated). */
  state: GameState;
  /** Lines to append to the terminal buffer. */
  lines: TerminalLine[];
  soundCue: SoundCue;
  /** Vfx event WITHOUT `value` — the caller stamps the raw input as value. */
  vfx: VfxEvent | null;
  clearScreen: boolean;
}

/** Commands fully owned by the pure reducer. Everything else falls back to the store. */
const HANDLED = new Set([
  "help",
  "clear",
  "status",
  "inbox",
  "read",
  "missions",
  "accept",
  "submit",
]);

export function isReducerCommand(key: string): boolean {
  return HANDLED.has(key);
}

/**
 * Reduce a single command. Returns a CommandResult, or null if this command is
 * not handled here (caller should use the legacy path).
 */
export function reduceCommand(
  state: GameState,
  cmd: ParsedCommand,
  ctx: CommandContext
): CommandResult | null {
  if (!HANDLED.has(cmd.key)) return null;

  const line = (text: string, type: TerminalLine["type"] = "info"): TerminalLine => ({
    id: ctx.nextId(),
    text,
    type,
  });

  // Defaults mirror the legacy store behavior.
  const result: CommandResult = {
    state,
    lines: [],
    soundCue: "click",
    vfx: null,
    clearScreen: false,
  };

  switch (cmd.key) {
    case "help":
      result.lines = helpOutput();
      result.soundCue = "beep";
      break;

    case "clear":
      result.lines = [line("Terminal cleared.", "success")];
      result.clearScreen = true;
      break;

    case "status":
      result.lines = [
        line(`Cash: ${state.cash}c | Reputation: ${state.reputation}`),
        line(`Trace: ${state.trace.level.toFixed(1)}% (${state.trace.status})`),
        line(
          `Route anonym.: ${(state.route.anonymity * 100).toFixed(1)}% | Hops: ${state.route.hops.length}`
        ),
        line(
          `Connected host: ${state.session.connectedHost ?? "none"} | Working dir: ${
            state.session.workingDir ?? "/"
          }`
        ),
      ];
      result.soundCue = "beep";
      break;

    case "inbox":
      result.lines = state.inbox.map((mission) => line(missionSummaryLine(mission), "info"));
      break;

    case "read": {
      const missionId = cmd.args[0];
      const mission = state.activeMissions.find((m) => m.id === missionId);
      result.lines = mission
        ? formatMissionDetail(mission).map((text) => line(text, "info"))
        : [line(`Mission ${missionId} not found.`, "error")];
      break;
    }

    case "missions": {
      const active = state.activeMissions.filter((mission) => mission.status === "accepted");
      result.lines = active.length
        ? active.map((mission) => line(missionSummaryLine(mission), "info"))
        : [line("No active missions.", "info")];
      break;
    }

    case "accept": {
      const missionId = cmd.args[0];
      const mission = state.activeMissions.find((m) => m.id === missionId);
      if (!mission) {
        result.lines = [line(`Mission ${missionId} not found.`, "error")];
        break;
      }
      if (mission.status !== "available") {
        result.lines = [line(`${mission.title} is already ${mission.status}.`, "info")];
        break;
      }
      result.state = setMissionStatus(state, missionId, "accepted");
      result.lines = [line(`Mission ${mission.title} accepted.`, "success")];
      result.soundCue = "beep";
      result.vfx = { type: "success" };
      break;
    }

    case "submit": {
      const missionId = cmd.args[0];
      const mission = state.activeMissions.find((m) => m.id === missionId);
      if (!mission) {
        result.lines = [line(`Mission ${missionId} not found.`, "error")];
        break;
      }
      if (mission.status !== "accepted") {
        result.lines = [line(`Mission ${mission.title} is not active.`, "error")];
        break;
      }
      if (!evaluateMission(state, mission)) {
        result.lines = [
          line(`Mission ${mission.title} requires additional work.`, "error"),
          line("Check your inventory or edit the target file.", "info"),
        ];
        break;
      }
      const activeMissions = state.activeMissions.map((m) =>
        m.id === missionId ? { ...m, status: "completed" as const, completed: true } : m
      );
      result.state = {
        ...state,
        cash: state.cash + mission.reward.cash,
        reputation: state.reputation + mission.reward.reputation,
        activeMissions,
        inbox: syncInbox(activeMissions),
      };
      result.lines = [
        line(`Mission ${mission.title} completed!`, "success"),
        line(`+${mission.reward.cash}c  +${mission.reward.reputation} reputation`, "success"),
      ];
      result.soundCue = "success";
      result.vfx = { type: "success" };
      break;
    }
  }

  return result;
}
