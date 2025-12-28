"use client";

import { useMemo } from "react";
import { useGameStore } from "@/app/lib/persistence/store";

export default function MissionGuidance() {
  const activeMissions = useGameStore((state) => state.gameState.activeMissions);
  const session = useGameStore((state) => state.gameState.session);
  const route = useGameStore((state) => state.gameState.route);
  const inventory = useGameStore((state) => state.gameState.inventory);

  const activeMission = useMemo(() => {
    return activeMissions.find((m) => m.status === "accepted");
  }, [activeMissions]);

  const nextStep = useMemo(() => {
    if (!activeMission) return null;

    const { objective } = activeMission;
    const hostId = objective.hostId;

    // Check mission progress
    if (objective.type === "exfil") {
      const hasFile = inventory.some((item) => item.source === hostId && item.path === objective.targetPath);
      if (hasFile) {
        return { text: "File captured! Submit mission with: submit " + activeMission.id, type: "success" };
      }
      if (session.connectedHost === hostId) {
        return { text: "Find and copy target file: cp " + objective.targetPath + " @local", type: "info" };
      }
      if (route.hops.length === 0) {
        return { text: "Build proxy route: route add proxy-1 (or click nodes on map)", type: "warning" };
      }
      return { text: "Connect to target: connect " + hostId, type: "info" };
    }

    if (objective.type === "modify") {
      if (session.connectedHost === hostId) {
        return { text: "Edit target file: edit " + objective.targetPath + " key=value", type: "info" };
      }
      if (route.hops.length === 0) {
        return { text: "Build proxy route first", type: "warning" };
      }
      return { text: "Connect to target: connect " + hostId, type: "info" };
    }

    if (objective.type === "plant") {
      if (session.connectedHost === hostId) {
        return { text: "Plant tracer in: " + objective.targetPath, type: "info" };
      }
      if (route.hops.length === 0) {
        return { text: "Build proxy route first", type: "warning" };
      }
      return { text: "Connect to target: connect " + hostId, type: "info" };
    }

    return null;
  }, [activeMission, session, route, inventory]);

  if (!activeMission || !nextStep) {
    return (
      <div className="rounded border border-zinc-800 bg-black/40 p-3 text-[0.65rem] text-zinc-400">
        <div className="font-semibold uppercase tracking-[0.2em] text-zinc-500">Mission Status</div>
        <div className="mt-1">No active mission. Check inbox to accept one.</div>
      </div>
    );
  }

  return (
    <div className="rounded border border-zinc-800 bg-black/40 p-3 text-[0.65rem]">
      <div className="mb-2 flex items-center justify-between">
        <div className="font-semibold uppercase tracking-[0.2em] text-zinc-500">Active Mission</div>
        <div className="rounded bg-emerald-500/20 px-2 py-0.5 text-[0.6rem] text-emerald-300">IN PROGRESS</div>
      </div>
      <div className="mb-2 text-xs font-semibold text-white">{activeMission.title}</div>
      <div className={`rounded border px-2 py-1.5 ${
        nextStep.type === "success" ? "border-emerald-500/50 bg-emerald-500/10 text-emerald-300" :
        nextStep.type === "warning" ? "border-amber-500/50 bg-amber-500/10 text-amber-300" :
        "border-blue-500/50 bg-blue-500/10 text-blue-300"
      }`}>
        <div className="text-[0.6rem] uppercase tracking-[0.15em] opacity-70">Next Step</div>
        <div className="mt-0.5 font-mono text-[0.7rem]">{nextStep.text}</div>
      </div>
    </div>
  );
}

