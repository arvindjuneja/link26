import { create } from "zustand";
import type { GameState, TerminalLine, VfxEvent } from "@/types/game";
import { tickExposure } from "@/app/lib/game/exposure";
import { channelMitigation } from "@/app/lib/game/gear";
import { coolProxies } from "@/app/lib/game/worldQueries";
import { createInitialState } from "@/app/lib/game/initialState";
import { reduceCommand, type SoundCue } from "@/app/lib/game/reducer";
import { createLiveContext } from "@/app/lib/game/context";
import type { ScanAnimation, ExecutionPhase, TimedEffect } from "@/app/lib/game/effects";
import { localSaveProvider } from "./saveLocalIndexedDb";
import { cloudSaveProvider } from "./saveCloudSupabase";
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
  "collect rf",
  "deploy sensor",
];

// ScanAnimation / ExecutionPhase now live in app/lib/game/effects.ts (shared
// with the pure reducer). Re-exported here so view components can keep importing
// them from the store.
export type { ScanAnimation, ExecutionPhase };

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

// The store module is evaluated on BOTH server (SSR) and client, so the initial
// state must be deterministic — a Date.now() seed here renders a different world
// on each side and triggers a hydration mismatch. Use a fixed seed/time for the
// pre-load state; a real saved game (or a reset) replaces it client-side after
// mount. resetWorld() below still uses Date.now() for per-reset variety.
const INITIAL_SEED = 26;
const INITIAL_TIME = 1767225600000; // 2026-01-01 UTC

export const useGameStore = create<GameStoreState>()((set, get) => ({
  gameState: createInitialState({ seed: INITIAL_SEED, now: INITIAL_TIME }),
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
      // Discard pre-exposure saves rather than crash on the new schema.
      if (!cloudState.exposure) return false;
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
      // Discard pre-exposure saves rather than crash on the new schema.
      if (!saved.exposure) return;
      // Convert scannedHosts array back to Set
      if (saved.session && Array.isArray(saved.session.scannedHosts)) {
        saved.session.scannedHosts = new Set(saved.session.scannedHosts);
      } else if (saved.session && !saved.session.scannedHosts) {
        saved.session.scannedHosts = new Set();
      }
      set({ gameState: saved });
    }
  },
  // The Exposure Board tick: while a session is held, NETWORK climbs (the dwell
  // clock / closing window); idle, channels cool at their own rates.
  decayTraceTick: () =>
    set((state) => {
      const gs = state.gameState;
      const connectedHost = gs.session.connectedHost;
      const host = connectedHost ? gs.world.hosts[connectedHost] : undefined;
      return {
        gameState: {
          ...gs,
          exposure: tickExposure(gs.exposure, {
            connected: !!connectedHost,
            route: gs.route,
            host,
            networkMitigation: channelMitigation(gs.gear, "NETWORK"),
          }),
          world: { ...gs.world, proxies: coolProxies(gs.world.proxies) },
        },
      };
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

    // runCommand is now a thin dispatcher: parse -> pure reducer -> commit ->
    // play staged effects -> persist. All command logic lives in the reducer.
    const ctx = createLiveContext();
    const reduced = reduceCommand(nextState, { key, args, flags, raw: trimmed }, ctx);
    let effects: TimedEffect[] = [];
    if (reduced) {
      nextState = reduced.state;
      terminalLines.push(...reduced.lines);
      soundCue = reduced.soundCue;
      vfxEvent = reduced.vfx;
      clearScreen = reduced.clearScreen;
      effects = reduced.effects ?? [];
    } else {
      terminalLines.push(createLine(`Unknown command: ${key}`, "error"));
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

    // Play staged presentation effects (terminal drama + map animation). These
    // are view-only — game state was already committed above. The reducer chose
    // the timings; the store just schedules them.
    if (effects.length) {
      const applyEffect = (effect: TimedEffect) =>
        set((state) => {
          const patch: Partial<GameStoreState> = {};
          if (effect.lines) patch.terminalLines = [...state.terminalLines, ...effect.lines];
          if (effect.anim) {
            patch.scanAnimation =
              effect.anim.type === "set"
                ? effect.anim.value
                : effect.anim.type === "clear"
                ? null
                : state.scanAnimation
                ? { ...state.scanAnimation, ...effect.anim.value }
                : null;
          }
          if (effect.executionPhase !== undefined) patch.executionPhase = effect.executionPhase;
          if (effect.isExecuting !== undefined) patch.isExecuting = effect.isExecuting;
          return patch;
        });
      for (const effect of effects) {
        if (effect.atMs <= 0) applyEffect(effect);
        else setTimeout(() => applyEffect(effect), effect.atMs);
      }
    }

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
