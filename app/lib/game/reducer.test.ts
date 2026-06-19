import { describe, expect, it } from "vitest";
import type { GameState } from "@/types/game";
import { createInitialState } from "@/app/lib/game/initialState";
import { createDeterministicContext } from "@/app/lib/game/context";
import { isReducerCommand, reduceCommand, type ParsedCommand } from "@/app/lib/game/reducer";
import { CAMPAIGN } from "@/app/lib/game/campaign";

const cmd = (key: string, args: string[] = [], flags: string[] = []): ParsedCommand => ({
  key,
  args,
  flags,
  raw: [key, ...args, ...flags.map((f) => `--${f}`)].join(" "),
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
      cmd("route add", ["proxy-1"]),
      cmd("route add", ["proxy-3"]),
      cmd("route show"),
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

  it("returns null only for genuinely unknown commands", () => {
    const state = createInitialState({ now: 0 });
    expect(reduceCommand(state, cmd("frobnicate"), ctx())).toBeNull();
    expect(isReducerCommand("frobnicate")).toBe(false);
    expect(isReducerCommand("scan")).toBe(true);
    expect(isReducerCommand("connect")).toBe(true);
    expect(isReducerCommand("submit")).toBe(true);
    expect(isReducerCommand("route add")).toBe(true);
  });
});

describe("gameReducer — scan / connect (effects channel)", () => {
  const ctx = () => createDeterministicContext("fx", 0);

  it("scan marks the host scanned, raises trace, and emits a staged timeline", () => {
    const state = createInitialState({ now: 0 });
    const r = reduceCommand(state, cmd("scan", ["hq-node"]), ctx())!;

    expect(r.state.session.currentTarget).toBe("hq-node");
    expect(r.state.session.scannedHosts).toEqual(new Set(["hq-node"]));
    expect(r.state.exposure.NETWORK.level).toBeGreaterThan(state.exposure.NETWORK.level);
    expect(r.soundCue).toBe("scan");
    expect(r.vfx).toEqual({ type: "scan", target: "hq-node" });

    // timeline: t0 sets animation + busy; final step clears + goes idle
    expect(r.effects!.map((e) => e.atMs)).toEqual([0, 400, 800, 1200, 2700]);
    expect(r.effects![0]).toMatchObject({ isExecuting: true, executionPhase: "routing" });
    expect(r.effects![0].anim).toMatchObject({ type: "set" });
    const last = r.effects![r.effects!.length - 1];
    expect(last.anim).toEqual({ type: "clear" });
    expect(last.executionPhase).toBe("idle");

    // purity: the input's scannedHosts set was not mutated
    expect(state.session.scannedHosts).toEqual(new Set());
  });

  it("scan effects are deterministic for a fixed context", () => {
    const a = reduceCommand(createInitialState({ now: 0 }), cmd("scan", ["hq-node"]), ctx())!;
    const b = reduceCommand(createInitialState({ now: 0 }), cmd("scan", ["hq-node"]), ctx())!;
    expect(b.effects).toEqual(a.effects);
  });

  it("connect with no scan and no route stacks the trace penalties and warns", () => {
    const state = createInitialState({ now: 0 });
    const r = reduceCommand(state, cmd("connect", ["hq-node"]), ctx())!;

    expect(r.state.session.connectedHost).toBe("hq-node");
    expect(r.state.session.workingDir).toBe("/");
    // 15 + 35 (unscanned) + 40 (no route) + 20 (both) => large spike, alert
    expect(r.state.exposure.NETWORK.level).toBeGreaterThan(state.exposure.NETWORK.level + 10);
    expect(r.soundCue).toBe("alert");
    // both the "not scanned" (300ms) and "no route" (500ms) warnings are present
    expect(r.effects!.some((e) => e.atMs === 300)).toBe(true);
    expect(r.effects!.some((e) => e.atMs === 500)).toBe(true);
  });

  it("connect to an unreachable host errors with no effects", () => {
    const state = createInitialState({ now: 0 });
    const r = reduceCommand(state, cmd("connect", ["ghosthost"]), ctx())!;
    expect(r.lines[0].type).toBe("error");
    expect(r.effects).toBeUndefined();
    expect(r.state).toBe(state);
  });
});

