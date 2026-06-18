"use client";

import { useGameStore } from "@/app/lib/persistence/store";
import { GEAR } from "@/app/lib/game/gear";

export default function EvidencePanel() {
  const evidence = useGameStore((s) => s.gameState.evidence);
  const gear = useGameStore((s) => s.gameState.gear);
  const ownedGear = GEAR.filter((g) => (gear[g.id] ?? 0) > 0);

  return (
    <div className="rounded border border-cyan-500/15 bg-black/60 p-4 font-mono">
      <div className="mb-2 flex items-center justify-between text-[0.7rem]">
        <span className="tracking-wider text-cyan-300">EVIDENCE BOARD</span>
        <span className="text-zinc-500">{evidence.length} cards</span>
      </div>

      {evidence.length === 0 ? (
        <p className="text-[0.65rem] leading-snug text-zinc-600">
          No intel yet. <span className="text-zinc-400">osint &lt;subject&gt;</span> to footprint a person,{" "}
          <span className="text-zinc-400">collect rf &lt;host&gt;</span> to characterize an emitter.
        </p>
      ) : (
        <div className="max-h-40 space-y-1 overflow-y-auto pr-1">
          {evidence.map((e) => (
            <div key={e.id} className="flex items-baseline justify-between gap-2 text-[0.62rem]">
              <span className="shrink-0 text-cyan-500/70">{e.sourceId}</span>
              <span className="truncate text-zinc-400">{e.label}</span>
              <span className="truncate text-right text-zinc-300">{e.value}</span>
            </div>
          ))}
        </div>
      )}

      {ownedGear.length > 0 && (
        <div className="mt-3 border-t border-zinc-800 pt-2">
          <div className="mb-1 text-[0.6rem] tracking-wider text-zinc-500">RIG</div>
          <div className="flex flex-wrap gap-1">
            {ownedGear.map((g) => (
              <span
                key={g.id}
                className="rounded bg-cyan-500/10 px-1.5 py-0.5 text-[0.58rem] text-cyan-300"
                title={`${g.label}: flattens ${g.channel}`}
              >
                {g.id} T{gear[g.id]}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
