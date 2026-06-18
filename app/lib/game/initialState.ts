// The starting game state. Extracted from the store so it can be built
// deterministically (inject `now`) and imported by tests without dragging in
// the browser-only store (zustand + IndexedDB + Supabase).

import type { GameState, ToolId, ToolInstance } from "@/types/game";
import { generateWorld } from "@/app/lib/game/worldgen";
import { generateMissions } from "@/app/lib/game/missions";
import { getTraceStatus } from "@/app/lib/game/trace";

export interface InitialStateOptions {
  /** Timestamp baked into the fresh state. Inject for deterministic builds. */
  now?: number;
}

export function createInitialState(options: InitialStateOptions = {}): GameState {
  const now = options.now ?? Date.now();
  const world = generateWorld(now);
  const { inbox, missions } = generateMissions(world, now);
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
    time: now,
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
}