describe("gameReducer — recon surfaces (OSINT / RF / access)", () => {
  const ctx = () => createDeterministicContext("recon", 0);

  it("osint passive collects only passive facts at near-zero footprint", () => {
    const state = createInitialState({ now: 0 });
    const r = reduceCommand(state, cmd("osint", ["person-aurora"]), ctx())!;
    expect(r.state.evidence.length).toBeGreaterThan(0);
    expect(r.state.evidence.every((e) => e.sourceId === "person-aurora")).toBe(true);
    // passive sweep surfaces no breach/device cards
    expect(r.state.evidence.some((e) => e.factKind === "breach")).toBe(false);
    expect(r.state.exposure.FOOTPRINT.level).toBeGreaterThan(0);
  });

  it("osint --active surfaces breach/device and costs more footprint", () => {
    const state = createInitialState({ now: 0 });
    const passive = reduceCommand(state, cmd("osint", ["person-aurora"]), ctx())!;
    const active = reduceCommand(state, cmd("osint", ["person-aurora"], ["active"]), ctx())!;
    expect(active.state.evidence.some((e) => e.factKind === "breach")).toBe(true);
    expect(active.state.exposure.FOOTPRINT.level).toBeGreaterThan(passive.state.exposure.FOOTPRINT.level);
  });

  it("collect rf characterizes an emitter and raises RF", () => {
    const state = createInitialState({ now: 0 });
    const r = reduceCommand(state, cmd("collect rf", ["solstice"]), ctx())!;
    expect(r.state.evidence.some((e) => e.sourceId === "emitter-solstice" && e.factKind === "signature")).toBe(true);
    expect(r.state.exposure.RF.level).toBeGreaterThan(0);
  });

  it("acquire needs harvested creds first, then is deterministic + raises NETWORK", () => {
    const state = createInitialState({ now: 0 });
    const cold = reduceCommand(state, cmd("acquire", ["hq-node"]), ctx())!;
    expect(cold.lines[0].text).toContain("No harvested credentials");

    const withBreach = reduceCommand(state, cmd("osint", ["person-hq-node"], ["active"]), ctx())!.state;
    const a = reduceCommand(withBreach, cmd("acquire", ["hq-node"]), ctx())!;
    const b = reduceCommand(withBreach, cmd("acquire", ["hq-node"]), ctx())!;
    expect(a.state.exposure.NETWORK.level).toBeGreaterThan(withBreach.exposure.NETWORK.level);
    expect(a.state.session.acquired).toEqual(b.state.session.acquired); // deterministic
  });
});

describe("gameReducer — gear track", () => {
  const ctx = () => createDeterministicContext("gear", 0);

  it("buy deducts cash and raises the gear tier", () => {
    const state = createInitialState({ now: 0 });
    const r = reduceCommand(state, cmd("buy", ["rig"]), ctx())!;
    expect(r.state.gear.rig).toBe(1);
    expect(r.state.cash).toBe(state.cash - 1500);
    expect(r.soundCue).toBe("success");
  });

  it("buy rejects unknown items and unaffordable purchases", () => {
    const state = createInitialState({ now: 0 });
    expect(reduceCommand(state, cmd("buy", ["nope"]), ctx())!.lines[0].type).toBe("error");
    const broke = { ...state, cash: 10 };
    expect(reduceCommand(broke, cmd("buy", ["rig"]), ctx())!.lines[0].text).toContain("Insufficient");
  });

  it("gear flattens that channel's noise", () => {
    const base = createInitialState({ now: 0 });
    const geared = { ...base, gear: { rig: 4 } }; // max NETWORK mitigation
    const plainScan = reduceCommand(base, cmd("scan", ["hq-node"]), ctx())!;
    const gearedScan = reduceCommand(geared, cmd("scan", ["hq-node"]), ctx())!;
    const plainRise = plainScan.state.exposure.NETWORK.level - base.exposure.NETWORK.level;
    const gearedRise = gearedScan.state.exposure.NETWORK.level - geared.exposure.NETWORK.level;
    expect(gearedRise).toBeLessThan(plainRise);
  });
});

