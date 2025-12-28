"use client";

import { useEffect, useRef, useState } from "react";
import { useGameStore } from "@/app/lib/persistence/store";

// Matrix/binary rain character set
const chars = "01アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン";

interface RainDrop {
  id: number;
  x: number;
  speed: number;
  chars: string[];
  opacity: number;
  delay: number;
}

export default function VfxThreeOverlay() {
  const traceStatus = useGameStore((state) => state.gameState.trace.status);
  const lastEvent = useGameStore((state) => state.lastVfxEvent);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 });
  const raindropsRef = useRef<RainDrop[]>([]);
  const frameRef = useRef<number>(0);

  // Trace-based intensity
  const intensity = traceStatus === "LOCKDOWN" ? 0.12 : traceStatus === "HUNT" ? 0.08 : traceStatus === "ALERT" ? 0.05 : 0.03;
  const baseColor = traceStatus === "LOCKDOWN" ? [255, 80, 80] : traceStatus === "HUNT" ? [255, 140, 60] : traceStatus === "ALERT" ? [255, 180, 60] : [20, 180, 160];

  // Handle resize
  useEffect(() => {
    const updateDimensions = () => {
      setDimensions({
        width: window.innerWidth,
        height: window.innerHeight,
      });
    };
    updateDimensions();
    window.addEventListener("resize", updateDimensions);
    return () => window.removeEventListener("resize", updateDimensions);
  }, []);

  // Initialize raindrops
  useEffect(() => {
    if (dimensions.width === 0) return;
    
    const columnWidth = 20;
    const columns = Math.floor(dimensions.width / columnWidth);
    const drops: RainDrop[] = [];
    
    for (let i = 0; i < columns; i++) {
      // Only create drops for some columns (sparse)
      if (Math.random() > 0.7) {
        const charCount = 8 + Math.floor(Math.random() * 12);
        drops.push({
          id: i,
          x: i * columnWidth + columnWidth / 2,
          speed: 0.3 + Math.random() * 0.5,
          chars: Array.from({ length: charCount }, () => chars[Math.floor(Math.random() * chars.length)]),
          opacity: 0.03 + Math.random() * 0.04,
          delay: Math.random() * dimensions.height,
        });
      }
    }
    
    raindropsRef.current = drops;
  }, [dimensions.width, dimensions.height]);

  // Animation loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || dimensions.width === 0) return;
    
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let yOffsets = raindropsRef.current.map(drop => -drop.delay);
    let lastTime = 0;

    const animate = (time: number) => {
      const delta = time - lastTime;
      lastTime = time;

      ctx.clearRect(0, 0, dimensions.width, dimensions.height);
      
      // Very subtle background
      ctx.fillStyle = "rgba(0, 0, 0, 0)";
      ctx.fillRect(0, 0, dimensions.width, dimensions.height);

      raindropsRef.current.forEach((drop, index) => {
        const charHeight = 14;
        yOffsets[index] += drop.speed * (delta / 16);
        
        // Reset when off screen
        if (yOffsets[index] > dimensions.height + drop.chars.length * charHeight) {
          yOffsets[index] = -drop.chars.length * charHeight;
          // Randomize chars on reset
          drop.chars = drop.chars.map(() => chars[Math.floor(Math.random() * chars.length)]);
        }

        // Draw each character in the column
        drop.chars.forEach((char, charIndex) => {
          const y = yOffsets[index] + charIndex * charHeight;
          if (y < -charHeight || y > dimensions.height) return;

          // Fade based on position in trail
          const trailFade = 1 - (charIndex / drop.chars.length);
          const finalOpacity = drop.opacity * intensity * trailFade;
          
          if (finalOpacity < 0.005) return;

          // Head of trail is brighter
          const isHead = charIndex === 0;
          const [r, g, b] = baseColor;
          
          ctx.font = "12px 'IBM Plex Mono', monospace";
          ctx.fillStyle = isHead 
            ? `rgba(${r}, ${g}, ${b}, ${finalOpacity * 3})`
            : `rgba(${r}, ${g}, ${b}, ${finalOpacity})`;
          ctx.fillText(char, drop.x, y);
        });
      });

      frameRef.current = requestAnimationFrame(animate);
    };

    frameRef.current = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(frameRef.current);
  }, [dimensions, intensity, baseColor]);

  // Flash effect on events
  const [flash, setFlash] = useState(false);
  useEffect(() => {
    if (lastEvent?.type === "scan" || lastEvent?.type === "alert") {
      setFlash(true);
      setTimeout(() => setFlash(false), 150);
    }
  }, [lastEvent]);

  return (
    <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
      {/* Matrix rain canvas */}
      <canvas
        ref={canvasRef}
        width={dimensions.width}
        height={dimensions.height}
        className="absolute inset-0"
        style={{ opacity: 0.6 }}
      />
      
      {/* Subtle vignette */}
      <div 
        className="absolute inset-0"
        style={{
          background: "radial-gradient(ellipse at center, transparent 0%, transparent 40%, rgba(0,0,0,0.4) 100%)",
        }}
      />
      
      {/* Event flash overlay */}
      {flash && (
        <div 
          className="absolute inset-0 transition-opacity duration-150"
          style={{
            backgroundColor: lastEvent?.type === "alert" ? "rgba(239, 68, 68, 0.05)" : "rgba(56, 189, 248, 0.03)",
          }}
        />
      )}
      
      {/* Trace status overlays */}
      {traceStatus === "LOCKDOWN" && (
        <div className="absolute inset-0 animate-pulse bg-rose-500/5" />
      )}
      {traceStatus === "HUNT" && (
        <div className="absolute inset-0 bg-orange-500/3" />
      )}
      
      {/* Subtle scanlines */}
      <div 
        className="absolute inset-0 opacity-[0.015]"
        style={{
          backgroundImage: "repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(255,255,255,0.03) 2px, rgba(255,255,255,0.03) 4px)",
        }}
      />
    </div>
  );
}
