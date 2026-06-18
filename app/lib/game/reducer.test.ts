import { describe, expect, it } from "vitest";
import type { GameState } from "@/types/game";
import { createInitialState } from "@/app/lib/game/initialState";
import { createDeterministicContext } from "@/app/lib/game/context";
import { isReducerCommand, reduceCommand, type ParsedCommand } from "@/app/lib/game/reducer";

const cmd = (key: string, args: string[] = []): ParsedCommand => ({
  key,
  args,
  flags: [],
  raw: [key, ...args].join(" "),
});

// mission-ghost is an exfil objective on host "hq-node", path "/secrets.txt",
// rewarding 2200c / 20 rep (see app/lib/game/missions.ts).
const lootForGhost = (state: GameState): GameState => ({
  ...state,
  inventory: [
    { id: "loot-1", label: "secrets.txt", source: "hq-node", path: "/secrets.txt", content: "x" },
  ],
});

function runSequence(steps: ParsedCommand[]) {
  const ctx = createDeterministicContext("test-seed", 0);
  let state = createInitialState({ now: 0 });
  const lines = [];
  for (const step of steps) {
    const r = reduceCommand(state, step, ctx);
    if (!r) throw new Error(`reducer did not handle ${step.key}`);
    state = r.state;
    lines.push(...r.lines);
  }
  return { state, lines };
}

describe("gameReducer — determinism", () => {
  it("same seed + same sequence => byte-identical state and lines", () => {
    const steps = [
      cmd("inbox"),
      cmd("accept", ["mission-ghost"]),
      cmd("status"),
      cmd("read", ["mission-ghost"]),
      cmd("missions"),
    ];
    const a = runSequence(steps);
    const b = runSequence(steps);
    expect(b.state).toEqual(a.state);
    expect(b.lines).toEqual(a.lines);
  });
});

describe("gameReducer — purity", () => {
  it("never mutates the input state", () => {
    const state = createInitialState({ now: 0 });
    const cashBefore = state.cash;
    const ctx = createDeterministicContext();

    const accepted = reduceCommand(state, cmd("accept", ["mission-ghost"]), ctx)!.state;
    const armed = lootForGhost(accepted);
    const armedCash = armed.cash;

    const submitted = reduceCommand(armed, cmd("submit", ["mission-ghost"]), ctx)!;

    expect(submitted.state.cash).toBe(armedCash + 2200);
    expect(armed.cash).toBe(armedCash); // submit's input untouched
    expect(state.cash).toBe(cashBefore); // original untouched
    // original mission list not mutated by accept
    expect(state.activeMissions.find((m) => m.id === "mission-ghost")!.status).toBe("available");
  });
});

describe("gameReducer — behavior parity", () => {
  const ctx = () => createDeterministicContext();

  it("accept marks mission + inbox accepted, guards re-accept", () => {
    const state = createInitialState({ now: 0 });
    const r1 = reduceCommand(state, cmd("accept", ["mission-ghost"]), ctx())!;
    expect(r1.state.activeMissions.find((m) => m.id === "mission-ghost")!.status).toBe("accepted");
    expect(r1.state.inbox.find((m) => m.id === "mission-ghost")!.status).toBe("accepted");

    const r2 = reduceCommand(r1.state, cmd("accept", ["mission-ghost"]), ctx())!;
    expect(r2.lines.some((l) => l.text.includes("already accepted"))).toBe(true);
  });

  it("accept of unknown mission errors without changing state", () => {
    const state = createInitialState({ now: 0 });
    const r = reduceCommand(state, cmd("accept", ["nope"]), ctx())!;
    expect(r.lines[0].type).toBe("error");
    expect(r.state).toBe(state); // unchanged reference on the no-op path
  });

  it("submit before satisfying objective reports work remaining, no reward", () => {
    const state = createInitialState({ now: 0 });
    const accepted = reduceCommand(state, cmd("accept", ["mission-ghost"]), ctx())!.state;
    const r = reduceCommand(accepted, cmd("submit", ["mission-ghost"]), ctx())!;
    expect(r.state.cash).toBe(state.cash);
    expect(r.lines.some((l) => l.text.includes("requires additional work"))).toBe(true);
  });

  it("submit on satisfied objective pays out and completes", () => {
    const state = createInitialState({ now: 0 });
    const accepted = reduceCommand(state, cmd("accept", ["mission-ghost"]), ctx())!.state;
    const r = reduceCommand(lootForGhost(accepted), cmd("submit", ["mission-ghost"]), ctx())!;
    expect(r.state.cash).toBe(state.cash + 2200);
    expect(r.state.reputation).toBe(state.reputation + 20);
    expect(r.state.activeMissions.find((m) => m.id === "mission-ghost")!.status).toBe("completed");
    expect(r.soundCue).toBe("success");
  });

  it("returns null for commands it does not own", () => {
    const state = createInitialState({ now: 0 });
    expect(reduceCommand(state, cmd("scan", ["hq-node"]), ctx())).toBeNull();
    expect(isReducerCommand("scan")).toBe(false);
    expect(isReducerCommand("submit")).toBe(true);
  });
});
