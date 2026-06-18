// The starting game state. Extracted from the store so it can be built
// deterministically (inject `now`) and imported by tests without dragging in
// the browser-only store (zustand + IndexedDB + Supabase).

import type { GameState, ToolId, ToolInstance } from "@/types/game";
import { generateWorld } from "@/app/lib/game/worldgen";
import { generateMissions } from "@/app/lib/game/missions";
import { createExposure } from "@/app/lib/game/exposure";

export interface InitialStateOptions {
  /** Timestamp baked into the fresh state. Inject for deterministic builds. */
  now?: number;
  /** World seed. Defaults to `now` so {now:0} builds are fully reproducible. */
  seed?: number;
}

export function createInitialState(options: InitialStateOptions = {}): GameState {
  const now = options.now ?? Date.now();
  const seed = options.seed ?? now;
  const world = generateWorld(now, seed);
  const { inbox, missions } = generateMissions(world, now);

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
    seed,
    cash: 4200,
    reputation: 36,
    exposure: createExposure(8),
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
