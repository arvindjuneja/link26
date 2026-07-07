"use client";

import { useGameStore } from "@/app/lib/persistence/store";
import { CAMPAIGN } from "@/app/lib/game/campaign";

export default function CampaignPanel() {
  const chapter = useGameStore((s) => s.gameState.campaign.chapter);
  const missions = useGameStore((s) => s.gameState.activeMissions);
  const cur = CAMPAIGN[chapter];
  const done = chapter >= CAMPAIGN.length;
  const mission = cur ? missions.find((m) => m.id === `campaign-${cur.id}`) : undefined;

  return (
    <div className="rounded-lg border border-cyan-500/20 bg-black/60 p-4 font-mono">
      <div className="mb-2 flex items-center justify-between text-[0.7rem]">
        <span className="tracking-[0.2em] text-cyan-300">
          CAMPAIGN{cur ? ` · ACT ${cur.act}` : ""}
        </span>
        <span className="text-zinc-500">
          {Math.min(chapter, CAMPAIGN.length)}/{CAMPAIGN.length}
        </span>
      </div>

      <div className="mb-3 flex gap-1">
        {CAMPAIGN.map((c, i) => (
          <div
            key={c.id}
            title={c.title}
            className={`h-1 flex-1 rounded ${
              i < chapter ? "bg-cyan-400" : i === chapter ? "bg-cyan-500/50" : "bg-zinc-800"
            }`}
          />
        ))}
      </div>

      {done ? (
        <p className="text-[0.72rem] leading-snug text-zinc-300">
          Three acts done — scared freelancer, then operator, then ghost story. The handle&apos;s
          burned and the hunt closed on nobody.{" "}
          <span className="text-zinc-500">The contract board is yours now.</span>
        </p>
      ) : (
        <>
          <div className="mb-1 flex items-center gap-2">
            <span className="text-sm font-semibold text-zinc-100">{cur.title}</span>
            {mission?.status === "accepted" ? (
              <span className="text-[0.55rem] uppercase tracking-wider text-emerald-400">active</span>
            ) : (
              <span className="text-[0.55rem] text-cyan-400">type: accept {mission?.id ?? `campaign-${cur.id}`}</span>
            )}
          </div>
          <p className="text-[0.72rem] leading-relaxed text-zinc-400">&ldquo;{cur.intro}&rdquo;</p>
        </>
      )}
    </div>
  );
}
