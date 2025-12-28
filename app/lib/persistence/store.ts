import { create } from "zustand";
import type {
  GameState,
  Mission,
  MissionSummary,
  ProxyNode,
  RouteState,
  TerminalLine,
  VfxEvent,
  ToolId,
  ToolInstance,
  Host,
  InventoryItem,
} from "@/types/game";
import { generateWorld } from "@/app/lib/game/worldgen";
import { generateMissions } from "@/app/lib/game/missions";
import { helpOutput } from "@/app/lib/game/commands";
import {
  formatMissionDetail,
  formatProxyTable,
  formatScanOutput,
  missionSummaryLine,
} from "@/app/lib/game/formatting";
import { addTraceNoise, decayTrace, getTraceStatus } from "@/app/lib/game/trace";
import { localSaveProvider } from "./saveLocalIndexedDb";
import { nowTimestamp } from "@/app/lib/util/time";

const lineId = () =>
  typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `line-${Date.now()}-${Math.random().toString(16).slice(2)}`;

const multiWordCommands = [
  "proxy list",
  "proxy info",
  "route add",
  "route rm",
  "route show",
  "route clear",
  "wipe logs",
];

type SoundCue = "click" | "beep" | "alert" | "scan" | "connect" | "success" | "routeAdd" | "fileOp" | null;

// Scan animation state for visual feedback on map
export interface ScanAnimation {
  fromNode: string | null;  // Starting node (last proxy or "player")
  toNode: string;           // Target host
  throughProxies: string[]; // Route hops
  phase: "routing" | "scanning" | "complete";
  progress: number;         // 0-1
  startTime: number;
}

// Execution phases for visual command feedback
type ExecutionPhase = "idle" | "initiating" | "routing" | "executing" | "complete";

const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));

const buildRouteState = (hops: string[], proxies: Record<string, ProxyNode>): RouteState => {
  let latency = 0;
  let anonymity = 0;
  hops.forEach((proxyId) => {
    const node = proxies[proxyId];
    if (!node) return;
    latency += 30 + node.costPerUse;
    anonymity = 1 - (1 - anonymity) * (1 - clamp(node.anonymity, 0, 1));
  });
  return {
    hops: [...hops],
    latencyMs: latency,
    anonymity: clamp(anonymity, 0, 0.99),
  };
};

const missionSummaryFromMission = (mission: Mission): MissionSummary => ({
  id: mission.id,
  title: mission.title,
  description: mission.description,
  reward: mission.reward,
  targetHost: mission.objective.hostId,
  deadline: mission.deadline,
  status: mission.status,
});

const syncInbox = (missions: Mission[]): MissionSummary[] => missions.map(missionSummaryFromMission);

const findHost = (world: GameState["world"], query?: string): Host | undefined => {
  if (!query) return undefined;
  const normalized = query.toLowerCase();
  return Object.values(world.hosts).find(
    (host) => host.id === normalized || host.label.toLowerCase().includes(normalized) || host.id === query
  );
};

const createInitialState = (): GameState => {
  const world = generateWorld();
  const { inbox, missions } = generateMissions(world);
  const traceLevel = 8;
  const tools: Record<ToolId, ToolInstance> = {
    scanner: {
      id: "scanner",
      level: 1,
      label: "ScanSuite Alpha",
      description: "Base recon module.",
    },
    proxyChain: {
      id: "proxyChain",
      level: 1,
      label: "Proxy Chain",
      description: "Sneaks traffic through proxy hops.",
    },
    wiper: {
      id: "wiper",
      level: 1,
      label: "Logger Wiper",
      description: "Clears trace signatures (use sparingly).",
    },
    tracker: {
      id: "tracker",
      level: 1,
      label: "Pulse Tracker",
      description: "Tracks host changes.",
    },
  };

  return {
    time: nowTimestamp(),
    cash: 4200,
    reputation: 36,
    trace: {
      level: traceLevel,
      status: getTraceStatus(traceLevel),
      lastEvent: "Session initialized",
    },
    route: {
      hops: [],
      latencyMs: 0,
      anonymity: 0,
    },
    playerTools: tools,
    inbox,
    activeMissions: missions,
    world,
    session: { scannedHosts: new Set() },
    inventory: [],
  };
};

