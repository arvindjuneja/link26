"use client";

import TraceMeter from "./TraceMeter";
import { useGameStore } from "@/app/lib/persistence/store";

export default function TopBar() {
  const gameState = useGameStore((state) => state.gameState);
  const { cash, reputation, route, session } = gameState;

  return (
    <div className="flex w-full flex-col gap-3 rounded border border-zinc-800 bg-black/60 p-4 text-xs text-zinc-300">
      <div className="flex flex-wrap items-center justify-between gap-2 text-[0.65rem] uppercase tracking-[0.2em] text-zinc-500">
        <div className="flex items-center gap-2">
          <span>Cash</span>
          <span className="text-white">{cash}c</span>
        </div>
        <div className="flex items-center gap-2">
          <span>Reputation</span>
          <span className="text-white">{reputation}r</span>
        </div>
        <div className="flex items-center gap-2">
          <span>Route hops</span>
          <span className="text-white">{route.hops.length}</span>
        </div>
        <button className="rounded border border-zinc-700 px-3 py-1 text-[0.65rem] uppercase tracking-[0.2em] text-zinc-200 transition hover:border-white">
          Login (Coming soon)
        </button>
      </div>
      <div className="flex items-center justify-between gap-3 text-[0.65rem] text-zinc-400">
        <div>
          <div className="text-[0.6rem] text-zinc-500">Cloud Sync</div>
          <div className="text-white">Coming soon</div>
        </div>
        <div>
          <div className="text-[0.6rem] text-zinc-500">Connected Host</div>
          <div className="text-white">{session.connectedHost ?? "none"}</div>
        </div>
      </div>
      <TraceMeter />
    </div>
  );
}