describe("gameReducer — exits & scoring (clean / hot / burned + risk-dial)", () => {
  const ctx = () => createDeterministicContext("exit", 0);
  const armedGhost = () => {
    const base = createInitialState({ now: 0 });
    const accepted = reduceCommand(base, cmd("accept", ["mission-ghost"]), ctx())!.state;
    return lootForGhost(accepted);
  };

  it("clean exit increments the streak and pays a streak bonus", () => {
    const armed = { ...armedGhost(), streak: 3 };
    const r = reduceCommand(armed, cmd("submit", ["mission-ghost"]), ctx())!;
    expect(r.state.streak).toBe(4);
    expect(r.state.cash).toBe(armed.cash + Math.round(2200 * 1.3));
    expect(r.lines.some((l) => l.text.includes("GHOST"))).toBe(true);
  });

  it("hot exit pays full, resets the streak, and ticks ATTRIBUTION", () => {
    const armed = {
      ...armedGhost(),
      streak: 2,
      exposure: { ...armedGhost().exposure, NETWORK: { level: 60, status: "HUNT" as const } },
    };
    const r = reduceCommand(armed, cmd("submit", ["mission-ghost"]), ctx())!;
    expect(r.state.streak).toBe(0);
    expect(r.state.cash).toBe(armed.cash + 2200);
    expect(r.state.exposure.ATTRIBUTION.level).toBeGreaterThan(0);
    expect(r.lines.some((l) => l.text.includes("HOT"))).toBe(true);
  });

  it("burned exit halves pay and dents reputation", () => {
    const armed = {
      ...armedGhost(),
      exposure: { ...armedGhost().exposure, RF: { level: 90, status: "LOCKDOWN" as const } },
    };
    const r = reduceCommand(armed, cmd("submit", ["mission-ghost"]), ctx())!;
    expect(r.state.cash).toBe(armed.cash + 1100); // half of 2200
    expect(r.state.reputation).toBe(armed.reputation + 10); // 20 reward - 10 penalty
    expect(r.lines.some((l) => l.text.includes("BURNED"))).toBe(true);
  });

  it("the risk-dial (--push) boosts pay but spikes exposure", () => {
    const armed = armedGhost();
    const r = reduceCommand(armed, cmd("submit", ["mission-ghost"], ["push"]), ctx())!;
    expect(r.state.cash).toBe(armed.cash + Math.round(2200 * 1.6));
    expect(r.state.exposure.NETWORK.level).toBeGreaterThan(armed.exposure.NETWORK.level);
  });

  it("pushing into a burned exit forfeits the bonus (greed can't out-earn caution)", () => {
    const armed = {
      ...armedGhost(),
      exposure: { ...armedGhost().exposure, RF: { level: 90, status: "LOCKDOWN" as const } },
    };
    const r = reduceCommand(armed, cmd("submit", ["mission-ghost"], ["push"]), ctx())!;
    expect(r.state.cash).toBe(armed.cash + 1100); // half pay, NO 1.6x bonus
    expect(r.lines.some((l) => l.text.includes("No bonus"))).toBe(true);
  });

  it("ATTRIBUTION gear (launder) flattens the attribution spike on a hot exit", () => {
    const hot = {
      ...armedGhost(),
      exposure: { ...armedGhost().exposure, NETWORK: { level: 60, status: "HUNT" as const } },
    };
    const plain = reduceCommand(hot, cmd("submit", ["mission-ghost"]), ctx())!;
    const geared = reduceCommand({ ...hot, gear: { launder: 3 } }, cmd("submit", ["mission-ghost"]), ctx())!;
    expect(geared.state.exposure.ATTRIBUTION.level).toBeLessThan(plain.state.exposure.ATTRIBUTION.level);
  });
});