const parseCommand = (input: string) => {
  const tokens = input.split(/\s+/).filter(Boolean);
  if (!tokens.length) return { key: "", args: [], flags: [] };
  let key = tokens[0].toLowerCase();
  let args = tokens.slice(1);
  const candidate = tokens.length > 1 ? `${tokens[0].toLowerCase()} ${tokens[1].toLowerCase()}` : "";
  if (multiWordCommands.includes(candidate)) {
    key = candidate;
    args = tokens.slice(2);
  }
  const flags = args.filter((token) => token.startsWith("--")).map((token) => token.replace(/^--/, ""));
  const filtered = args.filter((token) => !token.startsWith("--"));
  return { key, args: filtered, flags };
};

const listFiles = (host: Host, path: string): string[] => {
  const normalized = path === "/" ? "/" : path.replace(/\/+$/, "");
  const entries = host.filesystem
    .filter((entry) => {
      if (normalized === "/") return entry.path.split("/").filter(Boolean).length <= 2;
      return entry.path.startsWith(`${normalized}/`);
    })
    .map((entry) => `${entry.type.padEnd(4)} ${entry.name}`);
  return entries.length ? entries : ["<empty directory>"];
};

const evaluateMission = (state: GameState, mission: Mission): boolean => {
  const { objective } = mission;
  const host = state.world.hosts[objective.hostId];
  if (!host) return false;

  switch (objective.type) {
    case "exfil":
      return state.inventory.some((item) => item.source === objective.hostId && item.path === objective.targetPath);
    case "modify": {
      const fileEntry = host.filesystem.find((entry) => entry.path === objective.targetPath);
      return !!fileEntry?.content?.includes("tampered") || !!fileEntry?.content?.includes("state patched");
    }
    case "plant":
      return host.filesystem.some((entry) => entry.path === objective.targetPath && entry.content?.includes("tracer"));
    default:
      return false;
  }
};

const createLine = (text: string, type: TerminalLine["type"] = "info"): TerminalLine => ({
  id: lineId(),
  text,
  type,
});

interface GameStoreState {
  gameState: GameState;
  terminalLines: TerminalLine[];
  commandHistory: string[];
  lastVfxEvent: VfxEvent | null;
  soundCue: SoundCue;
  isExecuting: boolean;
  executionPhase: ExecutionPhase;
  scanAnimation: ScanAnimation | null;
  runCommand: (input: string) => Promise<void>;
  clearTerminal: () => void;
  loadSavedState: () => Promise<void>;
  decayTraceTick: () => void;
  acknowledgeSoundCue: () => void;
  addTerminalLine: (line: TerminalLine) => void;
  resetWorld: () => Promise<void>;
  setScanAnimation: (animation: ScanAnimation | null) => void;
  setExecutionPhase: (phase: ExecutionPhase) => void;
}

const welcomeMessage = (): TerminalLine[] => [
  createLine("╔═══════════════════════════════════════════════════════╗", "info"),
  createLine("║               Link26 :: Terminal v2026.1               ║", "info"),
  createLine("║         A sentimental road back to Uplink times        ║", "info"),
  createLine("╚═══════════════════════════════════════════════════════╝", "info"),
  createLine("", "info"),
  createLine("Welcome back, operator. The network awaits.", "info"),
  createLine("Your mission inbox contains 3 contracts.", "info"),
  createLine("", "info"),
  createLine("Type 'inbox' to view missions. Type 'help' for commands.", "info"),
  createLine("", "info"),
];

