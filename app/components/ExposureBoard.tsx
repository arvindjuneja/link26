"use client";

import { useEffect, useRef } from "react";
import { useGameStore } from "@/app/lib/persistence/store";
import { EXPOSURE_CHANNELS, overallTrace, topChannel } from "@/app/lib/game/exposure";
import { playHeartbeat } from "@/app/lib/audio/sounds";
import type { ExposureChannel, TraceStatus } from "@/types/game";

// Cold-glass palette: color is spent as tension rises. CALM is low-sat cyan
// (not bright green); LOCKDOWN burns toward the threat hue.
const STATUS_COLOR: Record<TraceStatus, { bar: string; text: string; glow: string }> = {
  CALM: { bar: "bg-cyan-500/60", text: "text-cyan-300", glow: "" },
  ALERT: { bar: "bg-amber-500/70", text: "text-amber-300", glow: "shadow-[0_0_12px_-2px] shadow-amber-500/40" },
  HUNT: { bar: "bg-orange-500/80", text: "text-orange-300", glow: "shadow-[0_0_16px_-2px] shadow-orange-500/50" },
  LOCKDOWN: { bar: "bg-rose-500/90", text: "text-rose-300", glow: "shadow-[0_0_22px_-1px] shadow-rose-500/60" },
};

// Beats per minute by worst-channel status; CALM is silent (and slow visually).
const BPM: Record<TraceStatus, number> = { CALM: 48, ALERT: 72, HUNT: 108, LOCKDOWN: 150 };

const CHANNEL_FEAR: Record<ExposureChannel, string> = {
  NETWORK: "tracing the packet back",
  RF: "someone in the building noticing",
  FOOTPRINT: "tipping them off by looking",
  ATTRIBUTION: "building a profile of you",
};

const NARRATIVE: Record<TraceStatus, string> = {
  CALM: "SYSTEMS NOMINAL",
  ALERT: "SUSPICIOUS ACTIVITY",
  HUNT: "TRACE IN PROGRESS",
  LOCKDOWN: "IDENTITY COMPROMISED",
};

export default function ExposureBoard() {
  const exposure = useGameStore((s) => s.gameState.exposure);
  const streak = useGameStore((s) => s.gameState.streak);
  const overall = overallTrace(exposure);
  const top = topChannel(exposure);
  const bpm = BPM[overall.status];
  const beatMs = Math.round(60000 / bpm);

  // Drive the audible heartbeat at BPM; silence at CALM is intentional.
  const beatRef = useRef<ReturnType<typeof setInterval> | null>(null);
  useEffect(() => {
    if (beatRef.current) clearInterval(beatRef.current);
    if (overall.status === "CALM") return; // reward: silence
    const intensity = overall.status === "LOCKDOWN" ? 1.2 : overall.status === "HUNT" ? 0.9 : 0.6;
    beatRef.current = setInterval(() => playHeartbeat(intensity), beatMs);
    return () => {
      if (beatRef.current) clearInterval(beatRef.current);
    };
  }, [overall.status, beatMs]);

  const oc = STATUS_COLOR[overall.status];

  return (
    <div className="font-mono">
      {/* Heartbeat row */}
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span
            className={`inline-block h-3 w-3 rounded-full ${oc.bar} ${oc.glow}`}
            style={{ animation: `pulse-beat ${beatMs}ms ease-in-out infinite` }}
          />
          <span className={`text-sm font-semibold tracking-wide ${oc.text}`}>{overall.status}</span>
          <span className="text-[0.6rem] text-zinc-500">{bpm} BPM</span>
        </div>
        <div className="text-right">
          <div className={`text-[0.65rem] uppercase tracking-wider ${oc.text}`}>{NARRATIVE[overall.status]}</div>
          {streak > 0 && (
            <div className="text-[0.6rem] text-cyan-400">ghost streak ×{streak}</div>
          )}
        </div>
      </div>

      {/* Per-channel bars */}
      <div className="space-y-2">
        {EXPOSURE_CHANNELS.map((ch) => {
          const c = exposure[ch];
          const col = STATUS_COLOR[c.status];
          const isTop = ch === top && c.level > 0;
          return (
            <div key={ch} title={`fear: ${CHANNEL_FEAR[ch]}`}>
              <div className="mb-0.5 flex items-center justify-between text-[0.6rem]">
                <span className={`tracking-wider ${isTop ? col.text : "text-zinc-500"}`}>{ch}</span>
                <span className={`tabular-nums ${col.text}`}>{c.level.toFixed(0)}%</span>
              </div>
              <div className="h-1.5 w-full overflow-hidden rounded-full bg-zinc-800/80">
                <div
                  className={`h-full rounded-full ${col.bar} transition-all duration-500`}
                  style={{ width: `${Math.min(100, c.level)}%` }}
                />
              </div>
            </div>
          );
        })}
      </div>

      <p className="mt-3 text-[0.6rem] leading-snug text-zinc-600">
        triage the board — you can&apos;t zero every channel. exit before the worst one closes the window.
      </p>

      <style jsx>{`
        @keyframes pulse-beat {
          0%, 100% { transform: scale(1); opacity: 0.85; }
          12% { transform: scale(1.7); opacity: 1; }
          24% { transform: scale(1); opacity: 0.85; }
          36% { transform: scale(1.4); opacity: 0.95; }
        }
      `}</style>
    </div>
  );
}
