import { Host, RouteState, TraceInfo, TraceStatus } from "@/types/game";

const statusThresholds: Record<TraceStatus, number> = {
  CALM: 0,
  ALERT: 25,
  HUNT: 50,
  LOCKDOWN: 80,
};

export function getTraceStatus(level: number): TraceStatus {
  if (level >= statusThresholds.LOCKDOWN) return "LOCKDOWN";
  if (level >= statusThresholds.HUNT) return "HUNT";
  if (level >= statusThresholds.ALERT) return "ALERT";
  return "CALM";
}

export function clampLevel(level: number): number {
  return Math.max(0, Math.min(100, level));
}

export function addTraceNoise(
  trace: TraceInfo,
  baseNoise: number,
  route: RouteState,
  host?: Host
): TraceInfo {
  const anonymity = route?.anonymity ?? 0;
  const hostMonitor = host?.monitoring ?? 0.2;
  // Without route, noise is amplified (direct connection = more detectable)
  const routePenalty = anonymity === 0 ? 1.5 : 1.0;
  const effectiveNoise = baseNoise * (1 - anonymity * 0.7) * Math.max(hostMonitor, 0.15) * routePenalty;
  const nextLevel = clampLevel(trace.level + effectiveNoise);
  return {
    ...trace,
    level: nextLevel,
    status: getTraceStatus(nextLevel),
    lastEvent: `Noise +${effectiveNoise.toFixed(1)}`,
  };
}

export function decayTrace(trace: TraceInfo): TraceInfo {
  // Decay slower - only when disconnected/idle
  // Decay faster if trace is high (pressure to disconnect)
  const decayRate = trace.level > 50 ? 1.2 : trace.level > 25 ? 0.8 : 0.4;
  const nextLevel = clampLevel(trace.level - decayRate);
  return {
    ...trace,
    level: nextLevel,
    status: getTraceStatus(nextLevel),
  };
}
