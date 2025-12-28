"use client";

import { useEffect, useRef, useState } from "react";
import { useGameStore } from "@/app/lib/persistence/store";

const statusPalette: Record<string, { bg: string; text: string; pulse: string }> = {
  CALM: { bg: "bg-emerald-500", text: "text-emerald-400", pulse: "shadow-emerald-500/50" },
  ALERT: { bg: "bg-amber-400", text: "text-amber-300", pulse: "shadow-amber-400/50" },
  HUNT: { bg: "bg-orange-500", text: "text-orange-300", pulse: "shadow-orange-500/50" },
  LOCKDOWN: { bg: "bg-rose-500", text: "text-rose-300", pulse: "shadow-rose-500/50" },
};

export default function TraceMeter() {
  const trace = useGameStore((state) => state.gameState.trace);
  const [pulse, setPulse] = useState(false);
  const lastStatusRef = useRef(trace.status);
  const style = statusPalette[trace.status] ?? statusPalette.CALM;

  useEffect(() => {
    const prevStatus = lastStatusRef.current;
    if (trace.status !== prevStatus) {
      lastStatusRef.current = trace.status;
      // Intentional animation trigger on status change
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setPulse(true);
      const timer = setTimeout(() => setPulse(false), 1000);
      return () => clearTimeout(timer);
    }
  }, [trace.status]);

  const isHigh = trace.status === "HUNT" || trace.status === "LOCKDOWN";

  return (
    <div className={`w-full space-y-1 text-[11px] uppercase tracking-[0.2em] transition-all ${pulse ? "scale-105" : ""}`}>
      <div className="flex items-center justify-between text-[0.65rem]">
        <span className="text-zinc-400">trace level</span>
        <span className={`font-semibold ${style.text} ${pulse ? "animate-pulse" : ""}`}>
          {trace.status}
          {isHigh && " ⚠"}
        </span>
      </div>
      <div className="relative h-2 overflow-hidden rounded border border-zinc-800 bg-zinc-900">
        <div
          className={`${style.bg} h-full transition-all duration-300 ${pulse ? `shadow-lg ${style.pulse}` : ""}`}
          style={{ width: `${trace.level}%` }}
        />
        {isHigh && (
          <div className="absolute inset-0 animate-pulse bg-white/10" />
        )}
      </div>
      <div className="flex items-center justify-between text-[0.65rem]">
        <span className="text-zinc-500">{trace.level.toFixed(1)}%</span>
        {trace.lastEvent && (
          <span className="text-zinc-600">{trace.lastEvent}</span>
        )}
      </div>
    </div>
  );
}
