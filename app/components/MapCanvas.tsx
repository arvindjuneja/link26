"use client";

import { MouseEvent, PointerEvent, useEffect, useMemo, useRef, useState } from "react";
import type { RouteState, World, TraceInfo } from "@/types/game";
import { continents, drawContinent } from "@/app/lib/map/continents";
import { useGameStore, ScanAnimation } from "@/app/lib/persistence/store";

type MapCanvasProps = {
  world: World;
  route: RouteState;
  trace?: TraceInfo;
  focusHost?: string;
  session?: { connectedHost?: string; scannedHosts?: Set<string> };
  onProxyAdd?: (proxyId: string) => void;
  large?: boolean;
};

const margin = 40;

export default function MapCanvas({ world, route, trace, focusHost, session, onProxyAdd, large = false }: MapCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [hoveredLabel, setHoveredLabel] = useState<string | null>(null);
  const [hoveredProxyId, setHoveredProxyId] = useState<string | null>(null);
  const [phase, setPhase] = useState(0);
  const [routeAnimationPhase, setRouteAnimationPhase] = useState(0);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const routeLengthRef = useRef(route.hops.length);
  
  // Scan animation state from store
  const scanAnimation = useGameStore((state) => state.scanAnimation);
  const [scanWaveProgress, setScanWaveProgress] = useState(0);

  const nodes = useMemo(() => ({
    proxies: Object.values(world.proxies),
    hosts: Object.values(world.hosts),
  }), [world]);

  const toCanvasPoint = useMemo(
    () => (lat: number, lon: number, width: number, height: number) => {
      // Use world map projection (Mercator-like) instead of bounding box
      const x = ((lon + 180) / 360) * (width - margin * 2) + margin;
      const y = height - (((lat + 90) / 180) * (height - margin * 2) + margin);
      return { x, y };
    },
    []
  );

  useEffect(() => {
    let frame: number;
    const animate = () => {
      // Reset route animation if route length changed
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

  // Scan wave animation
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
      
      if (progress < 1) {
        frame = requestAnimationFrame(animateWave);
      }
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

    ctx.clearRect(0, 0, width, height);

    // -------- Background layers (Uplink-like) --------
    ctx.save();
    ctx.imageSmoothingEnabled = true;
    ctx.lineJoin = "round";
    ctx.lineCap = "round";

    // Ocean gradient
    const ocean = ctx.createLinearGradient(0, 0, 0, height);
    ocean.addColorStop(0, "#050b1a");
    ocean.addColorStop(0.55, "#060d1f");
    ocean.addColorStop(1, "#02050f");
    ctx.fillStyle = ocean;
    ctx.fillRect(0, 0, width, height);

    // Dotted grid pattern (cached per size bucket)
    const dotSize = isFullscreen ? 1.3 : 1;
    const dotStep = isFullscreen ? 16 : 14;
    const patternCanvas = document.createElement("canvas");
    patternCanvas.width = dotStep * 6;
    patternCanvas.height = dotStep * 6;
    const pctx = patternCanvas.getContext("2d");
    if (pctx) {
      pctx.clearRect(0, 0, patternCanvas.width, patternCanvas.height);
      for (let y = 0; y < patternCanvas.height; y += dotStep) {
        for (let x = 0; x < patternCanvas.width; x += dotStep) {
          // subtle variation
          const a = 0.08 + ((x + y) % (dotStep * 3) === 0 ? 0.06 : 0);
          pctx.fillStyle = `rgba(255,255,255,${a})`;
          pctx.beginPath();
          pctx.arc(x + 0.5, y + 0.5, dotSize, 0, Math.PI * 2);
          pctx.fill();
        }
      }
    }
    const pattern = ctx.createPattern(patternCanvas, "repeat");
    if (pattern) {
      ctx.globalAlpha = 0.35;
      ctx.fillStyle = pattern;
      ctx.fillRect(0, 0, width, height);
      ctx.globalAlpha = 1;
    }

    // Subtle scanlines
    ctx.globalAlpha = 0.08;
    ctx.strokeStyle = "rgba(255,255,255,0.06)";
    ctx.lineWidth = 1;
    const scanStep = isFullscreen ? 6 : 5;
    for (let y = 0; y < height; y += scanStep) {
      ctx.beginPath();
      ctx.moveTo(0, y + 0.5);
      ctx.lineTo(width, y + 0.5);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;

    // Vignette
    const vignette = ctx.createRadialGradient(
      width * 0.5,
      height * 0.48,
      Math.min(width, height) * 0.25,
      width * 0.5,
      height * 0.5,
      Math.max(width, height) * 0.7
    );
    vignette.addColorStop(0, "rgba(0,0,0,0)");
    vignette.addColorStop(1, "rgba(0,0,0,0.55)");
    ctx.fillStyle = vignette;
    ctx.fillRect(0, 0, width, height);

    // Tiny grain (cheap noise)
    ctx.globalAlpha = 0.07;
    ctx.fillStyle = "rgba(255,255,255,1)";
    const grainCount = isFullscreen ? 1200 : 220;
    for (let i = 0; i < grainCount; i++) {
      const gx = Math.random() * width;
      const gy = Math.random() * height;
      ctx.fillRect(gx, gy, 1, 1);
    }
    ctx.globalAlpha = 1;
    ctx.restore();

    // World map projection function
    const worldToCanvas = (lat: number, lon: number) => {
      const x = ((lon + 180) / 360) * (width - margin * 2) + margin;
      const y = height - (((lat + 90) / 180) * (height - margin * 2) + margin);
      return { x, y };
    };

    // Draw all continents with fill and glow like Uplink
    const continentList = [
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

    // Continents: fill + glow stroke + crisp stroke (Uplink-like)
    ctx.save();
    ctx.lineJoin = "round";
    ctx.lineCap = "round";

    // Fill
    ctx.fillStyle = "rgba(30, 58, 138, 0.42)";
    ctx.strokeStyle = "rgba(96, 165, 250, 0.35)";
    ctx.lineWidth = isFullscreen ? 1.25 : 1;
    continentList.forEach((continent) => drawContinent(ctx, continent, worldToCanvas, true));

    // Glow stroke pass
    ctx.globalCompositeOperation = "screen";
    ctx.strokeStyle = "rgba(96, 165, 250, 0.85)";
    ctx.lineWidth = isFullscreen ? 2.4 : 1.9;
    ctx.shadowColor = "rgba(96, 165, 250, 0.95)";
    ctx.shadowBlur = isFullscreen ? 18 : 10;
    continentList.forEach((continent) => {
      // draw without fill; drawContinent always closes path so this is ok
      drawContinent(ctx, continent, worldToCanvas, false);
    });

    // Crisp outline pass
    ctx.globalCompositeOperation = "source-over";
    ctx.shadowBlur = 0;
    ctx.strokeStyle = "rgba(191, 219, 254, 0.65)";
    ctx.lineWidth = isFullscreen ? 1.25 : 1;
    continentList.forEach((continent) => drawContinent(ctx, continent, worldToCanvas, false));
    ctx.restore();

    const proxyPoints = nodes.proxies.map((proxy) => ({
      id: proxy.id,
      point: toCanvasPoint(proxy.geo.lat, proxy.geo.lon, width, height),
      proxy,
    }));

    // Draw animated route line with pulse effect and data packets
    if (route.hops.length > 0) {
      const routePoints = route.hops
        .map((proxyId) => proxyPoints.find((entry) => entry.id === proxyId))
        .filter((node): node is NonNullable<typeof node> => node !== undefined);

      if (routePoints.length > 1) {
        // Draw base route line with dashed pattern like Uplink
        ctx.strokeStyle = "rgba(16, 185, 129, 0.8)";
        ctx.lineWidth = 2;
        ctx.setLineDash([5, 3]);
        ctx.shadowColor = "rgba(16, 185, 129, 0.6)";
        ctx.shadowBlur = 4;
        ctx.beginPath();
        routePoints.forEach((node, index) => {
          if (index === 0) ctx.moveTo(node.point.x, node.point.y);
          else ctx.lineTo(node.point.x, node.point.y);
        });
        ctx.stroke();
        ctx.setLineDash([]); // Reset dash
        ctx.shadowBlur = 0;

        // Draw animated data packets along route
        const pulseProgress = (Math.sin(routeAnimationPhase) + 1) / 2;
        const segmentLength = routePoints.length - 1;
        const pulseIndex = Math.floor(pulseProgress * segmentLength);
        if (pulseIndex < segmentLength) {
          const start = routePoints[pulseIndex];
          const end = routePoints[pulseIndex + 1];
          const localProgress = (pulseProgress * segmentLength) % 1;
          const pulseX = start.point.x + (end.point.x - start.point.x) * localProgress;
          const pulseY = start.point.y + (end.point.y - start.point.y) * localProgress;

          // Main pulse
          ctx.beginPath();
          ctx.fillStyle = "rgba(16, 185, 129, 0.9)";
          ctx.shadowColor = "rgba(16, 185, 129, 1)";
          ctx.shadowBlur = 16;
          ctx.arc(pulseX, pulseY, 5, 0, Math.PI * 2);
          ctx.fill();
          
          // Outer ring
          ctx.beginPath();
          ctx.strokeStyle = "rgba(16, 185, 129, 0.6)";
          ctx.lineWidth = 2;
          ctx.arc(pulseX, pulseY, 8 + Math.sin(routeAnimationPhase * 2) * 2, 0, Math.PI * 2);
          ctx.stroke();
          ctx.shadowBlur = 0;
        }

        // Draw multiple smaller packets for busier feel
        for (let i = 0; i < 2; i++) {
          const offset = (routeAnimationPhase + i * Math.PI) % (Math.PI * 2);
          const packetProgress = (Math.sin(offset) + 1) / 2;
          const packetSegment = Math.floor(packetProgress * segmentLength);
          if (packetSegment < segmentLength) {
            const pStart = routePoints[packetSegment];
            const pEnd = routePoints[packetSegment + 1];
            const pLocal = (packetProgress * segmentLength) % 1;
            const px = pStart.point.x + (pEnd.point.x - pStart.point.x) * pLocal;
            const py = pStart.point.y + (pEnd.point.y - pStart.point.y) * pLocal;

            ctx.beginPath();
            ctx.fillStyle = `rgba(16, 185, 129, ${0.5 - i * 0.2})`;
            ctx.arc(px, py, 3, 0, Math.PI * 2);
            ctx.fill();
          }
        }
      }
    }

    // -------- SCAN WAVE ANIMATION --------
    if (scanAnimation && scanAnimation.toNode) {
      const targetHost = world.hosts[scanAnimation.toNode];
      if (targetHost) {
        const targetPoint = toCanvasPoint(targetHost.geo.lat, targetHost.geo.lon, width, height);
        
        // Build the path: player/center -> proxies -> target
        const pathPoints: { x: number; y: number }[] = [];
        
        // Start point (center of canvas for "player")
        pathPoints.push({ x: width / 2, y: height / 2 });
        
        // Add proxy hops
        scanAnimation.throughProxies.forEach((proxyId) => {
          const proxy = world.proxies[proxyId];
          if (proxy) {
            const point = toCanvasPoint(proxy.geo.lat, proxy.geo.lon, width, height);
            pathPoints.push(point);
          }
        });
        
        // End point is the target
        pathPoints.push(targetPoint);
        
        // Calculate total path length
        let totalLength = 0;
        const segmentLengths: number[] = [];
        for (let i = 0; i < pathPoints.length - 1; i++) {
          const dx = pathPoints[i + 1].x - pathPoints[i].x;
          const dy = pathPoints[i + 1].y - pathPoints[i].y;
          const len = Math.sqrt(dx * dx + dy * dy);
          segmentLengths.push(len);
          totalLength += len;
        }
        
        // Draw the scan wave traveling along the path
        const waveProgress = scanWaveProgress;
        const waveDistance = waveProgress * totalLength;
        
        // Find where the wave is
        let accumulatedLength = 0;
        let waveX = pathPoints[0].x;
        let waveY = pathPoints[0].y;
        
        for (let i = 0; i < segmentLengths.length; i++) {
          if (accumulatedLength + segmentLengths[i] >= waveDistance) {
            const localProgress = (waveDistance - accumulatedLength) / segmentLengths[i];
            waveX = pathPoints[i].x + (pathPoints[i + 1].x - pathPoints[i].x) * localProgress;
            waveY = pathPoints[i].y + (pathPoints[i + 1].y - pathPoints[i].y) * localProgress;
            break;
          }
          accumulatedLength += segmentLengths[i];
        }
        
        // Draw the wave trail (glowing line from start to current position)
        const gradient = ctx.createLinearGradient(pathPoints[0].x, pathPoints[0].y, waveX, waveY);
        gradient.addColorStop(0, "rgba(56, 189, 248, 0.1)");
        gradient.addColorStop(0.7, "rgba(56, 189, 248, 0.6)");
        gradient.addColorStop(1, "rgba(56, 189, 248, 1)");
        
        ctx.strokeStyle = gradient;
        ctx.lineWidth = 3;
        ctx.shadowColor = "rgba(56, 189, 248, 1)";
        ctx.shadowBlur = 15;
        ctx.setLineDash([8, 4]);
        ctx.beginPath();
        
        // Draw path up to wave position
        let drawnLength = 0;
        ctx.moveTo(pathPoints[0].x, pathPoints[0].y);
        for (let i = 0; i < segmentLengths.length && drawnLength < waveDistance; i++) {
          const remainingDistance = waveDistance - drawnLength;
          if (segmentLengths[i] <= remainingDistance) {
            ctx.lineTo(pathPoints[i + 1].x, pathPoints[i + 1].y);
            drawnLength += segmentLengths[i];
          } else {
            ctx.lineTo(waveX, waveY);
            break;
          }
        }
        ctx.stroke();
        ctx.setLineDash([]);
        
        // Draw the wave pulse
        const pulseSize = 8 + Math.sin(phase * 4) * 3;
        const pulseOpacity = 0.8 + Math.sin(phase * 4) * 0.2;
        
        // Outer glow ring
        ctx.beginPath();
        ctx.strokeStyle = `rgba(56, 189, 248, ${pulseOpacity * 0.4})`;
        ctx.lineWidth = 2;
        ctx.arc(waveX, waveY, pulseSize + 8, 0, Math.PI * 2);
        ctx.stroke();
        
        // Middle ring
        ctx.beginPath();
        ctx.strokeStyle = `rgba(56, 189, 248, ${pulseOpacity * 0.7})`;
        ctx.lineWidth = 2;
        ctx.arc(waveX, waveY, pulseSize + 4, 0, Math.PI * 2);
        ctx.stroke();
        
        // Core pulse
        ctx.beginPath();
        ctx.fillStyle = `rgba(56, 189, 248, ${pulseOpacity})`;
        ctx.shadowColor = "rgba(56, 189, 248, 1)";
        ctx.shadowBlur = 20;
        ctx.arc(waveX, waveY, pulseSize, 0, Math.PI * 2);
        ctx.fill();
        ctx.shadowBlur = 0;
        
        // Light up proxies that the wave has passed
        pathPoints.slice(1, -1).forEach((point, index) => {
          const proxyDistance = segmentLengths.slice(0, index + 1).reduce((a, b) => a + b, 0);
          if (waveDistance >= proxyDistance) {
            // Proxy has been passed - light it up
            ctx.beginPath();
            ctx.fillStyle = "rgba(56, 189, 248, 0.8)";
            ctx.shadowColor = "rgba(56, 189, 248, 1)";
            ctx.shadowBlur = 12;
            ctx.arc(point.x, point.y, 6, 0, Math.PI * 2);
            ctx.fill();
            ctx.shadowBlur = 0;
          }
        });
        
        // Light up target when wave reaches it
        if (waveProgress >= 0.95) {
          const rippleSize = 15 + (waveProgress - 0.95) * 200;
          const rippleOpacity = Math.max(0, 1 - (waveProgress - 0.95) * 10);
          
          ctx.beginPath();
          ctx.strokeStyle = `rgba(56, 189, 248, ${rippleOpacity * 0.6})`;
          ctx.lineWidth = 3;
          ctx.shadowColor = "rgba(56, 189, 248, 1)";
          ctx.shadowBlur = 15;
          ctx.arc(targetPoint.x, targetPoint.y, rippleSize, 0, Math.PI * 2);
          ctx.stroke();
          
          ctx.beginPath();
          ctx.strokeStyle = `rgba(56, 189, 248, ${rippleOpacity * 0.3})`;
          ctx.arc(targetPoint.x, targetPoint.y, rippleSize + 10, 0, Math.PI * 2);
          ctx.stroke();
          ctx.shadowBlur = 0;
        }
      }
    }

    // Draw ALL hosts as simple squares like Uplink
    Object.values(world.hosts).forEach((host) => {
      const { x, y } = toCanvasPoint(host.geo.lat, host.geo.lon, width, height);
      const isTarget = focusHost === host.id;
      const isConnected = session?.connectedHost === host.id;
      
      // Draw host as simple square like Uplink
      const squareSize = isTarget ? 12 : 8;
      const squareColor = isTarget ? "rgba(248,146,60,1)" : isConnected ? "rgba(16, 185, 129, 0.8)" : "rgba(255, 255, 255, 0.6)";
      
      // Square outline
      ctx.strokeStyle = squareColor;
      ctx.lineWidth = isTarget ? 2 : 1;
      ctx.shadowColor = squareColor;
      ctx.shadowBlur = isTarget ? 8 : 4;
      ctx.strokeRect(x - squareSize / 2, y - squareSize / 2, squareSize, squareSize);
      
      // Fill for target/connected
      if (isTarget || isConnected) {
        ctx.fillStyle = squareColor;
        ctx.fillRect(x - squareSize / 2 + 1, y - squareSize / 2 + 1, squareSize - 2, squareSize - 2);
      }
      
      ctx.shadowBlur = 0;
      
      // Label for all hosts (like Uplink)
      ctx.fillStyle = "rgba(255, 255, 255, 0.9)";
      ctx.font = "9px 'IBM Plex Mono', monospace";
      ctx.textAlign = "left";
      ctx.fillText(host.label, x + squareSize / 2 + 4, y + 3);
    });

    // Draw proxy nodes as simple white squares like Uplink
    proxyPoints.forEach(({ proxy, point }) => {
      const isInRoute = route.hops.includes(proxy.id);
      const isHovered = hoveredProxyId === proxy.id;
      const size = isInRoute ? 10 : 6;
      const squareColor = isInRoute ? "rgba(16, 185, 129, 1)" : "rgba(255, 255, 255, 0.7)";

      // Outer glow ring for route nodes
      if (isInRoute) {
        ctx.beginPath();
        ctx.strokeStyle = `rgba(16, 185, 129, ${0.6 + Math.sin(phase) * 0.3})`;
        ctx.lineWidth = 2;
        ctx.shadowColor = "rgba(16, 185, 129, 0.8)";
        ctx.shadowBlur = 10;
        ctx.strokeRect(point.x - size / 2 - 3, point.y - size / 2 - 3, size + 6, size + 6);
        ctx.shadowBlur = 0;
      }

      // Simple square like Uplink
      ctx.strokeStyle = squareColor;
      ctx.lineWidth = isInRoute ? 2 : 1;
      ctx.shadowColor = squareColor;
      ctx.shadowBlur = isHovered ? 8 : (isInRoute ? 6 : 2);
      ctx.strokeRect(point.x - size / 2, point.y - size / 2, size, size);
      
      // Fill for route nodes
      if (isInRoute) {
        ctx.fillStyle = `rgba(16, 185, 129, ${0.3 + Math.sin(phase) * 0.2})`;
        ctx.fillRect(point.x - size / 2 + 1, point.y - size / 2 + 1, size - 2, size - 2);
      }
      
      ctx.shadowBlur = 0;

      // Heat indicator (red tint for high heat)
      if (proxy.heat > 0.5) {
        ctx.fillStyle = `rgba(239, 68, 68, ${proxy.heat * 0.6})`;
        ctx.fillRect(point.x - size / 2, point.y - size / 2, size, size);
      }
      
      // Label for proxies (like Uplink)
      ctx.fillStyle = "rgba(200, 200, 255, 0.8)";
      ctx.font = "8px 'IBM Plex Mono', monospace";
      ctx.textAlign = "left";
      ctx.fillText(proxy.label, point.x + size / 2 + 4, point.y + 3);
    });

    // Draw pulsing ring around target host (like Uplink)
    const targetHost = focusHost ? world.hosts[focusHost] : undefined;
    if (targetHost) {
      const { x, y } = toCanvasPoint(targetHost.geo.lat, targetHost.geo.lon, width, height);
      const pulseRadius = 15 + Math.sin(phase) * 3;
      const pulseOpacity = 0.5 + Math.sin(phase) * 0.3;

      // Multiple concentric rings like Uplink
      for (let i = 0; i < 3; i++) {
        ctx.beginPath();
        ctx.strokeStyle = `rgba(248,146,60, ${pulseOpacity - i * 0.15})`;
        ctx.lineWidth = 1;
        ctx.shadowColor = "rgba(248,146,60, 0.6)";
        ctx.shadowBlur = 8 - i * 2;
        ctx.arc(x, y, pulseRadius + i * 4, 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.shadowBlur = 0;
    }
  }, [nodes.proxies, nodes.hosts, route.hops, focusHost, phase, routeAnimationPhase, hoveredProxyId, world, toCanvasPoint, session, isFullscreen, scanAnimation, scanWaveProgress]);

  const handlePointer = (event: PointerEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const { width, height } = canvas;
    const mouseX = event.clientX - rect.left;
    const mouseY = event.clientY - rect.top;
    
    // Find closest proxy
    const proxiesArr = Object.values(world.proxies);
    let closestProxy: { proxyId: string; dist: number } | null = null;
    
    for (const proxy of proxiesArr) {
      const point = toCanvasPoint(proxy.geo.lat, proxy.geo.lon, width, height);
      const dist = Math.hypot(point.x - mouseX, point.y - mouseY);
      if (!closestProxy || dist < closestProxy.dist) {
        closestProxy = { proxyId: proxy.id, dist };
      }
    }
    
    if (closestProxy && closestProxy.dist < 20) {
      const node = world.proxies[closestProxy.proxyId];
      const isInRoute = route.hops.includes(closestProxy.proxyId);
      setHoveredProxyId(closestProxy.proxyId);
      setHoveredLabel(
        `${node.label} | Anon: ${(node.anonymity * 100).toFixed(0)}% | Heat: ${(node.heat * 100).toFixed(0)}% | Cost: ${node.costPerUse}c${isInRoute ? " [IN ROUTE]" : " [Click to add]"}`
      );
    } else {
      setHoveredProxyId(null);
      setHoveredLabel(null);
    }
  };

  const handleClick = (event: MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas || !onProxyAdd) return;
    const rect = canvas.getBoundingClientRect();
    const { width, height } = canvas;
    const mouseX = event.clientX - rect.left;
    const mouseY = event.clientY - rect.top;
    
    // Find closest proxy
    const proxiesArr = Object.values(world.proxies);
    let closestProxy: { proxyId: string; dist: number } | null = null;
    
    for (const proxy of proxiesArr) {
      const point = toCanvasPoint(proxy.geo.lat, proxy.geo.lon, width, height);
      const dist = Math.hypot(point.x - mouseX, point.y - mouseY);
      if (!closestProxy || dist < closestProxy.dist) {
        closestProxy = { proxyId: proxy.id, dist };
      }
    }
    
    if (closestProxy && closestProxy.dist < 20) {
      onProxyAdd(closestProxy.proxyId);
    }
  };

  const toggleFullscreen = () => {
    if (!containerRef.current) return;
    
    if (!isFullscreen) {
      const elem = containerRef.current;
      if (elem.requestFullscreen) {
        elem.requestFullscreen();
      } else {
        const webkitElem = elem as HTMLElement & { webkitRequestFullscreen?: () => void };
        const msElem = elem as HTMLElement & { msRequestFullscreen?: () => void };
        if (webkitElem.webkitRequestFullscreen) {
          webkitElem.webkitRequestFullscreen();
        } else if (msElem.msRequestFullscreen) {
          msElem.msRequestFullscreen();
        }
      }
      setIsFullscreen(true);
    } else {
      if (document.exitFullscreen) {
        document.exitFullscreen();
      } else {
        const webkitDoc = document as Document & { webkitExitFullscreen?: () => void };
        const msDoc = document as Document & { msExitFullscreen?: () => void };
        if (webkitDoc.webkitExitFullscreen) {
          webkitDoc.webkitExitFullscreen();
        } else if (msDoc.msExitFullscreen) {
          msDoc.msExitFullscreen();
        }
      }
      setIsFullscreen(false);
    }
  };

  useEffect(() => {
    const handleFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement);
    };
    
    document.addEventListener("fullscreenchange", handleFullscreenChange);
    document.addEventListener("webkitfullscreenchange", handleFullscreenChange);
    document.addEventListener("msfullscreenchange", handleFullscreenChange);
    
    return () => {
      document.removeEventListener("fullscreenchange", handleFullscreenChange);
      document.removeEventListener("webkitfullscreenchange", handleFullscreenChange);
      document.removeEventListener("msfullscreenchange", handleFullscreenChange);
    };
  }, []);

  // Maintain 2:1 aspect ratio for proper world map projection
  const canvasWidth = isFullscreen ? 1920 : large ? 1400 : 500;
  const canvasHeight = isFullscreen ? 960 : large ? 700 : 250;

  // Trace status colors
  const traceColor = trace?.status === "LOCKDOWN" ? "bg-rose-500" 
    : trace?.status === "HUNT" ? "bg-orange-500" 
    : trace?.status === "ALERT" ? "bg-amber-500" 
    : "bg-emerald-500";
  
  const traceTextColor = trace?.status === "LOCKDOWN" ? "text-rose-400" 
    : trace?.status === "HUNT" ? "text-orange-400" 
    : trace?.status === "ALERT" ? "text-amber-400" 
    : "text-emerald-400";

  const containerClass = isFullscreen ? 'fixed inset-0 z-50 bg-black flex items-center justify-center' 
    : large ? 'w-full min-h-[350px] rounded border border-zinc-800 bg-black/60 flex items-center justify-center overflow-hidden' 
    : 'w-full min-h-[180px] rounded border border-zinc-800 bg-black/60 flex items-center justify-center overflow-hidden';

  return (
    <div 
      ref={containerRef}
      className={`relative ${containerClass}`}
    >
      {/* Top left: Title */}
      <div className="absolute top-3 left-3 z-10 rounded bg-black/80 px-3 py-1.5 text-[0.7rem] uppercase tracking-[0.2em] text-zinc-400">
        Network Map
      </div>

      {/* Top center: Trace Level (only in large mode) */}
      {large && trace && (
        <div className="absolute top-3 left-1/2 -translate-x-1/2 z-10 flex items-center gap-4 rounded bg-black/80 px-4 py-2">
          <div className="flex items-center gap-2">
            <span className="text-[0.65rem] uppercase tracking-[0.15em] text-zinc-500">Trace</span>
            <div className="w-32 h-2 bg-zinc-800 rounded-full overflow-hidden">
              <div 
                className={`h-full ${traceColor} transition-all duration-300`}
                style={{ width: `${Math.min(trace.level, 100)}%` }}
              />
            </div>
            <span className={`text-[0.75rem] font-bold ${traceTextColor}`}>{trace.level.toFixed(1)}%</span>
          </div>
          <div className={`px-2 py-0.5 rounded text-[0.65rem] font-bold uppercase ${traceTextColor} ${traceColor}/20`}>
            {trace.status}
          </div>
        </div>
      )}

      {/* Top right: Controls */}
      <div className="absolute top-3 right-3 z-10 flex items-center gap-3">
        <div className="flex gap-2 text-[0.6rem] text-zinc-500">
          <div className="flex items-center gap-1">
            <div className="h-2 w-2 rounded-full bg-blue-400" />
            <span>Proxy</span>
          </div>
          <div className="flex items-center gap-1">
            <div className="h-2 w-2 rounded-full bg-orange-400" />
            <span>Target</span>
          </div>
        </div>
        <button
          onClick={toggleFullscreen}
          className="rounded bg-black/80 px-2 py-1 text-[0.65rem] text-zinc-400 hover:bg-black/90 hover:text-zinc-300 transition-colors"
          title={isFullscreen ? "Exit fullscreen" : "Fullscreen"}
        >
          {isFullscreen ? "✕ Exit" : "⛶ Full"}
        </button>
      </div>

      <canvas
        ref={canvasRef}
        width={canvasWidth}
        height={canvasHeight}
        className="max-w-full max-h-full"
        style={{ aspectRatio: '2 / 1' }}
        onPointerMove={handlePointer}
        onPointerLeave={() => setHoveredLabel(null)}
        onClick={handleClick}
      />

      {/* Bottom bar */}
      <div className="absolute bottom-3 left-3 right-3 flex items-center justify-between">
        <div className="rounded bg-black/70 px-3 py-1.5 text-[0.7rem] text-zinc-300">
          {hoveredLabel ?? (route.hops.length > 0 
            ? `Route: ${route.hops.length} hop${route.hops.length > 1 ? "s" : ""} | Anonymity: ${(route.anonymity * 100).toFixed(0)}% | Latency: ${route.latencyMs}ms` 
            : "Click proxy nodes to build route")}
        </div>
        {route.hops.length > 0 && (
          <div className="rounded bg-emerald-500/20 px-3 py-1.5 text-[0.7rem] font-semibold text-emerald-300">
            {route.hops.length} hop{route.hops.length > 1 ? "s" : ""} active
          </div>
        )}
      </div>
    </div>
  );
}
