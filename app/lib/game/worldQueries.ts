// Pure read helpers + small math shared by the reducer and the store.
// Extracted so the migration to the pure reducer doesn't duplicate logic.

import type { Host, Person, ProxyNode, RfEmitter, RouteState, World } from "@/types/game";

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

/** Cool every proxy's heat slightly (called on the idle tick). Pure. */
export function coolProxies(
  proxies: Record<string, ProxyNode>,
  rate = 0.04
): Record<string, ProxyNode> {
  const next: Record<string, ProxyNode> = {};
  for (const [id, p] of Object.entries(proxies)) {
    next[id] = p.heat > 0 ? { ...p, heat: clamp(p.heat - rate, 0, 1) } : p;
  }
  return next;
}

/** Resolve a person by id or fuzzy handle/org match. */
export function findPerson(world: World, query?: string): Person | undefined {
  if (!query) return undefined;
  const q = query.toLowerCase();
  return Object.values(world.people).find(
    (p) =>
      p.id === q ||
      p.id === query ||
      p.label.toLowerCase().includes(q) ||
      (p.org ?? "").toLowerCase().includes(q)
  );
}

/** Resolve an RF emitter by id, label, or the host site it sits at. */
export function findEmitter(world: World, query?: string): RfEmitter | undefined {
  if (!query) return undefined;
  const q = query.toLowerCase();
  return Object.values(world.emitters).find(
    (e) =>
      e.id === q ||
      e.id === query ||
      e.label.toLowerCase().includes(q) ||
      (e.siteHostId ?? "").toLowerCase() === q
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
