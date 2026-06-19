"use client";

import { MouseEvent, PointerEvent, useEffect, useMemo, useRef, useState } from "react";
import type { RouteState, World, TraceInfo } from "@/types/game";
import { continents } from "@/app/lib/map/continents";
import { useGameStore } from "@/app/lib/persistence/store";

type MapCanvasProps = {
  world: World;
  route: RouteState;
  trace?: TraceInfo;
  focusHost?: string;
  session?: { connectedHost?: string; scannedHosts?: Set<string> };
  onProxyAdd?: (proxyId: string) => void;
  large?: boolean;
};

type HoverNode = { id: string; kind: "host" | "proxy" } | null;

const margin = 48;
const HIT_RADIUS = 18;

const CONTINENT_LIST: number[][][] = [
  continents.northAmerica,
  continents.centralAmerica,
  continents.southAmerica,
  continents.europe,
  continents.africa,
  continents.asia,
  continents.australia,
  continents.japan,
  continents.uk,
  continents.indonesia,
  continents.newZealand,
];

function pointInPolygon(x: number, y: number, poly: { x: number; y: number }[]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const xi = poly[i].x, yi = poly[i].y, xj = poly[j].x, yj = poly[j].y;
    const intersect = yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

export default function MapCanvas({ world, route, trace, focusHost, session, onProxyAdd, large = false }: MapCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const baseLayerRef = useRef<{ key: string; canvas: HTMLCanvasElement } | null>(null);
  const [hovered, setHovered] = useState<HoverNode>(null);
  const [hoveredLabel, setHoveredLabel] = useState<string | null>(null);
  const [phase, setPhase] = useState(0);
  const [routeAnimationPhase, setRouteAnimationPhase] = useState(0);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const routeLengthRef = useRef(route.hops.length);

  const scanAnimation = useGameStore((state) => state.scanAnimation);
  const [scanWaveProgress, setScanWaveProgress] = useState(0);

  const toCanvasPoint = useMemo(
    () => (lat: number, lon: number, width: number, height: number) => {
      const x = ((lon + 180) / 360) * (width - margin * 2) + margin;
      const y = height - (((lat + 90) / 180) * (height - margin * 2) + margin);
      return { x, y };
    },
    []
  );

  useEffect(() => {
    let frame: number;
    const animate = () => {
      if (route.hops.length !== routeLengthRef.current) {
        routeLengthRef.current = route.hops.length;
        setRouteAnimationPhase(0);
      }
      setPhase((current) => (current + 0.02) % (Math.PI * 2));
      setRouteAnimationPhase((current) => (current + 0.03) % (Math.PI * 2));
      frame = requestAnimationFrame(animate);
    };
    animate();
    return () => cancelAnimationFrame(frame);
  }, [route.hops.length]);

  useEffect(() => {
    if (!scanAnimation) {
      setScanWaveProgress(0);
      return;
    }
    const startTime = scanAnimation.startTime;
    const duration = scanAnimation.phase === "routing" ? 600 : scanAnimation.phase === "scanning" ? 800 : 400;
    let frame: number;
    const animateWave = () => {
      const elapsed = Date.now() - startTime;
      const progress = Math.min(elapsed / duration, 1);
      setScanWaveProgress(progress);
      if (progress < 1) frame = requestAnimationFrame(animateWave);
    };
    frame = requestAnimationFrame(animateWave);
    return () => cancelAnimationFrame(frame);
  }, [scanAnimation]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const { width, height } = canvas;
    const project = (lat: number, lon: number) => toCanvasPoint(lat, lon, width, height);

    // ---- Cached base layer: ocean + dot-matrix landmasses + vignette ----
    const key = `${width}x${height}`;
    if (!baseLayerRef.current || baseLayerRef.current.key !== key) {
      const off = document.createElement("canvas");
      off.width = width;
      off.height = height;
      const octx = off.getContext("2d");
      if (octx) {
        const ocean = octx.createLinearGradient(0, 0, 0, height);
        ocean.addColorStop(0, "#040a14");
        ocean.addColorStop(0.6, "#05101c");
        ocean.addColorStop(1, "#03070f");
        octx.fillStyle = ocean;
        octx.fillRect(0, 0, width, height);

        // faint graticule
        octx.strokeStyle = "rgba(56,189,248,0.05)";
        octx.lineWidth = 1;
        for (let gx = margin; gx <= width - margin; gx += (width - margin * 2) / 12) {
          octx.beginPath();
          octx.moveTo(gx, margin);
          octx.lineTo(gx, height - margin);
          octx.stroke();
        }
        for (let gy = margin; gy <= height - margin; gy += (height - margin * 2) / 6) {
          octx.beginPath();
          octx.moveTo(margin, gy);
          octx.lineTo(width - margin, gy);
          octx.stroke();
        }

        // dot-matrix continents
        const polys = CONTINENT_LIST.map((c) => c.map(([lat, lon]) => project(lat, lon)));
        const step = Math.max(6, Math.round(width / 165));
        const r = width > 1000 ? 1.45 : 1.15;
        for (let y = margin; y < height - margin; y += step) {
          for (let x = margin; x < width - margin; x += step) {
            let inside = false;
            for (const poly of polys) {
              if (pointInPolygon(x, y, poly)) {
                inside = true;
                break;
              }
            }
            if (!inside) continue;
            // subtle depth: a little brighter toward the equator band
            const lat = 90 - ((height - margin - y) / (height - margin * 2)) * 180;
            const a = 0.32 + 0.18 * (1 - Math.min(1, Math.abs(lat) / 70));
            octx.fillStyle = `rgba(96,178,228,${a.toFixed(3)})`;
            octx.beginPath();
            octx.arc(x, y, r, 0, Math.PI * 2);
            octx.fill();
          }
        }

        const vignette = octx.createRadialGradient(
          width * 0.5, height * 0.5, Math.min(width, height) * 0.35,
          width * 0.5, height * 0.5, Math.max(width, height) * 0.72
        );
        vignette.addColorStop(0, "rgba(0,0,0,0)");
        vignette.addColorStop(1, "rgba(0,0,0,0.45)");
        octx.fillStyle = vignette;
        octx.fillRect(0, 0, width, height);
      }
      baseLayerRef.current = { key, canvas: off };
    }

    ctx.clearRect(0, 0, width, height);
    ctx.drawImage(baseLayerRef.current.canvas, 0, 0);
    ctx.lineJoin = "round";
    ctx.lineCap = "round";

    const proxyPoints = Object.values(world.proxies).map((proxy) => ({
      id: proxy.id,
      point: project(proxy.geo.lat, proxy.geo.lon),
      proxy,
    }));

    // ---- Route line + a single clean data packet ----
    if (route.hops.length > 0) {
      const routePoints = route.hops
        .map((proxyId) => proxyPoints.find((entry) => entry.id === proxyId))
        .filter((n): n is NonNullable<typeof n> => n !== undefined);
      if (routePoints.length > 1) {
        ctx.strokeStyle = "rgba(56,189,248,0.55)";
        ctx.lineWidth = 1.5;
        ctx.setLineDash([6, 5]);
        ctx.lineDashOffset = -routeAnimationPhase * 12;
        ctx.beginPath();
        routePoints.forEach((n, i) => (i === 0 ? ctx.moveTo(n.point.x, n.point.y) : ctx.lineTo(n.point.x, n.point.y)));
        ctx.stroke();
        ctx.setLineDash([]);
        ctx.lineDashOffset = 0;

        const t = (Math.sin(routeAnimationPhase) + 1) / 2;
        const seg = routePoints.length - 1;
        const idx = Math.min(seg - 1, Math.floor(t * seg));
        const local = (t * seg) % 1;
        const a = routePoints[idx].point;
        const b = routePoints[idx + 1].point;
        const px = a.x + (b.x - a.x) * local;
        const py = a.y + (b.y - a.y) * local;
        ctx.beginPath();
        ctx.fillStyle = "rgba(125,211,252,0.95)";
        ctx.shadowColor = "rgba(56,189,248,0.9)";
        ctx.shadowBlur = 10;
        ctx.arc(px, py, 2.6, 0, Math.PI * 2);
        ctx.fill();
        ctx.shadowBlur = 0;
      }
    }

    // ---- Scan/connect wave ----
    if (scanAnimation && scanAnimation.toNode) {
      const targetHost = world.hosts[scanAnimation.toNode];
      if (targetHost) {
        const targetPoint = project(targetHost.geo.lat, targetHost.geo.lon);
        const pathPoints: { x: number; y: number }[] = [{ x: width / 2, y: height / 2 }];
        scanAnimation.throughProxies.forEach((proxyId) => {
          const proxy = world.proxies[proxyId];
          if (proxy) pathPoints.push(project(proxy.geo.lat, proxy.geo.lon));
        });
        pathPoints.push(targetPoint);

        const segLengths: number[] = [];
        let totalLength = 0;
        for (let i = 0; i < pathPoints.length - 1; i++) {
          const len = Math.hypot(pathPoints[i + 1].x - pathPoints[i].x, pathPoints[i + 1].y - pathPoints[i].y);
          segLengths.push(len);
          totalLength += len;
        }
        const waveDistance = scanWaveProgress * totalLength;
        let acc = 0;
        let waveX = pathPoints[0].x;
        let waveY = pathPoints[0].y;
        for (let i = 0; i < segLengths.length; i++) {
          if (acc + segLengths[i] >= waveDistance) {
            const lp = (waveDistance - acc) / segLengths[i];
            waveX = pathPoints[i].x + (pathPoints[i + 1].x - pathPoints[i].x) * lp;
            waveY = pathPoints[i].y + (pathPoints[i + 1].y - pathPoints[i].y) * lp;
            break;
          }
          acc += segLengths[i];
        }

        ctx.strokeStyle = "rgba(56,189,248,0.7)";
        ctx.lineWidth = 2;
        ctx.shadowColor = "rgba(56,189,248,0.9)";
        ctx.shadowBlur = 10;
        ctx.setLineDash([7, 5]);
        ctx.beginPath();
        ctx.moveTo(pathPoints[0].x, pathPoints[0].y);
        let drawn = 0;
        for (let i = 0; i < segLengths.length && drawn < waveDistance; i++) {
          if (segLengths[i] <= waveDistance - drawn) {
            ctx.lineTo(pathPoints[i + 1].x, pathPoints[i + 1].y);
            drawn += segLengths[i];
          } else {
            ctx.lineTo(waveX, waveY);
            break;
          }
        }
        ctx.stroke();
        ctx.setLineDash([]);

        const pulse = 5 + Math.sin(phase * 4) * 2;
        ctx.beginPath();
        ctx.fillStyle = "rgba(125,211,252,0.95)";
        ctx.arc(waveX, waveY, pulse, 0, Math.PI * 2);
        ctx.fill();
        ctx.shadowBlur = 0;

        if (scanWaveProgress >= 0.95) {
          const rr = 14 + (scanWaveProgress - 0.95) * 180;
          ctx.beginPath();
          ctx.strokeStyle = `rgba(56,189,248,${Math.max(0, 1 - (scanWaveProgress - 0.95) * 10) * 0.6})`;
          ctx.lineWidth = 2;
          ctx.arc(targetPoint.x, targetPoint.y, rr, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
    }

    // ---- Nodes ----
    const diamond = (x: number, y: number, s: number) => {
      ctx.beginPath();
      ctx.moveTo(x, y - s);
      ctx.lineTo(x + s, y);
      ctx.lineTo(x, y + s);
      ctx.lineTo(x - s, y);
      ctx.closePath();
    };

    // proxies (rings)
    proxyPoints.forEach(({ proxy, point }) => {
      const inRoute = route.hops.includes(proxy.id);
      const isHovered = hovered?.kind === "proxy" && hovered.id === proxy.id;
      const x = point.x, y = point.y;
      if (inRoute) {
        ctx.beginPath();
        ctx.strokeStyle = `rgba(56,189,248,${0.5 + Math.sin(phase) * 0.3})`;
        ctx.lineWidth = 1.5;
        ctx.arc(x, y, 7 + Math.sin(phase) * 1.5, 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.beginPath();
      ctx.arc(x, y, inRoute ? 3.4 : isHovered ? 3 : 2.2, 0, Math.PI * 2);
      ctx.fillStyle = inRoute ? "rgba(125,211,252,1)" : isHovered ? "rgba(125,211,252,0.9)" : "rgba(125,211,252,0.45)";
      ctx.fill();
      if (proxy.heat > 0.5) {
        ctx.beginPath();
        ctx.arc(x, y, 5.5, 0, Math.PI * 2);
        ctx.strokeStyle = `rgba(248,113,113,${proxy.heat * 0.7})`;
        ctx.lineWidth = 1;
        ctx.stroke();
      }
    });

    // hosts (diamonds)
    Object.values(world.hosts).forEach((host) => {
      const { x, y } = project(host.geo.lat, host.geo.lon);
      const isTarget = focusHost === host.id;
      const isConnected = session?.connectedHost === host.id;
      const isHovered = hovered?.kind === "host" && hovered.id === host.id;
      const color = isTarget ? "rgba(251,146,60,1)" : isConnected ? "rgba(52,211,153,1)" : isHovered ? "rgba(125,211,252,0.95)" : "rgba(125,211,252,0.5)";
      const s = isTarget ? 5.5 : 4;
      if (isTarget) {
        for (let i = 0; i < 2; i++) {
          ctx.beginPath();
          ctx.strokeStyle = `rgba(251,146,60,${(0.5 + Math.sin(phase) * 0.3) - i * 0.2})`;
          ctx.lineWidth = 1;
          ctx.arc(x, y, 11 + i * 5 + Math.sin(phase) * 2, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
      diamond(x, y, s);
      if (isTarget || isConnected) {
        ctx.fillStyle = color;
        ctx.fill();
      } else {
        ctx.strokeStyle = color;
        ctx.lineWidth = 1.25;
        ctx.stroke();
      }
    });

    // ---- Smart labels (only the few that matter) ----
    const drawLabel = (x: number, y: number, text: string, color: string) => {
      ctx.font = "11px 'IBM Plex Mono', ui-monospace, monospace";
      const w = ctx.measureText(text).width;
      const flip = x > width * 0.74;
      const lx = flip ? x - 12 - w - 8 : x + 12;
      const ly = y - 7;
      ctx.fillStyle = "rgba(3,8,14,0.82)";
      ctx.beginPath();
      if (ctx.roundRect) ctx.roundRect(lx - 5, ly, w + 10, 16, 4);
      else ctx.rect(lx - 5, ly, w + 10, 16);
      ctx.fill();
      ctx.fillStyle = color;
      ctx.textAlign = "left";
      ctx.fillText(text, lx, ly + 12);
      // tiny connector
      ctx.strokeStyle = "rgba(125,211,252,0.3)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(flip ? x - 5 : x + 5, y);
      ctx.lineTo(flip ? lx + w + 5 : lx - 5, ly + 8);
      ctx.stroke();
    };

    const labeled = new Set<string>();
    const labelHost = (id: string | undefined, color: string) => {
      if (!id || labeled.has(`h:${id}`)) return;
      const host = world.hosts[id];
      if (!host) return;
      const { x, y } = project(host.geo.lat, host.geo.lon);
      drawLabel(x, y, host.label, color);
      labeled.add(`h:${id}`);
    };
    // route proxies
    route.hops.forEach((id) => {
      const entry = proxyPoints.find((p) => p.id === id);
      if (entry) drawLabel(entry.point.x, entry.point.y, entry.proxy.label, "rgba(125,211,252,0.95)");
    });
    labelHost(session?.connectedHost, "rgba(52,211,153,1)");
    labelHost(focusHost, "rgba(251,146,60,1)");
    if (hovered?.kind === "host") labelHost(hovered.id, "rgba(191,219,254,0.95)");
    if (hovered?.kind === "proxy") {
      const entry = proxyPoints.find((p) => p.id === hovered.id);
      if (entry && !route.hops.includes(hovered.id)) drawLabel(entry.point.x, entry.point.y, entry.proxy.label, "rgba(191,219,254,0.95)");
    }
  }, [route.hops, route.anonymity, focusHost, phase, routeAnimationPhase, hovered, world, toCanvasPoint, session, scanAnimation, scanWaveProgress]);

  const nearestNode = (event: { clientX: number; clientY: number }) => {
    const canvas = canvasRef.current;
    if (!canvas) return null;
    const rect = canvas.getBoundingClientRect();
    const { width, height } = canvas;
    const mx = ((event.clientX - rect.left) / rect.width) * width;
    const my = ((event.clientY - rect.top) / rect.height) * height;
    let best: { id: string; kind: "host" | "proxy"; dist: number } | null = null;
    for (const proxy of Object.values(world.proxies)) {
      const p = toCanvasPoint(proxy.geo.lat, proxy.geo.lon, width, height);
      const d = Math.hypot(p.x - mx, p.y - my);
      if (!best || d < best.dist) best = { id: proxy.id, kind: "proxy", dist: d };
    }
    for (const host of Object.values(world.hosts)) {
      const p = toCanvasPoint(host.geo.lat, host.geo.lon, width, height);
      const d = Math.hypot(p.x - mx, p.y - my);
      if (!best || d < best.dist) best = { id: host.id, kind: "host", dist: d };
    }
    return best && best.dist < HIT_RADIUS ? best : null;
  };

  const handlePointer = (event: PointerEvent<HTMLCanvasElement>) => {
    const near = nearestNode(event);
    if (!near) {
      setHovered(null);
      setHoveredLabel(null);
      return;
    }
    setHovered({ id: near.id, kind: near.kind });
    if (near.kind === "proxy") {
      const p = world.proxies[near.id];
      const inRoute = route.hops.includes(near.id);
      setHoveredLabel(
        `${p.label} · anon ${(p.anonymity * 100).toFixed(0)}% · heat ${(p.heat * 100).toFixed(0)}% · ${p.costPerUse}c${inRoute ? " · IN ROUTE" : " · click to add"}`
      );
    } else {
      const h = world.hosts[near.id];
      setHoveredLabel(`${h.label} · ${h.geo.region} · target with: scan ${h.id}`);
    }
  };

  const handleClick = (event: MouseEvent<HTMLCanvasElement>) => {
    if (!onProxyAdd) return;
    const near = nearestNode(event);
    if (near?.kind === "proxy") onProxyAdd(near.id);
  };

  const toggleFullscreen = () => {
    if (!containerRef.current) return;
    if (!isFullscreen) {
      containerRef.current.requestFullscreen?.();
      setIsFullscreen(true);
    } else {
      document.exitFullscreen?.();
      setIsFullscreen(false);
    }
  };

  useEffect(() => {
    const onChange = () => setIsFullscreen(!!document.fullscreenElement);
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);

  const canvasWidth = isFullscreen ? 1920 : large ? 1400 : 500;
  const canvasHeight = isFullscreen ? 960 : large ? 700 : 250;

  const traceColor = trace?.status === "LOCKDOWN" ? "bg-rose-500" : trace?.status === "HUNT" ? "bg-orange-500" : trace?.status === "ALERT" ? "bg-amber-500" : "bg-cyan-500";
  const traceTextColor = trace?.status === "LOCKDOWN" ? "text-rose-400" : trace?.status === "HUNT" ? "text-orange-400" : trace?.status === "ALERT" ? "text-amber-400" : "text-cyan-300";

  const containerClass = isFullscreen
    ? "fixed inset-0 z-50 bg-black flex items-center justify-center"
    : "w-full aspect-[2/1] rounded-lg border border-cyan-500/15 bg-[#03070f] overflow-hidden";

  return (
    <div ref={containerRef} className={`relative ${containerClass}`}>
      <div className="pointer-events-none absolute left-3 top-3 z-10 rounded bg-black/60 px-2.5 py-1 text-[0.62rem] uppercase tracking-[0.25em] text-cyan-400/70">
        Network Map
      </div>

      {large && trace && (
        <div className="absolute left-1/2 top-3 z-10 flex -translate-x-1/2 items-center gap-3 rounded bg-black/60 px-3 py-1.5">
          <span className="text-[0.6rem] uppercase tracking-[0.15em] text-zinc-500">Trace</span>
          <div className="h-1.5 w-28 overflow-hidden rounded-full bg-zinc-800">
            <div className={`h-full ${traceColor} transition-all duration-300`} style={{ width: `${Math.min(trace.level, 100)}%` }} />
          </div>
          <span className={`text-[0.7rem] font-semibold tabular-nums ${traceTextColor}`}>{trace.level.toFixed(1)}%</span>
          <span className={`rounded px-1.5 py-0.5 text-[0.6rem] font-semibold uppercase ${traceTextColor}`}>{trace.status}</span>
        </div>
      )}

      <div className="absolute right-3 top-3 z-10 flex items-center gap-3">
        <div className="flex gap-3 text-[0.58rem] text-zinc-500">
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-cyan-400" /> Proxy</span>
          <span className="flex items-center gap-1"><span className="inline-block h-2 w-2 rotate-45 bg-orange-400" /> Target</span>
        </div>
        <button
          onClick={toggleFullscreen}
          className="rounded bg-black/60 px-2 py-1 text-[0.62rem] text-zinc-400 transition-colors hover:text-cyan-300"
          title={isFullscreen ? "Exit fullscreen" : "Fullscreen"}
        >
          {isFullscreen ? "✕ Exit" : "⛶ Full"}
        </button>
      </div>

      <canvas
        ref={canvasRef}
        width={canvasWidth}
        height={canvasHeight}
        className={isFullscreen ? "max-h-full max-w-full cursor-crosshair" : "block h-full w-full cursor-crosshair"}
        style={{ aspectRatio: "2 / 1" }}
        onPointerMove={handlePointer}
        onPointerLeave={() => {
          setHovered(null);
          setHoveredLabel(null);
        }}
        onClick={handleClick}
      />

      <div className="absolute bottom-3 left-3 right-3 flex items-center justify-between gap-2">
        <div className="truncate rounded bg-black/70 px-2.5 py-1.5 text-[0.66rem] text-zinc-300">
          {hoveredLabel ??
            (route.hops.length > 0
              ? `Route: ${route.hops.length} hop${route.hops.length > 1 ? "s" : ""} · anonymity ${(route.anonymity * 100).toFixed(0)}% · ${route.latencyMs}ms`
              : "Click proxy nodes to build a route")}
        </div>
        {route.hops.length > 0 && (
          <div className="shrink-0 rounded bg-cyan-500/15 px-2.5 py-1.5 text-[0.66rem] font-semibold text-cyan-300">
            {route.hops.length} hop{route.hops.length > 1 ? "s" : ""} active
          </div>
        )}
      </div>
    </div>
  );
}
