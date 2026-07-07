"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Canvas, useFrame } from "@react-three/fiber";
import * as THREE from "three";
import { useGameStore } from "@/app/lib/persistence/store";
import type { RfEmitter } from "@/types/game";

// ELINT spectrum waterfall — a Three.js scrolling spectrogram of the RF
// environment. Each world emitter is a persistent peak at its band; once you
// `collect rf` it (characterize its signature) the trace brightens. The "aha"
// is reading the unlabeled emitter at a target site off the waterfall.

const BINS = 96; // frequency bins (texture width)
const ROWS = 64; // time rows (texture height)
const BANDS = ["433 MHz", "900 MHz", "1.2 GHz", "2.4 GHz", "5.8 GHz"]; // low -> high

function bandBin(band: string): number {
  const i = BANDS.indexOf(band);
  return Math.round((((i < 0 ? 2 : i) + 0.5) / BANDS.length) * BINS);
}

function Waterfall({ emitters, characterized }: { emitters: RfEmitter[]; characterized: Set<string> }) {
  const data = useMemo(() => new Uint8Array(BINS * ROWS * 4), []);
  const tex = useMemo(() => {
    const t = new THREE.DataTexture(data, BINS, ROWS, THREE.RGBAFormat);
    t.needsUpdate = true;
    return t;
  }, [data]);
  const peaks = useMemo(
    () => emitters.map((e) => ({ bin: bandBin(e.band), strong: characterized.has(e.id) })),
    [emitters, characterized]
  );
  const acc = useRef(0);

  useFrame((_, dt) => {
    acc.current += dt;
    if (acc.current < 0.05) return; // ~20 rows/sec — a calm waterfall
    acc.current = 0;
    data.copyWithin(0, BINS * 4, BINS * ROWS * 4); // scroll rows up by one
    const top = (ROWS - 1) * BINS * 4;
    for (let x = 0; x < BINS; x++) {
      let v = 0.05 + Math.random() * 0.05; // noise floor
      for (const p of peaks) {
        const d = x - p.bin;
        v += (p.strong ? 0.95 : 0.55) * Math.exp(-(d * d) / 7);
      }
      v = Math.min(1, v);
      const idx = top + x * 4;
      data[idx] = Math.floor(40 + 190 * v * v); // r (warms at peaks)
      data[idx + 1] = Math.floor(60 + 170 * v); // g
      data[idx + 2] = Math.floor(70 + 180 * v); // b
      data[idx + 3] = Math.floor(35 + 210 * v); // a
    }
    tex.needsUpdate = true;
  });

  return (
    <mesh rotation={[-Math.PI / 2.5, 0, 0]} position={[0, -0.15, 0]}>
      <planeGeometry args={[6, 4]} />
      <meshBasicMaterial map={tex} transparent toneMapped={false} />
    </mesh>
  );
}

export default function SpectrumWaterfall() {
  // Select the stable record; deriving the array in the selector would return a
  // new reference each call and loop useSyncExternalStore.
  const emittersRecord = useGameStore((s) => s.gameState.world.emitters);
  const emitters = useMemo(() => Object.values(emittersRecord), [emittersRecord]);
  const evidence = useGameStore((s) => s.gameState.evidence);
  const characterized = useMemo(
    () => new Set(evidence.filter((e) => e.factKind === "signature").map((e) => e.sourceId)),
    [evidence]
  );

  const [mounted, setMounted] = useState(false);
  const [webgl, setWebgl] = useState(true);
  useEffect(() => {
    setMounted(true);
    try {
      const c = document.createElement("canvas");
      setWebgl(!!(c.getContext("webgl2") || c.getContext("webgl")));
    } catch {
      setWebgl(false);
    }
  }, []);

  // Only run the WebGL render loop while the waterfall is actually on screen.
  // Off-screen (scrolled away or display:none during onboarding) it was still
  // rendering at 60fps — wasted GPU/CPU. IntersectionObserver flips frameloop.
  const viewRef = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    const el = viewRef.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => setVisible(e.isIntersecting), { threshold: 0.05 });
    io.observe(el);
    return () => io.disconnect();
  }, [mounted]);

  return (
    <div className="rounded-lg border border-cyan-500/20 bg-black/60 p-4 font-mono">
      <div className="mb-2 flex items-center justify-between text-[0.7rem]">
        <span className="tracking-[0.2em] text-cyan-300">ELINT · SPECTRUM WATERFALL</span>
        <span className="text-zinc-500">
          {characterized.size}/{emitters.length} characterized
        </span>
      </div>
      <div ref={viewRef} className="h-44 w-full overflow-hidden rounded bg-[#02060c]">
        {mounted && webgl ? (
          <Canvas
            camera={{ position: [0, 2.1, 3.3], fov: 52 }}
            dpr={[1, 1.5]}
            gl={{ alpha: true }}
            frameloop={visible ? "always" : "never"}
          >
            <Waterfall emitters={emitters} characterized={characterized} />
          </Canvas>
        ) : (
          <div className="flex h-full items-center justify-center text-[0.64rem] text-zinc-600">
            {mounted ? "WebGL unavailable — spectrum view disabled" : "…"}
          </div>
        )}
      </div>
      <p className="mt-2 text-[0.6rem] leading-snug text-zinc-600">
        peaks are live emitters · <span className="text-zinc-400">sweep</span> to enumerate the band ·{" "}
        <span className="text-zinc-400">collect rf &lt;host&gt;</span> to characterize one (brightens its trace)
      </p>
    </div>
  );
}
