"use client";

import { useGameStore } from "@/app/lib/persistence/store";

export default function InboxPanel() {
  const inbox = useGameStore((state) => state.gameState.inbox);
  const runCommand = useGameStore((state) => state.runCommand);

  return (
    <section className="space-y-2 rounded border border-zinc-800 bg-black/50 p-3 text-[0.65rem] text-zinc-200">
      <header className="flex items-center justify-between text-xs uppercase tracking-[0.3em] text-zinc-500">
        <span>Mission inbox</span>
        <span>{inbox.length} entries</span>
      </header>
      <div className="space-y-2 text-[0.75rem]">
        {inbox.map((mission) => (
          <div key={mission.id} className="rounded border border-zinc-800 bg-zinc-900/40 p-2">
            <div className="flex items-center justify-between">
              <strong className="text-white">{mission.title}</strong>
              <span className="text-[0.65rem] text-zinc-400">{mission.status}</span>
            </div>
            <p className="text-[0.65rem] text-zinc-400">{mission.description}</p>
            <div className="mt-1 flex items-center gap-2 text-[0.7rem] text-zinc-400">
              <span>Reward: {mission.reward.cash}c / {mission.reward.reputation}r</span>
              <span>Target: {mission.targetHost}</span>
            </div>
            <div className="mt-2 flex flex-wrap gap-1">
              <button
                className="rounded border border-zinc-700 px-2 py-1 text-[0.65rem] uppercase tracking-[0.2em] text-zinc-200"
                onClick={() => runCommand(`read ${mission.id}`)}
              >
                Read
              </button>
              {mission.status === "available" && (
                <button
                  className="rounded border border-emerald-500/60 bg-emerald-500/20 px-2 py-1 text-[0.65rem] uppercase tracking-[0.2em] text-emerald-300"
                  onClick={() => runCommand(`accept ${mission.id}`)}
                >
                  Accept
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
