// Pure read helpers + small math shared by the reducer and the store.
// Extracted so the migration to the pure reducer doesn't duplicate logic.

import type { Host, ProxyNode, RouteState, World } from "@/types/game";

export const clamp = (value: number, min: number, max: number) =>
  Math.max(min, Math.min(max, value));

/** Derive latency/anonymity for a proxy hop list. */
export function buildRouteState(
  hops: string[],
  proxies: Record<string, ProxyNode>
): RouteState {
  let latency = 0;
  let anonymity = 0;
  hops.forEach((proxyId) => {
    const node = proxies[proxyId];
    if (!node) return;
    latency += 30 + node.costPerUse;
    anonymity = 1 - (1 - anonymity) * (1 - clamp(node.anonymity, 0, 1));
  });
  return {
    hops: [...hops],
    latencyMs: latency,
    anonymity: clamp(anonymity, 0, 0.99),
  };
}

/** Resolve a host by id or fuzzy label match. */
export function findHost(world: World, query?: string): Host | undefined {
  if (!query) return undefined;
  const normalized = query.toLowerCase();
  return Object.values(world.hosts).find(
    (host) =>
      host.id === normalized ||
      host.label.toLowerCase().includes(normalized) ||
      host.id === query
  );
}

/** List a host's filesystem entries under a path (one level deep at root). */
export function listFiles(host: Host, path: string): string[] {
  const normalized = path === "/" ? "/" : path.replace(/\/+$/, "");
  const entries = host.filesystem
    .filter((entry) => {
      if (normalized === "/") return entry.path.split("/").filter(Boolean).length <= 2;
      return entry.path.startsWith(`${normalized}/`);
    })
    .map((entry) => `${entry.type.padEnd(4)} ${entry.name}`);
  return entries.length ? entries : ["<empty directory>"];
}
