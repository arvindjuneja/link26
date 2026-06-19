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

import type {
  EvidenceCard,
  ExposureChannel,
  GameState,
  Host,
  InventoryItem,
  TerminalLine,
  VfxEvent,
} from "@/types/game";
import type { CommandContext } from "@/app/lib/game/context";
import type { ScanAnimation, TimedEffect } from "@/app/lib/game/effects";
import { helpOutput } from "@/app/lib/game/commands";
import {
  formatMissionDetail,
  formatProxyTable,
  formatScanOutput,
  missionSummaryLine,
} from "@/app/lib/game/formatting";
import { evaluateMission, setMissionStatus, syncInbox } from "@/app/lib/game/missionLogic";
import { CAMPAIGN } from "@/app/lib/game/campaign";
import { applyChannelNoise, EXPOSURE_CHANNELS, missionOutcome } from "@/app/lib/game/exposure";
import { GEAR, channelMitigation, gearById, nextCost } from "@/app/lib/game/gear";
import {
  buildRouteState,
  clamp,
  findEmitter,
  findHost,
  findPerson,
  listFiles,
} from "@/app/lib/game/worldQueries";

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
  /** Declarative timeline of staged presentation for the store to play. */
  effects?: TimedEffect[];
}

/**
 * Commands fully owned by the pure reducer — now the entire command set. The
 * staged-animation commands (scan/connect) express their drama through the
 * effects channel rather than calling setTimeout directly. Anything not listed
 * here is an unknown command, handled by the store's fallback.
 */
