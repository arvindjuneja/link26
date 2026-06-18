import { create } from "zustand";
import type { GameState, TerminalLine, VfxEvent, Host } from "@/types/game";
import { formatScanOutput } from "@/app/lib/game/formatting";
import { addTraceNoise, decayTrace } from "@/app/lib/game/trace";
import { createInitialState } from "@/app/lib/game/initialState";
import { reduceCommand, type SoundCue } from "@/app/lib/game/reducer";
import { createLiveContext } from "@/app/lib/game/context";
import { findHost } from "@/app/lib/game/worldQueries";
import { localSaveProvider } from "./saveLocalIndexedDb";
import { cloudSaveProvider } from "./saveCloudSupabase";
import { nowTimestamp } from "@/app/lib/util/time";
import type { User } from "@supabase/supabase-js";

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
  // Auth state
  user: User | null;
  cloudSyncEnabled: boolean;
  lastSyncTime: number | null;
  // Actions
  runCommand: (input: string) => Promise<void>;
  clearTerminal: () => void;
  loadSavedState: () => Promise<void>;
  decayTraceTick: () => void;
  acknowledgeSoundCue: () => void;
  addTerminalLine: (line: TerminalLine) => void;
  resetWorld: () => Promise<void>;
  setScanAnimation: (animation: ScanAnimation | null) => void;
  setExecutionPhase: (phase: ExecutionPhase) => void;
  // Auth actions
  setUser: (user: User | null) => void;
  syncToCloud: () => Promise<void>;
  loadFromCloud: () => Promise<boolean>;
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
  // Auth state
  user: null,
  cloudSyncEnabled: false,
  lastSyncTime: null,
  // Basic actions
  addTerminalLine: (line) =>
    set((state) => ({ terminalLines: [...state.terminalLines, line] })),
  clearTerminal: () => set({ terminalLines: [] }),
  acknowledgeSoundCue: () => set({ soundCue: null }),
  setScanAnimation: (animation) => set({ scanAnimation: animation }),
  setExecutionPhase: (phase) => set({ executionPhase: phase, isExecuting: phase !== "idle" && phase !== "complete" }),
  // Auth actions
  setUser: (user) => {
    set({ user, cloudSyncEnabled: !!user });
    // If user just logged in, try to load cloud save
    if (user) {
      get().loadFromCloud();
    }
  },
  syncToCloud: async () => {
    const { user, gameState } = get();
    if (!user) return;
    await cloudSaveProvider.save(gameState);
    set({ lastSyncTime: Date.now() });
  },
  loadFromCloud: async () => {
    const { user } = get();
    if (!user) return false;
    
    const cloudState = await cloudSaveProvider.load();
    if (cloudState) {
      // Convert scannedHosts array back to Set
      if (cloudState.session && Array.isArray(cloudState.session.scannedHosts)) {
        cloudState.session.scannedHosts = new Set(cloudState.session.scannedHosts);
      } else if (cloudState.session && !cloudState.session.scannedHosts) {
        cloudState.session.scannedHosts = new Set();
      }
      set({ gameState: cloudState, lastSyncTime: Date.now() });
      return true;
    }
    return false;
  },
  resetWorld: async () => {
    const { user } = get();
    // Clear saved state from IndexedDB
    await localSaveProvider.clear();
    // Also clear cloud save if logged in
    if (user) {
      await cloudSaveProvider.clear();
    }
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
      lastSyncTime: null,
    });
  },
  loadSavedState: async () => {
    // First try local save
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

    const appendTrace = (noise: number, host?: Host) => {
      const trace = addTraceNoise(nextState.trace, noise, route, host);
      nextState = { ...nextState, trace, time: nowTimestamp() };
    };

    // Phase 0 migration: the pure reducer owns an increasing subset of commands.
    // If it handles this one, apply its result and skip the legacy switch entirely.
    const ctx = createLiveContext();
    const reduced = reduceCommand(nextState, { key, args, flags, raw: trimmed }, ctx);
    if (reduced) {
      nextState = reduced.state;
      terminalLines.push(...reduced.lines);
      soundCue = reduced.soundCue;
      vfxEvent = reduced.vfx;
      clearScreen = reduced.clearScreen;
    } else {
    switch (key) {
      case "":
        emit([createLine("No command entered.", "error")]);
        break;
      case "settings":
        emit([createLine("Settings are currently handled by the terminal. Coming soon.", "info")]);
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
      default:
        emit([createLine(`Unknown command: ${key}`, "error")]);
        soundCue = "alert";
    }
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

    // Save to local storage
    await localSaveProvider.save(nextState);
    
    // Also sync to cloud if user is logged in
    const { user } = get();
    if (user) {
      // Fire and forget - don't block on cloud save
      cloudSaveProvider.save(nextState).then(() => {
        set({ lastSyncTime: Date.now() });
      });
    }
  },
}));
