// The Exposure Board engine.
//
// UPLINK had one trace number that beeped like a heart-rate monitor as the
// window closed. We keep that feeling but instantiate it per detection vector:
// the player must triage several rising bars at once. trace.ts (the pure noise
// math) is reused verbatim, once per channel.

import type {
  ExposureChannel,
  ExposureState,
  Host,
  RouteState,
  TraceInfo,
  TraceStatus,
} from "@/types/game";
import { addTraceNoise, decayTrace, getTraceStatus } from "@/app/lib/game/trace";

export const EXPOSURE_CHANNELS: ExposureChannel[] = [
  "NETWORK",
  "RF",
  "FOOTPRINT",
  "ATTRIBUTION",
];

const STATUS_RANK: Record<TraceStatus, number> = {
  CALM: 0,
  ALERT: 1,
  HUNT: 2,
  LOCKDOWN: 3,
};

// How fast each channel cools per idle tick. ATTRIBUTION barely fades — that is
// the whole point of the "they're profiling me" fear; it persists across the run.
const DECAY_SCALE: Record<ExposureChannel, number> = {
  NETWORK: 1,
  RF: 0.7,
  FOOTPRINT: 0.5,
  ATTRIBUTION: 0.08,
};

// Per-tick exposure added to NETWORK while a session is held open — the
// connection-time dwell clock. Holding a session is never free; the heartbeat
// climbs the longer you stay in.
const DWELL_NOISE = 3;

const channel = (level: number, lastEvent: string): TraceInfo => ({
  level,
  status: getTraceStatus(level),
  lastEvent,
});

export function createExposure(networkStart = 8): ExposureState {
  return {
    NETWORK: channel(networkStart, "Session initialized"),
    RF: channel(0, "RF silent"),
    FOOTPRINT: channel(0, "No footprint"),
    ATTRIBUTION: channel(0, "Clean identity"),
  };
}

/**
 * Add noise to a single channel (everything else untouched). `mitigation`
 * (0..1) is the player's gear flattening this channel. Pure.
 */
export function applyChannelNoise(
  exp: ExposureState,
  ch: ExposureChannel,
  baseNoise: number,
  route: RouteState,
  host?: Host,
  mitigation = 0
): ExposureState {
  return {
    ...exp,
    [ch]: addTraceNoise(exp[ch], baseNoise * (1 - mitigation), route, host),
  };
}

/**
 * One real-time tick. While connected, NETWORK rises (dwell clock); otherwise it
 * cools. RF/FOOTPRINT cool over time; ATTRIBUTION barely moves. Pure.
 */
export function tickExposure(
  exp: ExposureState,
  opts: {
    connected: boolean;
    route: RouteState;
    host?: Host;
    networkMitigation?: number;
  }
): ExposureState {
  return {
    NETWORK: opts.connected
      ? addTraceNoise(exp.NETWORK, DWELL_NOISE * (1 - (opts.networkMitigation ?? 0)), opts.route, opts.host)
      : decayTrace(exp.NETWORK, DECAY_SCALE.NETWORK),
    RF: decayTrace(exp.RF, DECAY_SCALE.RF),
    FOOTPRINT: decayTrace(exp.FOOTPRINT, DECAY_SCALE.FOOTPRINT),
    ATTRIBUTION: decayTrace(exp.ATTRIBUTION, DECAY_SCALE.ATTRIBUTION),
  };
}

/** The single headline status driving the heartbeat/page-tint: the worst channel. */
export function overallTrace(exp: ExposureState): TraceInfo {
  let top = exp.NETWORK;
  for (const ch of EXPOSURE_CHANNELS) {
    const t = exp[ch];
    const better =
      STATUS_RANK[t.status] > STATUS_RANK[top.status] ||
      (STATUS_RANK[t.status] === STATUS_RANK[top.status] && t.level > top.level);
    if (better) top = t;
  }
  return top;
}

export type ExitOutcome = "clean" | "hot" | "burned";

/** Classify an exit by the worst channel: ghost / tripped / burned. */
export function missionOutcome(exp: ExposureState): ExitOutcome {
  let worst = 0;
  for (const ch of EXPOSURE_CHANNELS) {
    worst = Math.max(worst, STATUS_RANK[exp[ch].status]);
  }
  if (worst >= STATUS_RANK.LOCKDOWN) return "burned";
  if (worst >= STATUS_RANK.HUNT) return "hot";
  return "clean";
}

/** The channel currently carrying the most heat (for UI emphasis). */
export function topChannel(exp: ExposureState): ExposureChannel {
  let best: ExposureChannel = "NETWORK";
  for (const ch of EXPOSURE_CHANNELS) {
    if (exp[ch].level > exp[best].level) best = ch;
  }
  return best;
}
