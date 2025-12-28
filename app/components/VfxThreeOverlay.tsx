"use client";

import { Canvas, useFrame } from "@react-three/fiber";
import { useRef } from "react";
import * as THREE from "three";
import { useGameStore } from "@/app/lib/persistence/store";

const particlePositions: [number, number, number][] = Array.from({ length: 60 }, (_, index) => [
  ((index % 5) - 2) * 0.8,
  Math.sin(index * 0.35) * 1.2,
  ((index % 3) - 1) * 0.6,
]);

const ParticleField = ({ eventType }: { eventType: string | null }) => {
  const group = useRef<THREE.Group>(null);

  useFrame(({ clock }) => {
    if (!group.current) return;
    const speed = eventType === "scan" ? 0.15 : eventType === "alert" ? 0.25 : 0.08;
    group.current.rotation.y = clock.elapsedTime * speed;
    group.current.children.forEach((child, index) => {
      const intensity = eventType === "scan" ? 0.4 : eventType === "alert" ? 0.6 : 0.2;
      child.position.y = Math.sin(clock.elapsedTime * 0.5 + index) * intensity;
    });
  });

  const particleColor = eventType === "alert" ? "tomato" : eventType === "scan" ? "#38bdf8" : eventType === "success" ? "#a3e635" : "#14b8a6";
  const opacity = eventType ? 0.8 : 0.4;

  return (
    <group ref={group}>
      {particlePositions.map((position, index) => (
        <mesh key={index} position={position}>
          <sphereGeometry args={[0.05, 8, 8]} />
          <meshBasicMaterial
            color={particleColor}
            opacity={opacity}
            transparent
          />
        </mesh>
      ))}
    </group>
  );
};

const PulseRing = ({ eventType }: { eventType: string | null }) => {
  const mesh = useRef<THREE.Mesh>(null);
  useFrame(({ clock }) => {
    if (!mesh.current) return;
    const pulseSpeed = eventType === "scan" ? 3 : eventType === "alert" ? 4 : 2;
    const pulseIntensity = eventType ? 0.15 : 0.08;
    mesh.current.scale.setScalar(1 + Math.sin(clock.elapsedTime * pulseSpeed) * pulseIntensity);
  });
  
  const ringColor = eventType === "alert" ? "#f87171" : eventType === "scan" ? "#38bdf8" : eventType === "success" ? "#a3e635" : "#14b8a6";
  const opacity = eventType ? 0.7 : 0.3;
  
  return (
    <mesh ref={mesh} rotation={[Math.PI / 2, 0, 0]}>
      <ringGeometry args={[0.5, 0.6, 64]} />
      <meshBasicMaterial color={ringColor} transparent opacity={opacity} />
    </mesh>
  );
};

export default function VfxThreeOverlay() {
  const lastEvent = useGameStore((state) => state.lastVfxEvent);
  const traceStatus = useGameStore((state) => state.gameState.trace.status);
  
  // Adjust particle intensity based on trace status
  const intensity = traceStatus === "LOCKDOWN" ? 1.2 : traceStatus === "HUNT" ? 0.9 : traceStatus === "ALERT" ? 0.6 : 0.4;
  
  return (
    <div className="pointer-events-none absolute inset-0 -z-10">
      <Canvas camera={{ position: [0, 0, 4], fov: 50 }}>
        <color attach="background" args={[0, 0, 0]} />
        <ambientLight intensity={0.3 + intensity * 0.2} />
        <pointLight position={[5, 5, 5]} intensity={0.5 + intensity * 0.3} />
        <ParticleField eventType={lastEvent?.type ?? null} />
        <PulseRing eventType={lastEvent?.type ?? null} />
      </Canvas>
      {traceStatus === "LOCKDOWN" && (
        <div className="absolute inset-0 animate-pulse bg-red-500/10" />
      )}
      {traceStatus === "HUNT" && (
        <div className="absolute inset-0 bg-orange-500/5" />
      )}
    </div>
  );
}
