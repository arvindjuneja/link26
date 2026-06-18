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

import type { GameState, Host, InventoryItem, TerminalLine, VfxEvent } from "@/types/game";
import type { CommandContext } from "@/app/lib/game/context";
import { helpOutput } from "@/app/lib/game/commands";
import { formatMissionDetail, formatProxyTable, missionSummaryLine } from "@/app/lib/game/formatting";
import { evaluateMission, setMissionStatus, syncInbox } from "@/app/lib/game/missionLogic";
import { addTraceNoise } from "@/app/lib/game/trace";
import { buildRouteState, clamp, findHost, listFiles } from "@/app/lib/game/worldQueries";

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

/**
 * Commands fully owned by the pure reducer. Everything else falls back to the
 * store's legacy switch — currently only `scan` and `connect`, which need an
 * effects channel for their staged animation before they can migrate.
 */
const HANDLED = new Set([
  // mission + status
  "help",
  "clear",
  "status",
  "inbox",
  "read",
  "missions",
  "accept",
  "submit",
  // proxy / route
  "proxy list",
  "proxy info",
  "route show",
  "route add",
  "route rm",
  "route clear",
  // recon
  "probe",
  "fingerprint",
  // session / filesystem
  "pwd",
  "ls",
  "cd",
  "cat",
  "cp",
  "rm",
  "edit",
  "wipe logs",
  "disconnect",
  "exit",
  // misc
  "market",
  "buy",
]);

export function isReducerCommand(key: string): boolean {
  return HANDLED.has(key);
}

/** Apply trace noise from an action, stamping the injected clock. Pure. */
function applyTrace(state: GameState, noise: number, ctx: CommandContext, host?: Host): GameState {
  return {
    ...state,
    trace: addTraceNoise(state.trace, noise, state.route, host),
    time: ctx.now,
  };
}

/** Replace a single host in the world. Pure. */
function withHost(state: GameState, host: Host): GameState {
  return {
    ...state,
    world: { ...state.world, hosts: { ...state.world.hosts, [host.id]: host } },
  };
}