describe("gameReducer — campaign spine", () => {
  const ctx = () => createDeterministicContext("camp", 0);

  it("chapter 0 is available, later chapters locked, and locked chapters can't be accepted", () => {
    const s = createInitialState({ now: 0 });
    const ch0 = s.activeMissions.find((m) => m.chapterIndex === 0)!;
    const ch1 = s.activeMissions.find((m) => m.chapterIndex === 1)!;
    expect(ch0.status).toBe("available");
    expect(ch1.status).toBe("locked");
    const r = reduceCommand(s, cmd("accept", [ch1.id]), ctx())!;
    expect(r.lines[0].text).toContain("locked");
  });

  it("completing a chapter advances the spine, unlocks the next, and Mercer speaks", () => {
    const base = createInitialState({ now: 0 });
    const ch0 = base.activeMissions.find((m) => m.chapterIndex === 0)!; // exfil hq-node /secrets.txt
    const accepted = reduceCommand(base, cmd("accept", [ch0.id]), ctx())!.state;
    const armed = {
      ...accepted,
      inventory: [{ id: "i", label: "x", source: "hq-node", path: "/secrets.txt", content: "x" }],
    };
    const r = reduceCommand(armed, cmd("submit", [ch0.id]), ctx())!;
    expect(r.state.campaign.chapter).toBe(1);
    expect(r.state.activeMissions.find((m) => m.chapterIndex === 1)!.status).toBe("available");
    expect(r.lines.some((l) => l.text.startsWith("MERCER:"))).toBe(true);
  });

  it("the campaign command reports progress + the current brief", () => {
    const s = createInitialState({ now: 0 });
    const r = reduceCommand(s, cmd("campaign"), ctx())!;
    expect(r.lines[0].text).toContain("Act I");
    expect(r.lines.some((l) => l.text.includes("[ now]"))).toBe(true);
    expect(r.lines.some((l) => l.text.startsWith("MERCER:"))).toBe(true);
  });
});

describe("gameReducer — ATTRIBUTION meta (Act II)", () => {
  const ctx = () => createDeterministicContext("act2", 0);

  it("churn resets ATTRIBUTION for a steep cost and clears recon footing", () => {
    const base = createInitialState({ now: 0 });
    const dirty = {
      ...base,
      cash: 5000,
      session: { ...base.session, acquired: ["hq-node"] },
      exposure: { ...base.exposure, ATTRIBUTION: { level: 60, status: "HUNT" as const } },
    };
    const r = reduceCommand(dirty, cmd("churn"), ctx())!;
    expect(r.state.exposure.ATTRIBUTION.level).toBe(0);
    expect(r.state.cash).toBe(2000); // 5000 - 3000
    expect(r.state.session.acquired).toEqual([]);
  });

  it("churn refuses when ATTRIBUTION is clean or cash is short", () => {
    const base = createInitialState({ now: 0 });
    expect(reduceCommand(base, cmd("churn"), ctx())!.lines[0].text).toContain("already clean");
    const broke = {
      ...base,
      cash: 100,
      exposure: { ...base.exposure, ATTRIBUTION: { level: 60, status: "HUNT" as const } },
    };
    expect(reduceCommand(broke, cmd("churn"), ctx())!.lines[0].type).toBe("error");
  });

  it("reusing a hot proxy builds ATTRIBUTION", () => {
    const base = createInitialState({ now: 0 });
    const hot = {
      ...base,
      world: {
        ...base.world,
        proxies: { ...base.world.proxies, "proxy-2": { ...base.world.proxies["proxy-2"], heat: 0.8 } },
      },
    };
    const r = reduceCommand(hot, cmd("route add", ["proxy-2"]), ctx())!;
    expect(r.state.exposure.ATTRIBUTION.level).toBeGreaterThan(0);
  });

  it("the campaign now spans two acts", () => {
    const acts = new Set(CAMPAIGN.map((c) => c.act));
    expect(acts.has("I")).toBe(true);
    expect(acts.has("II")).toBe(true);
    expect(CAMPAIGN.length).toBeGreaterThanOrEqual(10);
  });
});

