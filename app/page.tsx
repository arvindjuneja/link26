"use client";

import { useEffect, useState, useCallback } from "react";
import Terminal from "./components/Terminal";
import MapCanvas from "./components/MapCanvas";
import VfxThreeOverlay from "./components/VfxThreeOverlay";
import InboxPanel from "./components/InboxPanel";
import InventoryPanel from "./components/InventoryPanel";
import MarketPanel from "./components/MarketPanel";
import MissionGuidance from "./components/MissionGuidance";
import DemoMode from "./components/DemoMode";
import ExposureBoard from "./components/ExposureBoard";
import EvidencePanel from "./components/EvidencePanel";
import HandlerPanel from "./components/HandlerPanel";
import Codex from "./components/Codex";
import Disclaimer from "./components/Disclaimer";
import { AuthModal } from "./components/AuthModal";
import { useGameStore } from "./lib/persistence/store";
import { overallTrace } from "./lib/game/exposure";
import { supabase, isSupabaseConfigured } from "./lib/supabase/client";

// Status-based styling
const traceStyles = {
  CALM: {
    border: "border-cyan-500/20",
    glow: "",
    bg: "bg-cyan-500/5",
  },
  ALERT: {
    border: "border-amber-500/30",
    glow: "border-glow-alert",
    bg: "bg-amber-500/5",
  },
  HUNT: {
    border: "border-orange-500/40",
    glow: "border-glow-hunt",
    bg: "bg-orange-500/5",
  },
  LOCKDOWN: {
    border: "border-rose-500/50",
    glow: "border-glow-lockdown",
    bg: "bg-rose-500/10",
  },
};

export default function Home() {
  const loadSavedState = useGameStore((state) => state.loadSavedState);
  const decayTraceTick = useGameStore((state) => state.decayTraceTick);
  const gameState = useGameStore((state) => state.gameState);
  const runCommand = useGameStore((state) => state.runCommand);
  const isExecuting = useGameStore((state) => state.isExecuting);
  const user = useGameStore((state) => state.user);
  const setUser = useGameStore((state) => state.setUser);
  const cloudSyncEnabled = useGameStore((state) => state.cloudSyncEnabled);

  const [authModalOpen, setAuthModalOpen] = useState(false);

  const { world, route, session, cash, reputation, streak } = gameState;
  const trace = overallTrace(gameState.exposure);
  const traceStyle = traceStyles[trace.status as keyof typeof traceStyles] ?? traceStyles.CALM;

  const handleAuthChange = useCallback((newUser: typeof user) => {
    setUser(newUser);
  }, [setUser]);

  useEffect(() => {
    loadSavedState();
    const interval = setInterval(decayTraceTick, 3000);
    return () => clearInterval(interval);
  }, [loadSavedState, decayTraceTick]);

  // Initialize auth state on mount (only if Supabase is configured)
  useEffect(() => {
    if (!isSupabaseConfigured) return;
    
    supabase.auth.getUser().then(({ data: { user } }) => {
      setUser(user);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      setUser(session?.user ?? null);
    });

    return () => subscription.unsubscribe();
  }, [setUser]);

  return (
    <div className={`relative min-h-screen bg-[#000102] text-white transition-colors duration-500 ${traceStyle.bg}`}>
      <VfxThreeOverlay />
      <Disclaimer />
      <AuthModal
        isOpen={authModalOpen} 
        onClose={() => setAuthModalOpen(false)}
        onAuthChange={handleAuthChange}
      />
      <div className="relative z-10 mx-auto flex min-h-screen w-full max-w-[1600px] flex-col gap-3 px-3 py-4">
        {/* Compact top bar with trace-reactive styling */}
        <header className={`flex items-center justify-between rounded border ${traceStyle.border} ${traceStyle.glow} bg-black/60 px-4 py-2 text-[0.7rem] transition-all duration-300`}>
          <div className="flex items-center gap-6">
            <div><span className="text-zinc-500">CASH</span> <span className="font-semibold text-amber-400">{cash}c</span></div>
            <div><span className="text-zinc-500">REP</span> <span className="font-semibold text-cyan-300">{reputation}r</span></div>
            <div><span className="text-zinc-500">ROUTE</span> <span className="font-semibold">{route.hops.length} hops</span></div>
            {streak > 0 && (
              <div><span className="text-zinc-500">STREAK</span> <span className="font-semibold text-cyan-400">×{streak}</span></div>
            )}
          </div>
          <div className="flex items-center gap-4">
            <Codex />
            {/* Execution indicator */}
            {isExecuting && (
              <div className="flex items-center gap-2 text-cyan-400">
                <span className="inline-block h-2 w-2 animate-ping rounded-full bg-cyan-400" />
                <span className="text-[0.65rem] uppercase tracking-wider">EXECUTING</span>
              </div>
            )}
            <div className="text-zinc-500">
              {session.connectedHost ? (
                <span>Connected: <span className="text-emerald-400">{session.connectedHost}</span></span>
              ) : (
                <span>Disconnected</span>
              )}
            </div>
            <button 
              onClick={() => setAuthModalOpen(true)}
              className={`rounded border px-3 py-1 transition-colors ${
                user 
                  ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20" 
                  : "border-zinc-700 bg-zinc-800/50 text-zinc-400 hover:bg-zinc-700/50"
              }`}
            >
              {user ? (
                <span className="flex items-center gap-2">
                  <span className="h-2 w-2 rounded-full bg-emerald-400" />
                  SYNCED
                </span>
              ) : (
                "LOGIN"
              )}
            </button>
          </div>
        </header>

        {/* COCKPIT: map (2/3) beside the Exposure Board + Terminal (1/3), all
            visible at once — no scrolling between "where I look" and "where I type". */}
        <div className="flex flex-col gap-3 lg:flex-row lg:items-stretch">
          <section className="relative lg:w-2/3">
            <MapCanvas
              world={world}
              route={route}
              trace={trace}
              focusHost={session.currentTarget ?? session.connectedHost}
              session={session}
              onProxyAdd={(id) => runCommand(`route add ${id}`)}
              large
            />
          </section>

          <div className="flex min-h-0 flex-1 flex-col gap-3">
            <div className={`rounded border ${traceStyle.border} ${traceStyle.glow} bg-black/60 p-4 transition-all duration-300`}>
              <ExposureBoard />
            </div>
            <div className="min-h-[280px] flex-1">
              <Terminal />
            </div>
          </div>
        </div>

        {/* Secondary panels — reference material, below the fold */}
        <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
          <HandlerPanel />
          <MissionGuidance />
          <InboxPanel />
          <EvidencePanel />
          <InventoryPanel />
          <MarketPanel />
          <DemoMode />
        </div>
      </div>
    </div>
  );
}
