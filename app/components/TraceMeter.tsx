"use client";

import { useEffect, useRef, useState } from "react";
import { useGameStore } from "@/app/lib/persistence/store";

// Narrative status messages based on trace level and status
const narrativeMessages: Record<string, string[]> = {
  CALM: [
    "SYSTEMS NOMINAL",
    "ALL CLEAR",
    "UNDETECTED",
    "GHOST PROTOCOL ACTIVE",
    "SHADOWS HOLD",
  ],
  ALERT: [
    "SUSPICIOUS ACTIVITY",
    "PATTERN DETECTED",
    "ANALYSIS IN PROGRESS",
    "ANOMALY FLAGGED",
    "WATCHLIST TRIGGERED",
  ],
  HUNT: [
    "TRACE IN PROGRESS",
    "HUNTER ACTIVE",
    "SIGNATURE LOCKED",
    "COUNTERMEASURES DEPLOYING",
    "EVASION RECOMMENDED",
  ],
  LOCKDOWN: [
    "FULL TRACE ACTIVE",
    "IDENTITY COMPROMISED",
    "EMERGENCY PROTOCOLS",
    "CONNECTION SEVERED",
    "ABORT MISSION",
  ],
};

const statusPalette: Record<string, { bg: string; text: string; pulse: string; border: string; glow: string }> = {
  CALM: { 
    bg: "bg-emerald-500", 
    text: "text-emerald-400", 
    pulse: "shadow-emerald-500/50",
    border: "border-emerald-500/30",
    glow: "emerald",
  },
  ALERT: { 
    bg: "bg-amber-400", 
    text: "text-amber-300", 
    pulse: "shadow-amber-400/50",
    border: "border-amber-500/40",
    glow: "amber",
  },
  HUNT: { 
    bg: "bg-orange-500", 
    text: "text-orange-300", 
    pulse: "shadow-orange-500/50",
    border: "border-orange-500/50",
    glow: "orange",
  },
  LOCKDOWN: { 
    bg: "bg-rose-500", 
    text: "text-rose-300", 
    pulse: "shadow-rose-500/50",
    border: "border-rose-500/60",
    glow: "rose",
  },
};

// Micro-event messages
const microEvents = [
  "packet sniffing...",
  "hash comparing...",
  "log analysis...",
  "pattern matching...",
  "signature scan...",
  "entropy check...",
];