describe("gameReducer — evidence-assembly missions", () => {
  const ctx = () => createDeterministicContext("missions", 0);

  it("identify completes by assembling the required cards, not typing", () => {
    const base = createInitialState({ now: 0 });
    const accepted = reduceCommand(base, cmd("accept", ["mission-faceless"]), ctx())!.state;
    // before recon: not satisfiable
    const early = reduceCommand(accepted, cmd("submit", ["mission-faceless"]), ctx())!;
    expect(early.lines.some((l) => l.text.includes("additional work"))).toBe(true);
    // active OSINT surfaces handle+email+breach
    const recon = reduceCommand(accepted, cmd("osint", ["person-aurora"], ["active"]), ctx())!.state;
    const done = reduceCommand(recon, cmd("submit", ["mission-faceless"]), ctx())!;
    expect(done.state.cash).toBe(base.cash + 2000);
    expect(done.state.activeMissions.find((m) => m.id === "mission-faceless")!.status).toBe("completed");
  });

  it("characterize completes by collecting the emitter signature", () => {
    const base = createInitialState({ now: 0 });
    const accepted = reduceCommand(base, cmd("accept", ["mission-carrier"]), ctx())!.state;
    const recon = reduceCommand(accepted, cmd("collect rf", ["solstice"]), ctx())!.state;
    const done = reduceCommand(recon, cmd("submit", ["mission-carrier"]), ctx())!;
    expect(done.state.cash).toBe(base.cash + 1500);
    expect(done.state.activeMissions.find((m) => m.id === "mission-carrier")!.status).toBe("completed");
  });
});

// Helper: mark a host connected so filesystem commands work.
const connectedTo = (state: GameState, hostId: string): GameState => ({
  ...state,
  session: { ...state.session, connectedHost: hostId, currentTarget: hostId, workingDir: "/" },
});

describe("gameReducer — proxy / route", () => {
  const ctx = () => createDeterministicContext();

  it("route add appends a hop, heats the proxy, raises anonymity", () => {
    const state = createInitialState({ now: 0 });
    const r = reduceCommand(state, cmd("route add", ["proxy-1"]), ctx())!;
    expect(r.state.route.hops).toEqual(["proxy-1"]);
    expect(r.state.world.proxies["proxy-1"].heat).toBeGreaterThan(0);
    expect(r.state.route.anonymity).toBeGreaterThan(0);
    expect(r.soundCue).toBe("routeAdd");
    // input proxies untouched (purity)
    expect(state.world.proxies["proxy-1"].heat).toBe(0);
  });

  it("route add warns when a proxy overheats", () => {
    const base = createInitialState({ now: 0 });
    const hot: GameState = {
      ...base,
      world: {
        ...base.world,
        proxies: { ...base.world.proxies, "proxy-1": { ...base.world.proxies["proxy-1"], heat: 0.7 } },
      },
    };
    const r = reduceCommand(hot, cmd("route add", ["proxy-1"]), ctx())!;
    expect(r.lines.some((l) => l.type === "warning" && l.text.includes("overheating"))).toBe(true);
  });

  it("route add rejects unknown and duplicate proxies", () => {
    const state = createInitialState({ now: 0 });
    const unknown = reduceCommand(state, cmd("route add", ["nope"]), ctx())!;
    expect(unknown.lines[0].text).toContain("unavailable");

    const added = reduceCommand(state, cmd("route add", ["proxy-1"]), ctx())!.state;
    const dup = reduceCommand(added, cmd("route add", ["proxy-1"]), ctx())!;
    expect(dup.lines[0].text).toContain("already in route");
  });
});

