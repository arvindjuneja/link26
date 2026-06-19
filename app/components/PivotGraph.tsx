"use client";

import { useMemo } from "react";
import { useGameStore } from "@/app/lib/persistence/store";
import { GEAR } from "@/app/lib/game/gear";
import type { EvidenceCard } from "@/types/game";

// The OSINT pivot graph — the Maltego/SpiderFoot mental model. Recon drops
// evidence cards; the player watches a subject's breadcrumbs (handle, email,
// breach, device...) connect into a dossier. When a subject's cards satisfy an
// accepted identify contract, the cluster "snaps" to ATTRIBUTED — the payoff.

const KIND_COLOR: Record<string, string> = {
  handle: "#22d3ee",
  email: "#38bdf8",
  domain: "#2dd4bf",
  breach: "#fb7185",
  device: "#fbbf24",
  timezone: "#a78bfa",
  employer: "#34d399",
  location: "#fb923c",
  signature: "#e879f9",
};

const SIZE = 188;
const C = SIZE / 2;
const RING = 62;

function Cluster({
  sourceId,
  cards,
  label,
  attributed,
}: {
  sourceId: string;
  cards: EvidenceCard[];
  label: string;
  attributed: boolean;
}) {
  const isEmitter = sourceId.startsWith("emitter-");
  const n = cards.length;
  return (
    <div
      className={`rounded-lg border bg-black/40 p-2 transition-colors ${
        attributed ? "border-cyan-400/60 shadow-[0_0_18px_-4px] shadow-cyan-500/40" : "border-zinc-800"
      }`}
    >
      <div className="mb-1 flex items-center justify-between px-1">
        <span className="max-w-[130px] truncate text-[0.64rem] text-zinc-300" title={label}>
          {label}
        </span>
        {attributed && (
          <span className="text-[0.5rem] font-semibold uppercase tracking-wider text-cyan-300">● dossier</span>
        )}
      </div>
      <svg width={SIZE} height={SIZE} viewBox={`0 0 ${SIZE} ${SIZE}`}>
        {cards.map((card, i) => {
          const a = (i / Math.max(1, n)) * Math.PI * 2 - Math.PI / 2;
          const x = C + RING * Math.cos(a);
          const y = C + RING * Math.sin(a);
          const color = KIND_COLOR[card.factKind] ?? "#94a3b8";
          return (
            <g key={card.id}>
              <line x1={C} y1={C} x2={x} y2={y} stroke={color} strokeOpacity={0.35} strokeWidth={1} />
              <circle cx={x} cy={y} r={5} fill={color}>
                <title>{`${card.label}: ${card.value}`}</title>
              </circle>
              <text
                x={x}
                y={y + (Math.sin(a) >= 0 ? 14 : -9)}
                fill={color}
                fontSize="7"
                textAnchor="middle"
                fontFamily="IBM Plex Mono, monospace"
              >
                {card.factKind}
              </text>
            </g>
          );
        })}
        {/* center node */}
        <circle
          cx={C}
          cy={C}
          r={13}
          fill={isEmitter ? "rgba(232,121,249,0.18)" : attributed ? "rgba(34,211,238,0.22)" : "rgba(125,211,252,0.14)"}
          stroke={isEmitter ? "#e879f9" : attributed ? "#22d3ee" : "#7dd3fc"}
          strokeWidth={1.5}
        />
        <text x={C} y={C + 3} fill="#cbd5e1" fontSize="8" textAnchor="middle" fontFamily="IBM Plex Mono, monospace">
          {isEmitter ? "RF" : "ID"}
        </text>
      </svg>
    </div>
  );
}

export default function PivotGraph() {
  const evidence = useGameStore((s) => s.gameState.evidence);
  const missions = useGameStore((s) => s.gameState.activeMissions);
  const world = useGameStore((s) => s.gameState.world);
  const gear = useGameStore((s) => s.gameState.gear);

  const clusters = useMemo(() => {
    const groups = new Map<string, EvidenceCard[]>();
    for (const e of evidence) {
      if (!groups.has(e.sourceId)) groups.set(e.sourceId, []);
      groups.get(e.sourceId)!.push(e);
    }
    return Array.from(groups.entries()).map(([sourceId, cards]) => {
      const kinds = new Set(cards.map((c) => c.factKind));
      const attributed = missions.some(
        (m) =>
          m.objective.type === "identify" &&
          m.objective.targetPersonId === sourceId &&
          m.status === "accepted" &&
          (m.objective.requiredKinds ?? []).every((k) => kinds.has(k))
      );
      const label = sourceId.startsWith("emitter-")
        ? world.emitters[sourceId]?.label ?? "RF emitter"
        : world.people[sourceId]?.label ?? sourceId;
      return { sourceId, cards, label, attributed };
    });
  }, [evidence, missions, world]);

  const ownedGear = GEAR.filter((g) => (gear[g.id] ?? 0) > 0);

  return (
    <div className="rounded-lg border border-cyan-500/20 bg-black/60 p-4 font-mono">
      <div className="mb-3 flex items-center justify-between text-[0.7rem]">
        <span className="tracking-[0.2em] text-cyan-300">PIVOT GRAPH · DOSSIER</span>
        <span className="text-zinc-500">{evidence.length} cards · {clusters.length} subjects</span>
      </div>

      {clusters.length === 0 ? (
        <p className="text-[0.66rem] leading-relaxed text-zinc-500">
          No intel yet. <span className="text-zinc-400">osint &lt;subject&gt; --active</span> to footprint a
          person, <span className="text-zinc-400">collect rf &lt;host&gt;</span> to characterize an emitter — their
          breadcrumbs connect here, and a subject &ldquo;snaps&rdquo; to a dossier when it satisfies an accepted
          identify contract.
        </p>
      ) : (
        <div className="flex flex-wrap gap-3">
          {clusters.map((c) => (
            <Cluster key={c.sourceId} {...c} />
          ))}
        </div>
      )}

      {ownedGear.length > 0 && (
        <div className="mt-3 flex flex-wrap items-center gap-1 border-t border-zinc-800 pt-2">
          <span className="mr-1 text-[0.58rem] tracking-wider text-zinc-500">RIG</span>
          {ownedGear.map((g) => (
            <span
              key={g.id}
              className="rounded bg-cyan-500/10 px-1.5 py-0.5 text-[0.56rem] text-cyan-300"
              title={`${g.label}: flattens ${g.channel}`}
            >
              {g.id} T{gear[g.id]}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}