export const useGameStore = create<GameStoreState>()((set, get) => ({
  gameState: createInitialState(),
  terminalLines: welcomeMessage(),
  commandHistory: [],
  lastVfxEvent: null,
  soundCue: null,
  isExecuting: false,
  executionPhase: "idle" as ExecutionPhase,
  scanAnimation: null,
  addTerminalLine: (line) =>
    set((state) => ({ terminalLines: [...state.terminalLines, line] })),
  clearTerminal: () => set({ terminalLines: [] }),
  acknowledgeSoundCue: () => set({ soundCue: null }),
  setScanAnimation: (animation) => set({ scanAnimation: animation }),
  setExecutionPhase: (phase) => set({ executionPhase: phase, isExecuting: phase !== "idle" && phase !== "complete" }),
  resetWorld: async () => {
    // Clear saved state from IndexedDB
    await localSaveProvider.clear();
    // Generate fresh world
    const freshState = createInitialState();
    set({
      gameState: freshState,
      terminalLines: welcomeMessage(),
      commandHistory: [],
      lastVfxEvent: null,
      soundCue: null,
      isExecuting: false,
      executionPhase: "idle",
      scanAnimation: null,
    });
  },
  loadSavedState: async () => {
    const saved = await localSaveProvider.load();
    if (saved) {
      // Convert scannedHosts array back to Set
      if (saved.session && Array.isArray(saved.session.scannedHosts)) {
        saved.session.scannedHosts = new Set(saved.session.scannedHosts);
      } else if (saved.session && !saved.session.scannedHosts) {
        saved.session.scannedHosts = new Set();
      }
      set({ gameState: saved });
    }
  },
  decayTraceTick: () =>
    set((state) => {
      // Only decay if not connected (idle state)
      if (!state.gameState.session.connectedHost) {
        return { gameState: { ...state.gameState, trace: decayTrace(state.gameState.trace) } };
      }
      return state; // No decay while connected
    }),
  runCommand: async (rawInput) => {
    const trimmed = rawInput.trim();
    if (!trimmed) return;

    const { key, args, flags } = parseCommand(trimmed);
    const state = get().gameState;
    let nextState = { ...state };
    const terminalLines: TerminalLine[] = [];
    let soundCue: SoundCue = "click";
    let vfxEvent: VfxEvent | null = null;
    let clearScreen = false;

    const session = { ...state.session };
    const route = { ...state.route };

    const emit = (lines: TerminalLine[]) => {
      terminalLines.push(...lines);
    };

    const setMissionStatus = (missionId: string, status: MissionSummary["status"]) => {
      const updatedMissions = nextState.activeMissions.map((mission) =>
        mission.id === missionId ? { ...mission, status } : mission
      );
      nextState = { ...nextState, activeMissions: updatedMissions, inbox: syncInbox(updatedMissions) };
    };

    const appendTrace = (noise: number, host?: Host) => {
      const trace = addTraceNoise(nextState.trace, noise, route, host);
      nextState = { ...nextState, trace, time: nowTimestamp() };
    };

    switch (key) {
      case "":
        emit([createLine("No command entered.", "error")]);
        break;
      case "help":
        emit(helpOutput());
        soundCue = "beep";
        break;
      case "clear":
        emit([createLine("Terminal cleared.", "success")]);
        clearScreen = true;
        break;
      case "status":
        emit([
          createLine(`Cash: ${nextState.cash}c | Reputation: ${nextState.reputation}`),
          createLine(`Trace: ${nextState.trace.level.toFixed(1)}% (${nextState.trace.status})`),
          createLine(`Route anonym.: ${(route.anonymity * 100).toFixed(1)}% | Hops: ${route.hops.length}`),
          createLine(
            `Connected host: ${session.connectedHost ?? "none"} | Working dir: ${session.workingDir ?? "/"}`
          ),
        ]);
        soundCue = "beep";
        break;
      case "settings":
        emit([createLine("Settings are currently handled by the terminal. Coming soon.", "info")]);
        break;
      case "inbox":
        emit(nextState.inbox.map((mission) => createLine(missionSummaryLine(mission), "info")));
        break;
      case "read": {
        const missionId = args[0];
        const mission = nextState.activeMissions.find((m) => m.id === missionId);
        if (!mission) {
          emit([createLine(`Mission ${missionId} not found.`, "error")]);
        } else {
          emit(formatMissionDetail(mission).map((line) => createLine(line, "info")));
        }
        break;
      }
      case "accept": {
        const missionId = args[0];
        const mission = nextState.activeMissions.find((m) => m.id === missionId);
        if (!mission) {
          emit([createLine(`Mission ${missionId} not found.`, "error")]);
          break;
        }
        if (mission.status !== "available") {
          emit([createLine(`${mission.title} is already ${mission.status}.`, "info")]);
          break;
        }
        setMissionStatus(missionId, "accepted");
        emit([createLine(`Mission ${mission.title} accepted.`, "success")]);
        soundCue = "beep";
        vfxEvent = { type: "success" };
        break;
      }
      case "missions": {
        const active = nextState.activeMissions.filter((mission) => mission.status === "accepted");
        if (!active.length) {
          emit([createLine("No active missions.", "info")]);
        } else {
          emit(active.map((mission) => createLine(missionSummaryLine(mission), "info")));
        }
        break;
      }
      case "submit": {
        const missionId = args[0];
        const mission = nextState.activeMissions.find((m) => m.id === missionId);
        if (!mission) {
          emit([createLine(`Mission ${missionId} not found.`, "error")]);
          break;
        }
        if (mission.status !== "accepted") {
          emit([createLine(`Mission ${mission.title} is not active.`, "error")]);
          break;
        }
        const success = evaluateMission(nextState, mission);
        if (!success) {
          emit([
            createLine(`Mission ${mission.title} requires additional work.`, "error"),
            createLine("Check your inventory or edit the target file.", "info"),
          ]);
          break;
        }
        const updatedMissions = nextState.activeMissions.map((m) =>
          m.id === missionId ? { ...m, status: "completed" as const, completed: true } : m
        );
        nextState = {
          ...nextState,
          cash: nextState.cash + mission.reward.cash,
          reputation: nextState.reputation + mission.reward.reputation,
          activeMissions: updatedMissions,
          inbox: syncInbox(updatedMissions),
        };
        emit([
          createLine(`Mission ${mission.title} completed!`, "success"),
          createLine(`+${mission.reward.cash}c  +${mission.reward.reputation} reputation`, "success"),
        ]);
        soundCue = "success";
        vfxEvent = { type: "success" };
        break;
      }
      case "proxy list":
        emit(formatProxyTable(Object.values(nextState.world.proxies)).map((line) => createLine(line, "info")));
        break;
      case "proxy info": {
        const proxyId = args[0];
        const proxy = nextState.world.proxies[proxyId];
        if (!proxy) {
          emit([createLine(`Proxy ${proxyId} not found.`, "error")]);
          break;
        }
        emit([
          createLine(`ID: ${proxy.id}`),
          createLine(`Label: ${proxy.label}`),
          createLine(`Anonymity: ${(proxy.anonymity * 100).toFixed(1)}%`),
          createLine(`Heat: ${(proxy.heat * 100).toFixed(1)}%`),
          createLine(`Cost: ${proxy.costPerUse}c`),
        ]);
        break;
      }
      case "route show": {
        emit([
          createLine(`Hops: ${route.hops.join(" -> ") || "Direct"}`),
          createLine(`Latency: ${route.latencyMs.toFixed(0)}ms | Anonymity: ${(route.anonymity * 100).toFixed(1)}%`),
        ]);
        break;
      }
      case "route add": {
        const proxyId = args[0];
        const proxy = nextState.world.proxies[proxyId];
        if (!proxy) {
          emit([createLine(`Proxy ${proxyId} unavailable.`, "error")]);
          break;
        }
        if (proxy.heat >= 1) {
          emit([createLine(`Proxy ${proxyId} has burned out.`, "error")]);
          break;
        }
        if (route.hops.includes(proxyId)) {
          emit([createLine(`Proxy ${proxyId} already in route.`, "info")]);
          break;
        }
        // Increase heat more aggressively
        const heatIncrease = 0.15 + (proxy.heat * 0.1); // More heat if already hot
        const nextProxies = {
          ...nextState.world.proxies,
          [proxyId]: { ...proxy, heat: clamp(proxy.heat + heatIncrease, 0, 1) },
        };
        
        if (nextProxies[proxyId].heat >= 0.8) {
          emit([createLine(`WARNING: Proxy ${proxyId} is overheating (${(nextProxies[proxyId].heat * 100).toFixed(0)}%).`, "warning")]);
        }
        if (nextProxies[proxyId].heat >= 1) {
          emit([createLine(`CRITICAL: Proxy ${proxyId} has burned out and is unusable.`, "error")]);
        }
        const updatedWorld = { ...nextState.world, proxies: nextProxies };
        const updatedRoute = buildRouteState([...route.hops, proxyId], nextProxies);
        nextState = { ...nextState, world: updatedWorld, route: updatedRoute };
        emit([createLine(`Proxy ${proxyId} appended.`, "success")]);
        soundCue = "routeAdd";
        vfxEvent = { type: "scan" }; // Visual pulse on map
        break;
      }
      case "route rm": {
        const proxyId = args[0];
        if (!route.hops.includes(proxyId)) {
          emit([createLine(`${proxyId} is not part of the route.`, "error")]);
          break;
        }
        const updatedHops = route.hops.filter((hop) => hop !== proxyId);
        const updatedRoute = buildRouteState(updatedHops, nextState.world.proxies);
        nextState = { ...nextState, route: updatedRoute };
        emit([createLine(`Proxy ${proxyId} removed.`, "info")]);
        break;
      }
      case "route clear":
        nextState = { ...nextState, route: buildRouteState([], nextState.world.proxies) };
        emit([createLine("Route cleared.", "success")]);
        break;
      case "scan": {
        const host = findHost(nextState.world, args[0]);
        if (!host) {
          emit([createLine(`Host ${args[0]} not found.`, "error")]);
          break;
        }
        
        // Start scan animation sequence
        const hasRoute = route.hops.length > 0;
        const scanMode = flags.includes("stealth") ? "STEALTH" : flags.includes("aggr") ? "AGGRESSIVE" : "STANDARD";
        
        // Initial output - routing phase
        emit([
          createLine(`[SCAN] Initiating ${scanMode} scan on ${host.label}`, "info"),
          createLine(`[ROUTE] ${hasRoute ? `Routing through ${route.hops.length} proxy hop${route.hops.length > 1 ? "s" : ""}...` : "DIRECT CONNECTION - No proxy route!"}`, hasRoute ? "info" : "warning"),
        ]);
        
        // Set up scan animation for the map
        const scanAnim: ScanAnimation = {
          fromNode: route.hops.length > 0 ? route.hops[route.hops.length - 1] : "player",
          toNode: host.id,
          throughProxies: [...route.hops],
          phase: "routing",
          progress: 0,
          startTime: Date.now(),
        };
        set({ scanAnimation: scanAnim, isExecuting: true, executionPhase: "routing" });
        
        // Delayed output for drama
        setTimeout(() => {
          set((state) => ({
            terminalLines: [...state.terminalLines, createLine(`[PROBE] Enumerating ports on ${host.label}...`, "info")],
            scanAnimation: state.scanAnimation ? { ...state.scanAnimation, phase: "scanning", progress: 0.5 } : null,
            executionPhase: "executing",
          }));
        }, 400);
        
        setTimeout(() => {
          set((state) => ({
            terminalLines: [...state.terminalLines, createLine(`[PROBE] Fingerprinting services...`, "info")],
            scanAnimation: state.scanAnimation ? { ...state.scanAnimation, progress: 0.75 } : null,
          }));
        }, 800);
        
        // Final results after animation
        setTimeout(() => {
          const lines = formatScanOutput(host).map((line) => createLine(line, "success"));
          set((state) => ({
            terminalLines: [...state.terminalLines, createLine(`[COMPLETE] Scan finished.`, "success"), ...lines],
            scanAnimation: { ...state.scanAnimation!, phase: "complete", progress: 1 },
            executionPhase: "complete",
            isExecuting: false,
          }));
          
          // Clear animation after a moment
          setTimeout(() => {
            set({ scanAnimation: null, executionPhase: "idle" });
          }, 1500);
        }, 1200);
        
        const baseNoise = flags.includes("stealth") ? 6 : flags.includes("aggr") ? 18 : 12;
        appendTrace(baseNoise, host);
        
        // Ensure scannedHosts is a Set
        let scannedHostsSet = session.scannedHosts;
        if (!scannedHostsSet) {
          scannedHostsSet = new Set();
        } else if (Array.isArray(scannedHostsSet)) {
          scannedHostsSet = new Set(scannedHostsSet);
        } else if (!(scannedHostsSet instanceof Set)) {
          scannedHostsSet = new Set();
        }
        scannedHostsSet.add(host.id);
        nextState = { ...nextState, session: { ...session, currentTarget: host.id, scannedHosts: scannedHostsSet } };
        soundCue = "scan";
        vfxEvent = { type: "scan", target: host.id };
        break;
      }
      case "probe": {
        const host = findHost(nextState.world, args[0]);
        const port = Number(args[1]);
        if (!host || Number.isNaN(port)) {
          emit([createLine("Usage: probe <host> <port>", "error")]);
          break;
        }
        const service = host.services.find((entry) => entry.port === port);
        if (!service) {
          emit([createLine(`Port ${port} filtered (no service).`, "info")]);
        } else {
          emit([
            createLine(`${service.name} (${service.proto}) | ${service.banner ?? service.versionHint ?? "unknown"}`),
            createLine(`Exposure: ${(service.exposure * 100).toFixed(1)}% | Vigilance: ${service.accessRules.multiFactor ? "MFA" : "standard"}`),
          ]);
        }
        appendTrace(5, host);
        break;
      }
      case "fingerprint": {
        const host = findHost(nextState.world, args[0]);
        if (!host) {
          emit([createLine("Specify a host to fingerprint.", "error")]);
          break;
        }
        emit([
          createLine("OS guess: Linux 68%, FreeBSD 18%, Unknown 14%"),
          createLine("Latency analysis suggests hardened kernel.", "info"),
        ]);
        appendTrace(4, host);
        break;
      }
      case "connect": {
        const host = findHost(nextState.world, args[0]);
        if (!host) {
          emit([createLine(`Host ${args[0]} not reachable.`, "error")]);
          break;
        }

        // Check if host was scanned - ensure scannedHosts is a Set
        let scannedHosts = session.scannedHosts;
        if (!scannedHosts) {
          scannedHosts = new Set();
        } else if (Array.isArray(scannedHosts)) {
          scannedHosts = new Set(scannedHosts);
        } else if (!(scannedHosts instanceof Set)) {
          scannedHosts = new Set();
        }
        const wasScanned = scannedHosts.has(host.id);

        // Check if route exists
        const hasRouteForConnect = route.hops.length > 0;

        // Staged connection output
        emit([
          createLine(`[CONNECT] Initiating session to ${host.label}...`, "info"),
          createLine(`[ROUTE] ${hasRouteForConnect ? `Establishing tunnel through ${route.hops.length} hop${route.hops.length > 1 ? "s" : ""}` : "WARNING: Direct connection - no proxy!"}`, hasRouteForConnect ? "info" : "warning"),
        ]);
        
        // Set connection animation
        const connectAnim: ScanAnimation = {
          fromNode: route.hops.length > 0 ? route.hops[route.hops.length - 1] : "player",
          toNode: host.id,
          throughProxies: [...route.hops],
          phase: "routing",
          progress: 0,
          startTime: Date.now(),
        };
        set({ scanAnimation: connectAnim, isExecuting: true, executionPhase: "routing" });

        // Warn and apply penalties if requirements not met
        if (!wasScanned) {
          setTimeout(() => {
            set((state) => ({
              terminalLines: [...state.terminalLines, 
                createLine(`[!] WARNING: Host not scanned. IDS triggered.`, "warning"),
              ],
            }));
          }, 300);
        }

        if (!hasRouteForConnect) {
          setTimeout(() => {
            set((state) => ({
              terminalLines: [...state.terminalLines,
                createLine(`[!] WARNING: No proxy route. IP exposed.`, "warning"),
              ],
            }));
          }, 500);
        }

        // Calculate trace penalty - make it VERY visible
        let connectionNoise = 15; // Base connection noise (higher)
        if (!wasScanned) connectionNoise += 35; // Massive penalty for no scan
        if (!hasRouteForConnect) connectionNoise += 40; // Massive penalty for no route
        if (!wasScanned && !hasRouteForConnect) connectionNoise += 20; // Extra penalty for both

        // Delayed connection complete
        setTimeout(() => {
          set((state) => ({
            terminalLines: [...state.terminalLines,
              createLine(`[HANDSHAKE] Negotiating encryption...`, "info"),
            ],
            scanAnimation: state.scanAnimation ? { ...state.scanAnimation, phase: "scanning", progress: 0.6 } : null,
            executionPhase: "executing",
          }));
        }, 700);

        setTimeout(() => {
          set((state) => ({
            terminalLines: [...state.terminalLines,
              createLine(`[SESSION] Connection established to ${host.label}`, hasRouteForConnect && wasScanned ? "success" : "warning"),
              createLine(`[TRACE] Noise spike: +${connectionNoise} | Current: ${(state.gameState.trace.level).toFixed(1)}%`, connectionNoise > 30 ? "error" : "warning"),
            ],
            scanAnimation: { ...state.scanAnimation!, phase: "complete", progress: 1 },
            executionPhase: "complete",
            isExecuting: false,
          }));
          
          setTimeout(() => {
            set({ scanAnimation: null, executionPhase: "idle" });
          }, 1000);
        }, 1100);

        nextState = {
          ...nextState,
          session: {
            ...session,
            connectedHost: host.id,
            currentTarget: host.id,
            workingDir: "/",
            scannedHosts: scannedHosts instanceof Set ? scannedHosts : new Set(Array.isArray(scannedHosts) ? scannedHosts : []),
          },
        };
        appendTrace(connectionNoise, host);
        
        if (connectionNoise > 20 || nextState.trace.level > 25) {
          vfxEvent = { type: "alert", target: host.id };
          soundCue = "alert";
        } else {
          soundCue = "connect";
          vfxEvent = { type: "connect", target: host.id };
        }
        break;
      }
      case "disconnect":
      case "exit":
        const wasConnected = !!session.connectedHost;
        // Ensure scannedHosts is a Set
        let preservedScannedHosts = session.scannedHosts;
        if (!preservedScannedHosts) {
          preservedScannedHosts = new Set();
        } else if (Array.isArray(preservedScannedHosts)) {
          preservedScannedHosts = new Set(preservedScannedHosts);
        } else if (!(preservedScannedHosts instanceof Set)) {
          preservedScannedHosts = new Set();
        }
        nextState = { ...nextState, session: { scannedHosts: preservedScannedHosts } };
        emit([createLine(wasConnected ? "Disconnected. Trace will decay while idle." : "No active connection.", "info")]);
        break;
      case "pwd":
        emit([createLine(`Working directory: ${session.workingDir ?? "/"}`)]);
        break;
      case "ls": {
        if (!session.connectedHost) {
          emit([createLine("No host connected.", "error")]);
          break;
        }
        const host = nextState.world.hosts[session.connectedHost];
        const target = args[0] ?? session.workingDir ?? "/";
        emit(listFiles(host, target).map((line) => createLine(line)));
        break;
      }
      case "cd": {
        if (!session.connectedHost) {
          emit([createLine("No host connected.", "error")]);
          break;
        }
        const nextDir = args[0] ?? "/";
        nextState = { ...nextState, session: { ...session, workingDir: nextDir } };
        emit([createLine(`Set working dir to ${nextDir}`)]);
        break;
      }
      case "cat": {
        if (!session.connectedHost) {
          emit([createLine("No host connected.", "error")]);
          break;
        }
        const host = nextState.world.hosts[session.connectedHost];
        const target = args[0];
        const file = host.filesystem.find((entry) => entry.path === target);
        if (!file) {
          emit([createLine(`${target} not found.`, "error")]);
          break;
        }
        emit([createLine(file.content ?? "[binary data]", "info")] );
        break;
      }
      case "cp": {
        if (!session.connectedHost) {
          emit([createLine("No host connected.", "error")]);
          break;
        }
        const host = nextState.world.hosts[session.connectedHost];
        const src = args[0];
        const dst = args[1];
        if (!src || !dst) {
          emit([createLine("Usage: cp <src> <dst>", "error")]);
          break;
        }
        const entry = host.filesystem.find((file) => file.path === src);
        if (!entry) {
          emit([createLine(`${src} not found.`, "error")]);
          break;
        }
        if (dst !== "@local") {
          emit([createLine("Only @local destination is supported for now.", "info")]);
          break;
        }
        const newItem: InventoryItem = {
          id: `inv-${Date.now()}-${Math.random().toString(16).slice(2)}`,
          label: entry.name,
          source: host.id,
          path: entry.path,
          content: entry.content,
        };
        nextState = { ...nextState, inventory: [...nextState.inventory, newItem] };
        emit([createLine(`Copied ${entry.name} into inventory.`, "success")]);
        appendTrace(6, host);
        soundCue = "fileOp";
        vfxEvent = { type: "success" };
        break;
      }
      case "rm": {
        if (!session.connectedHost) {
          emit([createLine("No host connected.", "error")]);
          break;
        }
        const target = args[0];
        if (!target) {
          emit([createLine("Usage: rm <file>", "error")]);
          break;
        }
        const host = nextState.world.hosts[session.connectedHost];
        const filtered = host.filesystem.filter((entry) => entry.path !== target);
        const updatedHost = { ...host, filesystem: filtered };
        nextState = {
          ...nextState,
          world: { ...nextState.world, hosts: { ...nextState.world.hosts, [host.id]: updatedHost } },
        };
        emit([createLine(`Removed ${target}.`, "success")]);
        appendTrace(7, host);
        break;
      }
      case "edit": {
        if (!session.connectedHost) {
          emit([createLine("No host connected.", "error")]);
          break;
        }
        const target = args[0];
        const data = args[1];
        if (!target || !data) {
          emit([createLine("Usage: edit <file> key=value", "error")]);
          break;
        }
        const host = nextState.world.hosts[session.connectedHost];
        const file = host.filesystem.find((entry) => entry.path === target);
        if (!file) {
          emit([createLine(`${target} not found.`, "error")]);
          break;
        }
        const updatedFile = { ...file, content: `${data} (tampered)` };
        const updatedFs = host.filesystem.map((entry) => (entry.path === target ? updatedFile : entry));
        const updatedHost = { ...host, filesystem: updatedFs };
        nextState = {
          ...nextState,
          world: { ...nextState.world, hosts: { ...nextState.world.hosts, [host.id]: updatedHost } },
        };
        emit([createLine(`Patched ${target}.`, "success")]);
        appendTrace(5, host);
        break;
      }
      case "wipe logs": {
        if (!session.connectedHost) {
          emit([createLine("No host connected.", "error")]);
          break;
        }
        const host = nextState.world.hosts[session.connectedHost];
        const updatedHost = { ...host, logs: [] };
        const updatedWorld = {
          ...nextState.world,
          hosts: { ...nextState.world.hosts, [host.id]: updatedHost },
        };
        nextState = { ...nextState, world: updatedWorld };
        appendTrace(10, host);
        emit([createLine("Logs wiped. Trace noise spiked.", "warning")]);
        vfxEvent = { type: "alert" };
        soundCue = "alert";
        break;
      }
      case "market":
        emit([createLine("Market rotation offline. Check back after you rack more reputation.", "info")]);
        break;
      case "buy":
        emit([createLine("Store coming soon.", "info")]);
        break;
      default:
        emit([createLine(`Unknown command: ${key}`, "error")]);
        soundCue = "alert";
    }

    const commandLine = createLine(`lnk> ${trimmed}`, "command");

    set((state) => {
      const baseBuffer = clearScreen ? [] : state.terminalLines;
      const updatedBuffer = [...baseBuffer, commandLine, ...terminalLines];
      const updatedHistory = [trimmed, ...state.commandHistory.filter((entry) => entry !== trimmed)].slice(0, 60);
      const finalVfxEvent = vfxEvent ? { ...vfxEvent, value: trimmed } : null;
      return {
        gameState: nextState,
        terminalLines: updatedBuffer,
        commandHistory: updatedHistory,
        lastVfxEvent: finalVfxEvent,
        soundCue,
      };
    });

    await localSaveProvider.save(nextState);
  },
}));