describe("gameReducer — recon", () => {
  const ctx = () => createDeterministicContext();

  it("probe reports a known service and raises trace", () => {
    const state = createInitialState({ now: 0 });
    const r = reduceCommand(state, cmd("probe", ["hq-node", "22"]), ctx())!;
    expect(r.lines[0].text).toContain("ssh");
    expect(r.state.exposure.NETWORK.level).toBeGreaterThan(state.exposure.NETWORK.level);
  });

  it("probe of a closed port is filtered", () => {
    const state = createInitialState({ now: 0 });
    const r = reduceCommand(state, cmd("probe", ["hq-node", "9999"]), ctx())!;
    expect(r.lines[0].text).toContain("filtered");
  });
});

describe("gameReducer — filesystem & the exfil loop", () => {
  const ctx = () => createDeterministicContext();

  it("requires a connection for filesystem commands", () => {
    const state = createInitialState({ now: 0 });
    expect(reduceCommand(state, cmd("ls"), ctx())!.lines[0].text).toContain("No host connected");
    expect(reduceCommand(state, cmd("cat", ["/secrets.txt"]), ctx())!.lines[0].type).toBe("error");
  });

  it("cp pulls a file into inventory and that satisfies an exfil mission end-to-end", () => {
    const base = createInitialState({ now: 0 });
    const accepted = reduceCommand(base, cmd("accept", ["mission-ghost"]), ctx())!.state;
    const session = connectedTo(accepted, "hq-node");

    const copied = reduceCommand(session, cmd("cp", ["/secrets.txt", "@local"]), ctx())!;
    expect(copied.state.inventory).toHaveLength(1);
    expect(copied.state.inventory[0]).toMatchObject({ source: "hq-node", path: "/secrets.txt" });
    expect(copied.soundCue).toBe("fileOp");
    expect(copied.state.exposure.NETWORK.level).toBeGreaterThan(session.exposure.NETWORK.level);

    const submitted = reduceCommand(copied.state, cmd("submit", ["mission-ghost"]), ctx())!;
    expect(submitted.state.cash).toBe(base.cash + 2200);
    expect(submitted.state.activeMissions.find((m) => m.id === "mission-ghost")!.status).toBe("completed");
  });

  it("edit tampers a file and rm removes it", () => {
    const base = connectedTo(createInitialState({ now: 0 }), "hq-node");

    const edited = reduceCommand(base, cmd("edit", ["/secrets.txt", "spoofed"]), ctx())!;
    const host = edited.state.world.hosts["hq-node"];
    expect(host.filesystem.find((f) => f.path === "/secrets.txt")!.content).toContain("tampered");

    const removed = reduceCommand(base, cmd("rm", ["/secrets.txt"]), ctx())!;
    expect(removed.state.world.hosts["hq-node"].filesystem.some((f) => f.path === "/secrets.txt")).toBe(false);
  });

  it("wipe logs empties host logs, spikes trace, raises an alert", () => {
    const base = connectedTo(createInitialState({ now: 0 }), "hq-node");
    expect(base.world.hosts["hq-node"].logs.length).toBeGreaterThan(0);
    const r = reduceCommand(base, cmd("wipe logs"), ctx())!;
    expect(r.state.world.hosts["hq-node"].logs).toHaveLength(0);
    expect(r.vfx).toEqual({ type: "alert" });
    expect(r.state.exposure.NETWORK.level).toBeGreaterThan(base.exposure.NETWORK.level);
  });

  it("disconnect drops the session but preserves scanned hosts AND acquired creds", () => {
    const base = connectedTo(createInitialState({ now: 0 }), "hq-node");
    const armed: GameState = {
      ...base,
      session: { ...base.session, scannedHosts: new Set(["hq-node"]), acquired: ["hq-node"] },
    };
    const r = reduceCommand(armed, cmd("disconnect"), ctx())!;
    expect(r.state.session.connectedHost).toBeUndefined();
    expect(r.state.session.scannedHosts).toEqual(new Set(["hq-node"]));
    expect(r.state.session.acquired).toEqual(["hq-node"]); // creds survive a disconnect
  });
});