const HANDLED = new Set([
  // mission + status
  "help",
  "clear",
  "status",
  "settings",
  "inbox",
  "read",
  "missions",
  "accept",
  "submit",
  "campaign",
  // proxy / route
  "proxy list",
  "proxy info",
  "route show",
  "route add",
  "route rm",
  "route clear",
  // recon
  "scan",
  "probe",
  "fingerprint",
  "osint",
  "sweep",
  "collect rf",
  "deploy sensor",
  "acquire",
  "evidence",
  // session / filesystem
  "connect",
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

/** Add exposure noise to one channel, stamping the injected clock. Pure. */
function applyExposure(
  state: GameState,
  ch: ExposureChannel,
  noise: number,
  ctx: CommandContext,
  host?: Host
): GameState {
  return {
    ...state,
    exposure: applyChannelNoise(
      state.exposure,
      ch,
      noise,
      state.route,
      host,
      channelMitigation(state.gear, ch)
    ),
    time: ctx.now,
  };
}

/** Append evidence cards, de-duped by (sourceId, factKind). Pure. */
function addEvidence(state: GameState, cards: EvidenceCard[]): GameState {
  const seen = new Set(state.evidence.map((e) => `${e.sourceId}:${e.factKind}`));
  const fresh = cards.filter((c) => !seen.has(`${c.sourceId}:${c.factKind}`));
  if (!fresh.length) return state;
  return { ...state, evidence: [...state.evidence, ...fresh] };
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

    case "settings":
      result.lines = [line("Settings are currently handled by the terminal. Coming soon.", "info")];
      break;

    case "status":
      result.lines = [
        line(`Cash: ${state.cash}c | Reputation: ${state.reputation}`),
        line("Exposure board:"),
        ...EXPOSURE_CHANNELS.map((ch) =>
          line(
            `  ${ch.padEnd(11)} ${state.exposure[ch].level.toFixed(1).padStart(5)}%  ${state.exposure[ch].status}`,
            state.exposure[ch].status === "CALM" ? "info" : "warning"
          )
        ),
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
      if (!mission) {
        result.lines = [line(`Mission ${missionId} not found.`, "error")];
        break;
      }
      const detail = formatMissionDetail(mission).map((text) => line(text, "info"));
      if (mission.scopeNote) detail.push(line(`RoE: ${mission.scopeNote}`, "warning"));
      result.lines = detail;
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
      if (mission.status === "locked") {
        result.lines = [line(`${mission.title} is locked — finish the prior chapter first.`, "warning")];
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
          line("Check your inventory, evidence board, or edit the target file.", "info"),
        ];
        break;
      }

      // Risk-dial: pushing for bonus intel holds the line longer -> NETWORK spike,
      // which can flip the exit from clean to hot/burned. The greed decision.
      const push = cmd.flags.includes("push") || cmd.flags.includes("greedy");
      const afterPush = push ? applyExposure(state, "NETWORK", 25, ctx) : state;
      const outcome = missionOutcome(afterPush.exposure);

      let cash = mission.reward.cash;
      let reputation = mission.reward.reputation;
      let streak = afterPush.streak;
      const outcomeLines: TerminalLine[] = [];

      if (outcome === "clean") {
        const mult = 1 + Math.min(0.5, 0.1 * afterPush.streak); // bonus from prior streak
        cash = Math.round(cash * mult);
        streak = afterPush.streak + 1;
        outcomeLines.push(line("GHOST — clean exit. No one knows you were here.", "success"));
        if (streak > 1) {
          outcomeLines.push(line(`  clean streak x${streak} (+${Math.round((mult - 1) * 100)}% bonus)`, "success"));
        }
      } else if (outcome === "hot") {
        streak = 0;
        outcomeLines.push(line("HOT — objective met, but you tripped a tracer. Full pay; watch your back.", "warning"));
      } else {
        streak = 0;
        cash = Math.round(cash * 0.5);
        reputation = Math.max(0, reputation - 10);
        outcomeLines.push(line("BURNED — LOCKDOWN closed the window. You got out, but it cost you.", "error"));
      }

      if (push) {
        // The greed pays off only if you didn't get burned — pushing into a
        // lockdown loses you the bonus, so push can't out-earn caution.
        if (outcome === "burned") {
          outcomeLines.unshift(line("[RISK] Pushed too hard — burned. No bonus.", "error"));
        } else {
          cash = Math.round(cash * 1.6);
          outcomeLines.unshift(line("[RISK] Pushed for bonus intel — exposure spiked.", "warning"));
        }
      }

      // Non-clean exits feed ATTRIBUTION (your profile builds when you get noticed).
      // Honour the 'launder' gear, which exists specifically to flatten this channel.
      let exposure = afterPush.exposure;
      if (outcome !== "clean") {
        exposure = applyChannelNoise(
          exposure,
          "ATTRIBUTION",
          outcome === "burned" ? 18 : 8,
          afterPush.route,
          undefined,
          channelMitigation(afterPush.gear, "ATTRIBUTION")
        );
      }

      // Mark complete; if this was a campaign chapter, unlock the next one.
      const isChapter = mission.chapterIndex !== undefined;
      const nextChapter = isChapter ? mission.chapterIndex! + 1 : -1;
      const activeMissions = afterPush.activeMissions.map((m) => {
        if (m.id === missionId) return { ...m, status: "completed" as const, completed: true };
        if (isChapter && m.chapterIndex === nextChapter && m.status === "locked") {
          return { ...m, status: "available" as const };
        }
        return m;
      });
      result.state = {
        ...afterPush,
        exposure,
        cash: afterPush.cash + cash,
        reputation: afterPush.reputation + reputation,
        streak,
        activeMissions,
        inbox: syncInbox(activeMissions),
        campaign: isChapter
          ? { chapter: Math.max(afterPush.campaign.chapter, nextChapter) }
          : afterPush.campaign,
      };
      result.lines = [
        line(`Mission ${mission.title} completed!`, "success"),
        ...outcomeLines,
        line(`+${cash}c  +${reputation} reputation`, outcome === "burned" ? "warning" : "success"),
      ];
      // Mercer's payoff + the next chapter's briefing.
      if (isChapter) {
        const chapter = CAMPAIGN[mission.chapterIndex!];
        if (chapter) result.lines.push(line(""), line(`MERCER: ${chapter.outro}`, "info"));
        const next = CAMPAIGN[nextChapter];
        if (next) result.lines.push(line(`MERCER: Next — "${next.title}". ${next.intro}`, "info"));
      }
      result.soundCue = outcome === "clean" ? "success" : "alert";
      result.vfx = outcome === "burned" ? { type: "alert" } : { type: "success" };
      break;
    }

    case "campaign": {
      const cur = state.campaign.chapter;
      result.lines = [
        line(`Campaign — Act I  (${Math.min(cur, CAMPAIGN.length)}/${CAMPAIGN.length} done)`),
        ...CAMPAIGN.map((c, i) =>
          line(
            `  ${i < cur ? "[done]" : i === cur ? "[ now]" : "[lock]"} ${c.title}`,
            i === cur ? "success" : "info"
          )
        ),
      ];
      const chapter = CAMPAIGN[cur];
      result.lines.push(
        line(""),
        chapter
          ? line(`MERCER: ${chapter.intro}`, "info")
          : line("MERCER: Act I's done. The board's yours now, operator.", "info")
      );
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
      result.state = applyExposure(state, "NETWORK", 5, ctx, host);
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
      result.state = applyExposure(state, "NETWORK", 4, ctx, host);
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
      result.state = applyExposure(
        { ...state, inventory: [...state.inventory, newItem] },
        "NETWORK",
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
      result.state = applyExposure(withHost(state, updatedHost), "NETWORK", 7, ctx, host);
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
      result.state = applyExposure(withHost(state, updatedHost), "NETWORK", 5, ctx, host);
      result.lines = [line(`Patched ${target}.`, "success")];
      break;
    }

    case "wipe logs": {
      if (!state.session.connectedHost) {
        result.lines = [line("No host connected.", "error")];
        break;
      }
      const host = state.world.hosts[state.session.connectedHost];
      result.state = applyExposure(withHost(state, { ...host, logs: [] }), "NETWORK", 10, ctx, host);
      result.lines = [line("Logs wiped. NETWORK noise spiked.", "warning")];
      result.vfx = { type: "alert" };
      result.soundCue = "alert";
      break;
    }

    case "disconnect":
    case "exit": {
      const wasConnected = !!state.session.connectedHost;
      // End the live session but keep persistent intel: scanned hosts and any
      // acquired access credentials (the player paid exposure for those).
      result.state = {
        ...state,
        session: {
          scannedHosts: asSet(state.session.scannedHosts),
          acquired: state.session.acquired ?? [],
        },
      };
      result.lines = [
        line(
          wasConnected ? "Disconnected. Trace will decay while idle." : "No active connection.",
          "info"
        ),
      ];
      break;
    }

    case "scan": {
      const host = findHost(state.world, cmd.args[0]);
      if (!host) {
        result.lines = [line(`Host ${cmd.args[0]} not found.`, "error")];
        break;
      }
      const hops = state.route.hops;
      const hasRoute = hops.length > 0;
      const scanMode = cmd.flags.includes("stealth")
        ? "STEALTH"
        : cmd.flags.includes("aggr")
        ? "AGGRESSIVE"
        : "STANDARD";
      result.lines = [
        line(`[SCAN] Initiating ${scanMode} scan on ${host.label}`, "info"),
        line(
          `[ROUTE] ${
            hasRoute
              ? `Routing through ${hops.length} proxy hop${hops.length > 1 ? "s" : ""}...`
              : "DIRECT CONNECTION - No proxy route!"
          }`,
          hasRoute ? "info" : "warning"
        ),
      ];
      const anim: ScanAnimation = {
        fromNode: hasRoute ? hops[hops.length - 1] : "player",
        toNode: host.id,
        throughProxies: [...hops],
        phase: "routing",
        progress: 0,
        startTime: ctx.now,
      };
      const baseNoise = cmd.flags.includes("stealth") ? 6 : cmd.flags.includes("aggr") ? 18 : 12;
      const scanned = new Set(asSet(state.session.scannedHosts));
      scanned.add(host.id);
      result.state = applyExposure(
        { ...state, session: { ...state.session, currentTarget: host.id, scannedHosts: scanned } },
        "NETWORK",
        baseNoise,
        ctx,
        host
      );
      result.soundCue = "scan";
      result.vfx = { type: "scan", target: host.id };
      result.effects = [
        { atMs: 0, anim: { type: "set", value: anim }, isExecuting: true, executionPhase: "routing" },
        {
          atMs: 400,
          lines: [line(`[PROBE] Enumerating ports on ${host.label}...`, "info")],
          anim: { type: "patch", value: { phase: "scanning", progress: 0.5 } },
          executionPhase: "executing",
        },
        {
          atMs: 800,
          lines: [line(`[PROBE] Fingerprinting services...`, "info")],
          anim: { type: "patch", value: { progress: 0.75 } },
        },
        {
          atMs: 1200,
          lines: [
            line(`[COMPLETE] Scan finished.`, "success"),
            ...formatScanOutput(host).map((l) => line(l, "success")),
          ],
          anim: { type: "patch", value: { phase: "complete", progress: 1 } },
          executionPhase: "complete",
          isExecuting: false,
        },
        { atMs: 2700, anim: { type: "clear" }, executionPhase: "idle" },
      ];
      break;
    }

    case "connect": {
      const host = findHost(state.world, cmd.args[0]);
      if (!host) {
        result.lines = [line(`Host ${cmd.args[0]} not reachable.`, "error")];
        break;
      }
      const scanned = new Set(asSet(state.session.scannedHosts));
      const wasScanned = scanned.has(host.id);
      const hops = state.route.hops;
      const hasRoute = hops.length > 0;
      result.lines = [
        line(`[CONNECT] Initiating session to ${host.label}...`, "info"),
        line(
          `[ROUTE] ${
            hasRoute
              ? `Establishing tunnel through ${hops.length} hop${hops.length > 1 ? "s" : ""}`
              : "WARNING: Direct connection - no proxy!"
          }`,
          hasRoute ? "info" : "warning"
        ),
      ];
      const anim: ScanAnimation = {
        fromNode: hasRoute ? hops[hops.length - 1] : "player",
        toNode: host.id,
        throughProxies: [...hops],
        phase: "routing",
        progress: 0,
        startTime: ctx.now,
      };
      let connectionNoise = 15;
      if (!wasScanned) connectionNoise += 35;
      if (!hasRoute) connectionNoise += 40;
      if (!wasScanned && !hasRoute) connectionNoise += 20;
      // Acquired credentials authenticate the session — far less noise than a cold pop.
      if ((state.session.acquired ?? []).includes(host.id)) {
        connectionNoise = Math.max(5, connectionNoise - 25);
      }
      result.state = applyExposure(
        {
          ...state,
          session: {
            ...state.session,
            connectedHost: host.id,
            currentTarget: host.id,
            workingDir: "/",
            scannedHosts: scanned,
          },
        },
        "NETWORK",
        connectionNoise,
        ctx,
        host
      );
      const finalTrace = result.state.exposure.NETWORK.level;
      if (connectionNoise > 20 || finalTrace > 25) {
        result.vfx = { type: "alert", target: host.id };
        result.soundCue = "alert";
      } else {
        result.soundCue = "connect";
        result.vfx = { type: "connect", target: host.id };
      }
      const effects: TimedEffect[] = [
        { atMs: 0, anim: { type: "set", value: anim }, isExecuting: true, executionPhase: "routing" },
      ];
      if (!wasScanned) {
        effects.push({
          atMs: 300,
          lines: [line(`[!] WARNING: Host not scanned. IDS triggered.`, "warning")],
        });
      }
      if (!hasRoute) {
        effects.push({
          atMs: 500,
          lines: [line(`[!] WARNING: No proxy route. IP exposed.`, "warning")],
        });
      }
      effects.push({
        atMs: 700,
        lines: [line(`[HANDSHAKE] Negotiating encryption...`, "info")],
        anim: { type: "patch", value: { phase: "scanning", progress: 0.6 } },
        executionPhase: "executing",
      });
      effects.push({
        atMs: 1100,
        lines: [
          line(
            `[SESSION] Connection established to ${host.label}`,
            hasRoute && wasScanned ? "success" : "warning"
          ),
          line(
            `[TRACE] Noise spike: +${connectionNoise} | Current: ${finalTrace.toFixed(1)}%`,
            connectionNoise > 30 ? "error" : "warning"
          ),
        ],
        anim: { type: "patch", value: { phase: "complete", progress: 1 } },
        executionPhase: "complete",
        isExecuting: false,
      });
      effects.push({ atMs: 2100, anim: { type: "clear" }, executionPhase: "idle" });
      result.effects = effects;
      break;
    }

    case "osint": {
      const person = findPerson(state.world, cmd.args[0]);
      if (!person) {
        result.lines = [line(`No subject matches "${cmd.args[0] ?? ""}".`, "error")];
        break;
      }
      const active = cmd.flags.includes("active");
      const facts = person.facts.filter((f) => (active ? true : f.passive));
      const cards: EvidenceCard[] = facts.map((f) => ({
        id: ctx.nextId(),
        sourceKind: "person",
        sourceId: person.id,
        factKind: f.kind,
        label: f.label,
        value: f.value,
      }));
      // Passive collection is near-zero footprint; active probing of a watched
      // entity is the expensive, recognizable OSINT tradeoff.
      const footprint = active ? 8 + (person.watched ? 6 : 0) : 2;
      result.state = applyExposure(addEvidence(state, cards), "FOOTPRINT", footprint, ctx);
      result.lines = [
        line(
          `[OSINT] ${active ? "ACTIVE" : "PASSIVE"} sweep on ${person.label}${
            active && person.watched ? "  (watched entity — high footprint)" : ""
          }`,
          active ? "warning" : "info"
        ),
        ...facts.map((f) => line(`  + ${f.label}: ${f.value}`, "success")),
        line(
          active
            ? "  active probing wrote to FOOTPRINT."
            : "  passive only — run with --active to surface breach/device leads.",
          "info"
        ),
      ];
      result.soundCue = "scan";
      result.vfx = { type: "scan" };
      break;
    }

    case "sweep": {
      const emitters = Object.values(state.world.emitters);
      result.lines = [
        line("[ELINT] Sweeping the RF spectrum — wide-band passive scan..."),
        ...emitters.map((e) => {
          const known = state.evidence.some(
            (c) => c.sourceId === e.id && c.factKind === "signature"
          );
          return line(
            `  ${e.band.padEnd(8)} ${e.label.padEnd(26)} ${known ? "[characterized]" : "[unknown emitter]"}`,
            known ? "success" : "info"
          );
        }),
        line("  characterize one with: collect rf <host|emitter>", "info"),
      ];
      result.state = applyExposure(state, "RF", 4, ctx);
      result.soundCue = "scan";
      result.vfx = { type: "scan" };
      break;
    }

    case "collect rf":
    case "deploy sensor": {
      const emitter = findEmitter(state.world, cmd.args[0]);
      if (!emitter) {
        result.lines = [
          line(`No emitter at "${cmd.args[0] ?? ""}". Pass a host id or emitter id.`, "error"),
        ];
        break;
      }
      const card: EvidenceCard = {
        id: ctx.nextId(),
        sourceKind: "emitter",
        sourceId: emitter.id,
        factKind: "signature",
        label: `${emitter.band} emitter`,
        value: emitter.signature,
      };
      result.state = applyExposure(addEvidence(state, [card]), "RF", 10, ctx);
      result.lines = [
        line(`[RF] Tasking remote sensor at ${emitter.label}...`, "info"),
        line(`  band ${emitter.band} | signature ${emitter.signature}`, "success"),
        line("  emitter characterized. RF exposure rising (DF risk).", "warning"),
      ];
      result.soundCue = "scan";
      result.vfx = { type: "scan" };
      break;
    }

    case "acquire": {
      const host = findHost(state.world, cmd.args[0]);
      if (!host) {
        result.lines = [line(`Host ${cmd.args[0] ?? ""} not found.`, "error")];
        break;
      }
      const spray = cmd.flags.includes("spray");
      const orgPerson = state.world.people[`person-${host.id}`];
      const hasCreds =
        !!orgPerson &&
        state.evidence.some((e) => e.sourceId === orgPerson.id && e.factKind === "breach");
      if (!hasCreds && !spray) {
        result.lines = [
          line(`No harvested credentials for ${host.label}.`, "error"),
          line(
            `Run 'osint ${orgPerson?.label ?? "<subject>"} --active' to surface a breach record, or 'acquire ${
              cmd.args[0]
            } --spray' (loud).`,
            "info"
          ),
        ];
        break;
      }
      // Probabilistic gate — never a working technique, a roll against posture.
      const base = hasCreds ? 0.75 : 0.35;
      const chance = clamp(base - host.monitoring * 0.4, 0.05, 0.95);
      const success = ctx.random() < chance;
      const noise = (spray ? 22 : 8) + (success ? 0 : 6);
      let next = applyExposure(state, "NETWORK", noise, ctx, host);
      if (success) {
        const acquired = Array.from(new Set([...(state.session.acquired ?? []), host.id]));
        next = { ...next, session: { ...next.session, acquired } };
        result.lines = [
          line(`[ACCESS] ${spray ? "Spray" : "Credential"} attempt on ${host.label}...`, "info"),
          line(`  access acquired. 'connect ${host.id}' will authenticate (lower noise).`, "success"),
        ];
        result.soundCue = "success";
        result.vfx = { type: "success" };
      } else {
        result.lines = [
          line(`[ACCESS] ${spray ? "Spray" : "Credential"} attempt on ${host.label}...`, "info"),
          line("  rejected. NETWORK exposure spiked.", "warning"),
        ];
        result.soundCue = "alert";
        result.vfx = { type: "alert" };
      }
      result.state = next;
      break;
    }

    case "evidence": {
      if (!state.evidence.length) {
        result.lines = [line("No evidence collected. Try 'osint <subject>' or 'collect rf <host>'.", "info")];
        break;
      }
      result.lines = [
        line(`Evidence board (${state.evidence.length} cards):`),
        ...state.evidence.map((e) =>
          line(`  [${e.sourceId}] ${e.label}: ${e.value}`, "info")
        ),
      ];
      break;
    }

    case "market": {
      result.lines = [
        line("Market — gear flattens an exposure channel's noise:"),
        ...GEAR.map((g) => {
          const tier = state.gear[g.id] ?? 0;
          const maxed = tier >= g.maxTier;
          const price = maxed ? "MAXED" : `${nextCost(g, tier)}c`;
          return line(
            `  ${g.id.padEnd(9)} T${tier}/${g.maxTier}  ${price.padEnd(7)} [${g.channel}] ${g.label}`,
            "info"
          );
        }),
        line(`Cash: ${state.cash}c — buy with 'buy <id>'.`),
      ];
      break;
    }

    case "buy": {
      const item = gearById(cmd.args[0]);
      if (!item) {
        result.lines = [line(`Unknown item "${cmd.args[0] ?? ""}". See 'market'.`, "error")];
        break;
      }
      const tier = state.gear[item.id] ?? 0;
      if (tier >= item.maxTier) {
        result.lines = [line(`${item.label} is already at max tier.`, "info")];
        break;
      }
      const cost = nextCost(item, tier);
      if (state.cash < cost) {
        result.lines = [line(`Insufficient cash (${cost}c needed, have ${state.cash}c).`, "error")];
        break;
      }
      result.state = {
        ...state,
        cash: state.cash - cost,
        gear: { ...state.gear, [item.id]: tier + 1 },
      };
      result.lines = [
        line(`Acquired ${item.label} T${tier + 1}.`, "success"),
        line(`  ${item.channel} noise now flattened — that fear gets quieter.`, "info"),
      ];
      result.soundCue = "success";
      result.vfx = { type: "success" };
      break;
    }
  }

  return result;
}
