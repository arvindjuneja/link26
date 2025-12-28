"use client";

import { useEffect, useState } from "react";
import { useGameStore } from "@/app/lib/persistence/store";
import { generateWorld } from "@/app/lib/game/worldgen";
import { generateMissions } from "@/app/lib/game/missions";
import { getTraceStatus } from "@/app/lib/game/trace";
import { nowTimestamp } from "@/app/lib/util/time";

const DEMO_SEQUENCE = [
  { command: "clear", delay: 300 },
  { command: "inbox", delay: 1200 },
  { command: "read mission-ghost", delay: 1800 },
  { command: "accept mission-ghost", delay: 1200 },
  { command: "scan hq-node", delay: 3500 }, // Longer for scan effect
  { command: "proxy list", delay: 1500 },
  { command: "route add proxy-1", delay: 1200 },
  { command: "route add proxy-2", delay: 1200 },
  { command: "route show", delay: 1200 },
  { command: "connect hq-node", delay: 2500 }, // Longer for connection
  { command: "ls", delay: 1000 },
  { command: "cat /secrets.txt", delay: 1200 },
  { command: "cp /secrets.txt @local", delay: 1500 },
  { command: "status", delay: 1800 },
  { command: "exit", delay: 1000 },
  { command: "submit mission-ghost", delay: 3000 }, // Longer for celebration
];

export default function DemoMode() {
  const [isRunning, setIsRunning] = useState(false);
  const [currentStep, setCurrentStep] = useState(0);
  const runCommand = useGameStore((state) => state.runCommand);
  const resetWorld = useGameStore((state) => state.resetWorld);
  const gameState = useGameStore((state) => state.gameState);
  
  // Reset function to create fresh state
  const resetToInitialState = () => {
    const world = generateWorld();
    const { inbox, missions } = generateMissions(world);
    const traceLevel = 8;
    const tools = {
      scanner: { id: "scanner" as const, level: 1, label: "ScanSuite Alpha", description: "Base recon module." },
      proxyChain: { id: "proxyChain" as const, level: 1, label: "Proxy Chain", description: "Sneaks traffic through proxy hops." },
      wiper: { id: "wiper" as const, level: 1, label: "Logger Wiper", description: "Clears trace signatures (use sparingly)." },
      tracker: { id: "tracker" as const, level: 1, label: "Pulse Tracker", description: "Tracks host changes." },
    };

    const initialState = {
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
      session: { scannedHosts: new Set<string>() },
      inventory: [],
    };
    
    // Reset store state
    useGameStore.setState({ 
      gameState: initialState, 
      terminalLines: [],
      commandHistory: [],
      lastVfxEvent: null,
      soundCue: null,
    });
  };

  useEffect(() => {
    if (!isRunning) return;

    let timeoutId: NodeJS.Timeout;
    const currentAction = DEMO_SEQUENCE[currentStep];

    if (currentAction) {
      timeoutId = setTimeout(async () => {
        await runCommand(currentAction.command);
        if (currentStep < DEMO_SEQUENCE.length - 1) {
          setCurrentStep(currentStep + 1);
        } else {
          // Use setTimeout to avoid setState in effect
          setTimeout(() => {
            setIsRunning(false);
            setCurrentStep(0);
          }, 0);
        }
      }, currentAction.delay);
    } else {
      setTimeout(() => {
        setIsRunning(false);
        setCurrentStep(0);
      }, 0);
    }

    return () => {
      if (timeoutId) clearTimeout(timeoutId);
    };
  }, [isRunning, currentStep, runCommand]);

  const startDemo = () => {
    resetToInitialState();
    setIsRunning(true);
    setCurrentStep(0);
  };

  const stopDemo = () => {
    setIsRunning(false);
    setCurrentStep(0);
  };

  const progress = DEMO_SEQUENCE.length > 0 ? ((currentStep + 1) / DEMO_SEQUENCE.length) * 100 : 0;

  return (
    <div className="rounded border border-zinc-800 bg-black/60 p-3 text-[0.65rem]">
      <div className="mb-2 flex items-center justify-between">
        <div className="font-semibold uppercase tracking-[0.2em] text-zinc-500">Demo Mode</div>
        {isRunning && (
          <div className="rounded bg-blue-500/20 px-2 py-0.5 text-[0.6rem] text-blue-300 animate-pulse">
            RUNNING
          </div>
        )}
      </div>
      <p className="mb-3 text-[0.7rem] text-zinc-400">
        Watch an automated playthrough demonstrating all game features: mission flow, scanning, routing, connection, and file operations.
      </p>
      {isRunning && (
        <div className="mb-3 space-y-1">
          <div className="flex items-center justify-between text-[0.65rem] text-zinc-400">
            <span>Step {currentStep + 1} of {DEMO_SEQUENCE.length}</span>
            <span>{DEMO_SEQUENCE[currentStep]?.command}</span>
          </div>
          <div className="h-1.5 overflow-hidden rounded bg-zinc-900">
            <div
              className="h-full bg-blue-500 transition-all duration-300"
              style={{ width: `${progress}%` }}
            />
          </div>
        </div>
      )}
      <div className="flex gap-2">
        {!isRunning ? (
          <>
            <button
              onClick={startDemo}
              className="flex-1 rounded border border-emerald-500/60 bg-emerald-500/20 px-3 py-2 text-[0.7rem] font-semibold uppercase tracking-[0.15em] text-emerald-300 transition-colors hover:bg-emerald-500/30"
            >
              Start Demo
            </button>
            <button
              onClick={resetWorld}
              className="rounded border border-amber-500/60 bg-amber-500/20 px-3 py-2 text-[0.7rem] font-semibold uppercase tracking-[0.15em] text-amber-300 transition-colors hover:bg-amber-500/30"
              title="Clear saved data and regenerate world with new locations"
            >
              Reset
            </button>
          </>
        ) : (
          <button
            onClick={stopDemo}
            className="flex-1 rounded border border-rose-500/60 bg-rose-500/20 px-3 py-2 text-[0.7rem] font-semibold uppercase tracking-[0.15em] text-rose-300 transition-colors hover:bg-rose-500/30"
          >
            Stop Demo
          </button>
        )}
      </div>
      {isRunning && (
        <div className="mt-2 text-[0.65rem] text-zinc-500">
          Trace: {gameState.trace.level.toFixed(1)}% ({gameState.trace.status}) | 
          Route: {gameState.route.hops.length} hops | 
          Cash: {gameState.cash}c
        </div>
      )}
    </div>
  );
}