export default function TraceMeter() {
  const trace = useGameStore((state) => state.gameState.trace);
  const [pulse, setPulse] = useState(false);
  const [narrativeIndex, setNarrativeIndex] = useState(0);
  const [microEvent, setMicroEvent] = useState<string | null>(null);
  const [glitchText, setGlitchText] = useState(false);
  const lastStatusRef = useRef(trace.status);
  const style = statusPalette[trace.status] ?? statusPalette.CALM;
  const messages = narrativeMessages[trace.status] ?? narrativeMessages.CALM;

  // Pulse animation on status change
  useEffect(() => {
    const prevStatus = lastStatusRef.current;
    if (trace.status !== prevStatus) {
      lastStatusRef.current = trace.status;
      setPulse(true);
      setGlitchText(true);
      setNarrativeIndex(0); // Reset to first message of new status
      
      const pulseTimer = setTimeout(() => setPulse(false), 1500);
      const glitchTimer = setTimeout(() => setGlitchText(false), 300);
      return () => {
        clearTimeout(pulseTimer);
        clearTimeout(glitchTimer);
      };
    }
  }, [trace.status]);

  // Rotate narrative messages
  useEffect(() => {
    const interval = setInterval(() => {
      setNarrativeIndex((prev) => (prev + 1) % messages.length);
    }, 4000);
    return () => clearInterval(interval);
  }, [messages.length]);

  // Random micro-events when trace is high
  useEffect(() => {
    if (trace.status === "CALM") {
      setMicroEvent(null);
      return;
    }
    
    const interval = setInterval(() => {
      if (Math.random() > 0.5) {
        const event = microEvents[Math.floor(Math.random() * microEvents.length)];
        setMicroEvent(event);
        setTimeout(() => setMicroEvent(null), 2000);
      }
    }, 3000);
    return () => clearInterval(interval);
  }, [trace.status]);

  const isHigh = trace.status === "HUNT" || trace.status === "LOCKDOWN";
  const currentMessage = messages[narrativeIndex];

  return (
    <div className={`w-full space-y-2 text-[11px] uppercase tracking-[0.15em] transition-all duration-300 ${pulse ? "scale-[1.02]" : ""}`}>
      {/* Status header with narrative message */}
      <div className={`flex items-center justify-between rounded border ${style.border} bg-black/40 px-3 py-2`}>
        <div className="flex items-center gap-2">
          {/* Animated indicator */}
          <div className={`relative h-2 w-2 rounded-full ${style.bg}`}>
            <div className={`absolute inset-0 rounded-full ${style.bg} ${isHigh ? "animate-ping" : "animate-pulse"}`} />
          </div>
          <span className={`font-semibold tracking-[0.2em] ${style.text} ${glitchText ? "animate-pulse" : ""}`}>
            {trace.status}
          </span>
        </div>
        
        {/* Narrative message with typewriter-like effect */}
        <span className={`font-mono text-[0.6rem] ${style.text} opacity-80`}>
          {currentMessage}
        </span>
      </div>

      {/* Visual trace bar - now without numbers, just visual intensity */}
      <div className="relative h-3 overflow-hidden rounded border border-zinc-800 bg-zinc-900/80">
        {/* Base fill */}
        <div
          className={`${style.bg} h-full transition-all duration-500`}
          style={{ width: `${trace.level}%` }}
        />
        
        {/* Animated gradient overlay */}
        <div 
          className={`absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent transition-opacity ${
            isHigh ? "opacity-100 animate-pulse" : "opacity-0"
          }`}
        />
        
        {/* Scanline effect for high trace */}
        {isHigh && (
          <div 
            className="absolute inset-0 bg-gradient-to-b from-transparent via-white/10 to-transparent"
            style={{
              animation: "scanline 1.5s linear infinite",
            }}
          />
        )}
        
        {/* Warning flash overlay */}
        {trace.status === "LOCKDOWN" && (
          <div className="absolute inset-0 animate-pulse bg-rose-500/30" />
        )}
      </div>

      {/* Micro-events ticker */}
      <div className="flex items-center justify-between text-[0.6rem]">
        <div className="flex items-center gap-1">
          {/* Last event */}
          {trace.lastEvent && (
            <span className="text-zinc-500 truncate max-w-[120px]">
              {trace.lastEvent}
            </span>
          )}
        </div>
        
        {/* Micro-event display */}
        {microEvent && (
          <span className={`${style.text} animate-pulse font-mono`}>
            {microEvent}
          </span>
        )}
      </div>

      {/* Warning messages at high trace */}
      {trace.status === "HUNT" && (
        <div className="flex items-center gap-2 rounded border border-orange-500/40 bg-orange-500/10 px-2 py-1 text-[0.6rem] text-orange-300">
          <span className="animate-pulse">⚠</span>
          <span>EVASIVE ACTION RECOMMENDED</span>
        </div>
      )}
      
      {trace.status === "LOCKDOWN" && (
        <div className="flex items-center gap-2 rounded border border-rose-500/50 bg-rose-500/20 px-2 py-1 text-[0.6rem] text-rose-300 animate-pulse">
          <span>🔒</span>
          <span>IMMEDIATE DISCONNECTION ADVISED</span>
        </div>
      )}

      <style jsx>{`
        @keyframes scanline {
          0% { transform: translateY(-100%); }
          100% { transform: translateY(100%); }
        }
      `}</style>
    </div>
  );
}
