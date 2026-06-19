"use client";

import { useEffect, useRef } from "react";
import { useGameStore } from "@/app/lib/persistence/store";
import { overallTrace } from "@/app/lib/game/exposure";
import type { TraceStatus } from "@/types/game";
import {
  playTraceRise,
  playTraceWarning,
  setAmbientTension,
  startAmbient,
  stopAmbient,
} from "@/app/lib/audio/sounds";

const RANK: Record<TraceStatus, number> = { CALM: 0, ALERT: 1, HUNT: 2, LOCKDOWN: 3 };
const TENSION: Record<TraceStatus, number> = { CALM: 0, ALERT: 0.4, HUNT: 0.75, LOCKDOWN: 1 };

// Drives the ambient bed + escalation stingers. The AudioContext only unlocks
// after a user gesture, so we start the bed on the first sound cue (which always
// follows a command the player typed).
export default function AudioController() {
  const status = useGameStore((s) => overallTrace(s.gameState.exposure).status);
  const soundCue = useGameStore((s) => s.soundCue);
  const started = useRef(false);
  const prev = useRef<TraceStatus>(status);

  useEffect(() => {
    if (!started.current && soundCue) {
      started.current = true;
      startAmbient();
    }
  }, [soundCue]);

  useEffect(() => {
    setAmbientTension(TENSION[status]);
    if (RANK[status] > RANK[prev.current]) {
      if (status === "LOCKDOWN") playTraceWarning();
      else playTraceRise();
    }
    prev.current = status;
  }, [status]);

  useEffect(() => () => stopAmbient(), []);

  return null;
}
