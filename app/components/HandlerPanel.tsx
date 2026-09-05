"use client";

import { useMemo } from "react";
import { useGameStore } from "@/app/lib/persistence/store";
import { MERCER_LINES } from "@/app/lib/game/contentPack";
import { overallTrace } from "@/app/lib/game/exposure";

// Mercer — the handler. Terse, ex-trade, protective. He reacts to your current
// posture; he has OPSEC judgment and will warn you off reckless moves.
function deriveSituation(args: {
  attributionStatus: string;
  overallStatus: string;
  connected: boolean;
  hops: number;
  acceptedCount: number;
}): string {
  if (args.attributionStatus === "HUNT" || args.attributionStatus === "LOCKDOWN") return "high_attribution";
  if (args.overallStatus === "LOCKDOWN") return "burned";
  if (args.connected && args.hops === 0) return "no_route_warning";
  // Parked on a live session with nothing to do: the trace is climbing and the
  // right move is to get OFF the line, not to "keep working". The plain idle
  // nudge below assumes you're disconnected, so it would give exactly the wrong
  // advice here — catch the connected case first.
  if (args.connected && args.acceptedCount === 0) return "connected_idle";
  if (args.acceptedCount === 0) return "idle_nudge";
  return "intro";
}

export default function HandlerPanel() {
  const exposure = useGameStore((s) => s.gameState.exposure);
  const session = useGameStore((s) => s.gameState.session);
  const route = useGameStore((s) => s.gameState.route);
  const missions = useGameStore((s) => s.gameState.activeMissions);

  const line = useMemo(() => {
    const situation = deriveSituation({
      attributionStatus: exposure.ATTRIBUTION.status,
      overallStatus: overallTrace(exposure).status,
      connected: !!session.connectedHost,
      hops: route.hops.length,
      acceptedCount: missions.filter((m) => m.status === "accepted").length,
    });
    const pool = MERCER_LINES.filter((l) => l.situation === situation);
    const chosen = pool.length ? pool : MERCER_LINES.filter((l) => l.situation === "intro");
    // Stable pick so it doesn't flicker every render.
    const idx = situation.length % Math.max(1, chosen.length);
    return { situation, text: chosen[idx]?.text ?? "Stay quiet. Get in, get out." };
  }, [exposure, session.connectedHost, route.hops.length, missions]);

  return (
    <div className="rounded border border-cyan-500/15 bg-black/60 p-4 font-mono">
      <div className="mb-1 flex items-center gap-2 text-[0.7rem]">
        <span className="h-2 w-2 rounded-full bg-cyan-400" />
        <span className="tracking-wider text-cyan-300">MERCER</span>
        <span className="text-[0.55rem] text-zinc-600">handler · {line.situation}</span>
      </div>
      <p className="text-[0.72rem] leading-snug text-zinc-300">&ldquo;{line.text}&rdquo;</p>
    </div>
  );
}