/** Coerce session.scannedHosts to a Set regardless of how it was deserialized. */
function asSet(value: unknown): Set<string> {
  if (value instanceof Set) return value;
  if (Array.isArray(value)) return new Set(value);
  return new Set();
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

    case "proxy list":
      result.lines = formatProxyTable(Object.values(state.world.proxies)).map((l) =>
        line(l, "info")
      );
      break;

    case "proxy info": {
      const proxy = state.world.proxies[cmd.args[0]];
      if (!proxy) {
        result.lines = [line(`Proxy ${cmd.args[0]} not found.`, "error")];
        break;
      }
      result.lines = [
        line(`ID: ${proxy.id}`),
        line(`Label: ${proxy.label}`),
        line(`Anonymity: ${(proxy.anonymity * 100).toFixed(1)}%`),
        line(`Heat: ${(proxy.heat * 100).toFixed(1)}%`),
        line(`Cost: ${proxy.costPerUse}c`),
      ];
      break;
    }

    case "route show":
      result.lines = [
        line(`Hops: ${state.route.hops.join(" -> ") || "Direct"}`),
        line(
          `Latency: ${state.route.latencyMs.toFixed(0)}ms | Anonymity: ${(
            state.route.anonymity * 100
          ).toFixed(1)}%`
        ),
      ];
      break;

    case "route add": {
      const proxyId = cmd.args[0];
      const proxy = state.world.proxies[proxyId];
      if (!proxy) {
        result.lines = [line(`Proxy ${proxyId} unavailable.`, "error")];
        break;
      }
      if (proxy.heat >= 1) {
        result.lines = [line(`Proxy ${proxyId} has burned out.`, "error")];
        break;
      }
      if (state.route.hops.includes(proxyId)) {
        result.lines = [line(`Proxy ${proxyId} already in route.`, "info")];
        break;
      }
      const heatIncrease = 0.15 + proxy.heat * 0.1; // more heat if already hot
      const heated = { ...proxy, heat: clamp(proxy.heat + heatIncrease, 0, 1) };
      const proxies = { ...state.world.proxies, [proxyId]: heated };
      const warnings: TerminalLine[] = [];
      if (heated.heat >= 0.8) {
        warnings.push(
          line(
            `WARNING: Proxy ${proxyId} is overheating (${(heated.heat * 100).toFixed(0)}%).`,
            "warning"
          )
        );
      }
      if (heated.heat >= 1) {
        warnings.push(
          line(`CRITICAL: Proxy ${proxyId} has burned out and is unusable.`, "error")
        );
      }
      result.state = {
        ...state,
        world: { ...state.world, proxies },
        route: buildRouteState([...state.route.hops, proxyId], proxies),
      };
      result.lines = [...warnings, line(`Proxy ${proxyId} appended.`, "success")];
      result.soundCue = "routeAdd";
      result.vfx = { type: "scan" };
      break;
    }

    case "route rm": {
      const proxyId = cmd.args[0];
      if (!state.route.hops.includes(proxyId)) {
        result.lines = [line(`${proxyId} is not part of the route.`, "error")];
        break;
      }
      const hops = state.route.hops.filter((hop) => hop !== proxyId);
      result.state = { ...state, route: buildRouteState(hops, state.world.proxies) };
      result.lines = [line(`Proxy ${proxyId} removed.`, "info")];
      break;
    }

    case "route clear":
      result.state = { ...state, route: buildRouteState([], state.world.proxies) };
      result.lines = [line("Route cleared.", "success")];
      break;

    case "probe": {
      const host = findHost(state.world, cmd.args[0]);
      const port = Number(cmd.args[1]);
      if (!host || Number.isNaN(port)) {
        result.lines = [line("Usage: probe <host> <port>", "error")];
        break;
      }
      const service = host.services.find((entry) => entry.port === port);
      result.lines = service
        ? [
            line(
              `${service.name} (${service.proto}) | ${
                service.banner ?? service.versionHint ?? "unknown"
              }`
            ),
            line(
              `Exposure: ${(service.exposure * 100).toFixed(1)}% | Vigilance: ${
                service.accessRules.multiFactor ? "MFA" : "standard"
              }`
            ),
          ]
        : [line(`Port ${port} filtered (no service).`, "info")];
      result.state = applyTrace(state, 5, ctx, host);
      break;
    }

    case "fingerprint": {
      const host = findHost(state.world, cmd.args[0]);
      if (!host) {
        result.lines = [line("Specify a host to fingerprint.", "error")];
        break;
      }
      result.lines = [
        line("OS guess: Linux 68%, FreeBSD 18%, Unknown 14%"),
        line("Latency analysis suggests hardened kernel.", "info"),
      ];
      result.state = applyTrace(state, 4, ctx, host);
      break;
    }

    case "pwd":
      result.lines = [line(`Working directory: ${state.session.workingDir ?? "/"}`)];
      break;

    case "ls": {
      if (!state.session.connectedHost) {
        result.lines = [line("No host connected.", "error")];
        break;
      }
      const host = state.world.hosts[state.session.connectedHost];
      const target = cmd.args[0] ?? state.session.workingDir ?? "/";
      result.lines = listFiles(host, target).map((l) => line(l));
      break;
    }

    case "cd": {
      if (!state.session.connectedHost) {
        result.lines = [line("No host connected.", "error")];
        break;
      }
      const nextDir = cmd.args[0] ?? "/";
      result.state = { ...state, session: { ...state.session, workingDir: nextDir } };
      result.lines = [line(`Set working dir to ${nextDir}`)];
      break;
    }

    case "cat": {
      if (!state.session.connectedHost) {
        result.lines = [line("No host connected.", "error")];
        break;
      }
      const host = state.world.hosts[state.session.connectedHost];
      const file = host.filesystem.find((entry) => entry.path === cmd.args[0]);
      result.lines = file
        ? [line(file.content ?? "[binary data]", "info")]
        : [line(`${cmd.args[0]} not found.`, "error")];
      break;
    }

    case "cp": {
      if (!state.session.connectedHost) {
        result.lines = [line("No host connected.", "error")];
        break;
      }
      const host = state.world.hosts[state.session.connectedHost];
      const [src, dst] = cmd.args;
      if (!src || !dst) {
        result.lines = [line("Usage: cp <src> <dst>", "error")];
        break;
      }
      const entry = host.filesystem.find((file) => file.path === src);
      if (!entry) {
        result.lines = [line(`${src} not found.`, "error")];
        break;
      }
      if (dst !== "@local") {
        result.lines = [line("Only @local destination is supported for now.", "info")];
        break;
      }
      const newItem: InventoryItem = {
        id: `inv-${ctx.nextId()}`,
        label: entry.name,
        source: host.id,
        path: entry.path,
        content: entry.content,
      };
      result.state = applyTrace(
        { ...state, inventory: [...state.inventory, newItem] },
        6,
        ctx,
        host
      );
      result.lines = [line(`Copied ${entry.name} into inventory.`, "success")];
      result.soundCue = "fileOp";
      result.vfx = { type: "success" };
      break;
    }

    case "rm": {
      if (!state.session.connectedHost) {
        result.lines = [line("No host connected.", "error")];
        break;
      }
      const target = cmd.args[0];
      if (!target) {
        result.lines = [line("Usage: rm <file>", "error")];
        break;
      }
      const host = state.world.hosts[state.session.connectedHost];
      const updatedHost = {
        ...host,
        filesystem: host.filesystem.filter((entry) => entry.path !== target),
      };
      result.state = applyTrace(withHost(state, updatedHost), 7, ctx, host);
      result.lines = [line(`Removed ${target}.`, "success")];
      break;
    }

    case "edit": {
      if (!state.session.connectedHost) {
        result.lines = [line("No host connected.", "error")];
        break;
      }
      const [target, data] = cmd.args;
      if (!target || !data) {
        result.lines = [line("Usage: edit <file> key=value", "error")];
        break;
      }
      const host = state.world.hosts[state.session.connectedHost];
      const file = host.filesystem.find((entry) => entry.path === target);
      if (!file) {
        result.lines = [line(`${target} not found.`, "error")];
        break;
      }
      const updatedHost = {
        ...host,
        filesystem: host.filesystem.map((entry) =>
          entry.path === target ? { ...entry, content: `${data} (tampered)` } : entry
        ),
      };
      result.state = applyTrace(withHost(state, updatedHost), 5, ctx, host);
      result.lines = [line(`Patched ${target}.`, "success")];
      break;
    }

    case "wipe logs": {
      if (!state.session.connectedHost) {
        result.lines = [line("No host connected.", "error")];
        break;
      }
      const host = state.world.hosts[state.session.connectedHost];
      result.state = applyTrace(withHost(state, { ...host, logs: [] }), 10, ctx, host);
      result.lines = [line("Logs wiped. Trace noise spiked.", "warning")];
      result.vfx = { type: "alert" };
      result.soundCue = "alert";
      break;
    }

    case "disconnect":
    case "exit": {
      const wasConnected = !!state.session.connectedHost;
      result.state = {
        ...state,
        session: { scannedHosts: asSet(state.session.scannedHosts) },
      };
      result.lines = [
        line(
          wasConnected ? "Disconnected. Trace will decay while idle." : "No active connection.",
          "info"
        ),
      ];
      break;
    }

    case "market":
      result.lines = [
        line(
          "Market rotation offline. Check back after you rack more reputation.",
          "info"
        ),
      ];
      break;

    case "buy":
      result.lines = [line("Store coming soon.", "info")];
      break;
  }

  return result;
}
